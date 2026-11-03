package org.untrash.untrash_app

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.InetEndpoint
import com.wireguard.config.Peer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * The UntrashMesh tunnel (docs: app-api.md §1) on the official WireGuard
 * tunnel library, owned by the app process, not by an activity: other apps
 * (the Home Assistant app over the NAS's HA proxy) use it while the
 * UntrashApp is in the background or swiped away.
 *
 * Dart builds the wg-quick config and gives every NAS peer its endpoints
 * (LAN first, then public). WireGuard itself never changes an endpoint, so
 * this side does, like untrash-mesh pick_endpoint() on the NAS:
 * - when the real network changes (WLAN <-> mobile data) the tunnel starts
 *   again from each peer's first endpoint;
 * - when no peer has a handshake 20 s after a start (or none for 200 s;
 *   WireGuard re-handshakes about every 2 min under keepalive), every peer
 *   moves on to its next endpoint. After two rounds without luck it waits
 *   60 s between tries (a NAS that is off must not drain the battery).
 */
object MeshVpn {
    private const val SETTLE_MS = 8_000L
    private const val STALE_MS = 200_000L
    private const val SLOW_MS = 60_000L
    private const val MIN_GAP_MS = 20_000L
    private const val DIR_EVERY_MS = 300_000L

    private object Mesh : Tunnel {
        override fun getName() = "untrash-mesh"
        override fun onStateChange(newState: Tunnel.State) {}
    }

    private lateinit var backend: GoBackend
    private val exec = Executors.newSingleThreadScheduledExecutor()
    private var base: Config? = null
    private var endpoints: Map<String, List<String>> = emptyMap()
    private val index = HashMap<String, Int>()
    private val tries = HashMap<String, Int>()
    private var appliedAt = 0L
    private var watch: ScheduledFuture<*>? = null
    private var askedDirAt = 0L

    /**
     * Calls into Dart on the process-wide engine: "recover" (no NAS answers
     * on any endpoint: ask the mesh directories where they are now) and
     * "networkChanged" (tell the directories where we are). The engine runs
     * as long as the process, also without an activity.
     */
    var events: MethodChannel? = null

    private fun tellDart(method: String) {
        val ch = events ?: return
        Handler(Looper.getMainLooper()).post {
            try {
                ch.invokeMethod(method, null)
            } catch (_: Exception) {
            }
        }
    }
    private var pendingNet: ScheduledFuture<*>? = null

    @Synchronized
    fun init(ctx: Context) {
        if (::backend.isInitialized) return
        val app = ctx.applicationContext
        backend = GoBackend(app)
        // only real networks: the tunnel itself is a VPN network. A restart of
        // the tunnel makes Android report the real networks again, so only a
        // change of the preferred one (WLAN before mobile data) counts; the
        // first version restarted on every report and looped every ~5 s
        // (x15ultra on untrash1, 2026-11-02)
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        (app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
            .registerNetworkCallback(req, object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    networkSeen(network, caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
                }

                override fun onLost(network: Network) = networkGone(network)
            })
    }

    private val networks = HashMap<Network, Boolean>()      // real network -> is WLAN/Ethernet
    private var preferred: Network? = null

    @Synchronized
    private fun networkSeen(n: Network, wlan: Boolean) {
        networks[n] = wlan
        preferredChanged()
    }

    @Synchronized
    private fun networkGone(n: Network) {
        networks.remove(n)
        preferredChanged()
    }

    private fun preferredChanged() {
        val best = networks.entries.firstOrNull { it.value }?.key ?: networks.keys.firstOrNull()
        if (best == preferred) return
        val first = preferred == null
        preferred = best
        if (first || best == null) return                    // start-up, or no network at all
        pendingNet?.cancel(false)
        pendingNet = exec.schedule({ restart() }, 2, TimeUnit.SECONDS)   // a switch reports several times
    }

    @Synchronized
    private fun restart() {
        if (base == null) return
        index.clear()
        tries.clear()
        try {
            apply("network changed")
        } catch (_: Exception) {
        }
        tellDart("networkChanged")
    }

    @Synchronized
    fun up(config: Config, eps: Map<String, List<String>>) {
        // the app calls this on every return to the foreground: a running
        // tunnel with the same peers stays as it is (connections of other
        // apps through it are not cut)
        if (backend.getState(Mesh) == Tunnel.State.UP && base?.toWgQuickString() == config.toWgQuickString() &&
            endpoints == eps
        ) {
            return
        }
        base = config
        endpoints = eps
        index.clear()
        tries.clear()
        apply("app")
        if (watch == null) watch = exec.scheduleWithFixedDelay({ check() }, 4, 4, TimeUnit.SECONDS)
    }

    @Synchronized
    fun down() {
        base = null
        watch?.cancel(false)
        watch = null
        backend.setState(Mesh, Tunnel.State.DOWN, null)
    }

    @Synchronized
    fun handshakes(): Map<String, Long> {
        if (!::backend.isInitialized || backend.getState(Mesh) != Tunnel.State.UP) return emptyMap()
        val stats = backend.getStatistics(Mesh)
        return stats.peers().associate { it.toBase64() to (stats.peer(it)?.latestHandshakeEpochMillis ?: 0L) }
    }

    /** The config with each peer at its current endpoint. */
    private fun build(): Config {
        val b = base!!
        val peers = b.peers.map { p ->
            val key = p.publicKey.toBase64()
            val eps = endpoints[key].orEmpty()
            if (eps.isEmpty()) {
                p
            } else {
                val nb = Peer.Builder()
                    .setPublicKey(p.publicKey)
                    .addAllowedIps(p.allowedIps)
                    .setEndpoint(InetEndpoint.parse(eps[(index[key] ?: 0) % eps.size]))
                p.persistentKeepalive.ifPresent { nb.setPersistentKeepalive(it) }
                p.preSharedKey.ifPresent { nb.setPreSharedKey(it) }
                nb.build()
            }
        }
        return Config.Builder().setInterface(b.`interface`).addPeers(peers).build()
    }

    /** The last starts of the tunnel with their reason (shown in the app: no adb needed to see a loop). */
    private val starts = ArrayDeque<String>()

    @Synchronized
    fun starts(): List<String> = starts.toList()

    private fun apply(reason: String) {
        backend.setState(Mesh, Tunnel.State.UP, build())
        appliedAt = System.currentTimeMillis()
        val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date(appliedAt))
        starts.addFirst("$t $reason")
        while (starts.size > 8) starts.removeLast()
    }

    @Synchronized
    private fun check() {
        if (base == null || backend.getState(Mesh) != Tunnel.State.UP) return
        val now = System.currentTimeMillis()
        val hs = handshakes()
        fun fresh(key: String): Boolean {
            val last = hs[key] ?: 0L
            return last >= appliedAt || (last > 0 && now - last < STALE_MS)
        }
        // a restart cuts every peer, so only when none of them answers (the
        // network changed under us); one NAS that is off or unreachable
        // must not tear down the tunnel to the others
        if (endpoints.keys.any { fresh(it) }) {
            tries.clear()
            return
        }
        val movable = endpoints.filter { it.value.size > 1 }
        if (movable.isEmpty()) {
            // nothing to rotate: only the directories can help
            if (now - appliedAt > SETTLE_MS && now - askedDirAt > DIR_EVERY_MS) {
                askedDirAt = now
                tellDart("recover")
            }
            return
        }
        val n = tries.values.maxOrNull() ?: 0
        val slow = n >= 2 * movable.values.maxOf { it.size }
        // two rounds without luck: the NAS may have a new address; the mesh
        // directories (a Nextcloud) know it (Dart asks them, then calls up()
        // with the fresher endpoints). At most every 5 minutes.
        if (slow && now - askedDirAt > DIR_EVERY_MS) {
            askedDirAt = now
            tellDart("recover")
        }
        val wait = if (slow) SLOW_MS else SETTLE_MS
        if (now - appliedAt < maxOf(wait, MIN_GAP_MS)) return
        for (key in movable.keys) {
            index[key] = (index[key] ?: 0) + 1
            tries[key] = (tries[key] ?: 0) + 1
        }
        try {
            apply("no handshake, next endpoint")
        } catch (_: Exception) {
        }
    }
}

/**
 * The Flutter side of the tunnel, registered once on the process-wide
 * engine (UntrashApplication): up, down, handshakes, starts work without an
 * activity; only asking for the VPN permission needs one.
 */
object MeshTunnelChannel : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private lateinit var app: Context

    /** The activity in front, for the permission dialog; null in the background. */
    var activity: Activity? = null

    fun init(ctx: Context) {
        app = ctx.applicationContext
        MeshVpn.init(app)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val intent = GoBackend.VpnService.prepare(app)
                val a = activity
                when {
                    intent == null -> result.success(true)
                    a == null -> result.success(false)        // in the background: the user decides when the app is open
                    else -> {
                        pending = result
                        a.startActivityForResult(intent, REQUEST_VPN)
                    }
                }
            }
            "up" -> run(result) {
                val text = call.argument<String>("config") ?: throw IllegalArgumentException("no config")
                val eps = call.argument<Map<String, List<String>>>("endpoints") ?: emptyMap()
                MeshVpn.up(Config.parse(BufferedReader(StringReader(text))), eps)
                null
            }
            "down" -> run(result) {
                MeshVpn.down()
                null
            }
            "handshakes" -> run(result) { MeshVpn.handshakes() }
            "starts" -> run(result) { MeshVpn.starts() }
            else -> result.notImplemented()
        }
    }

    /** Backend calls block; they run off the main thread, answers go back on it. */
    private fun run(result: MethodChannel.Result, body: () -> Any?) {
        worker.execute {
            try {
                val v = body()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("tunnel", e.message ?: e.toString(), null) }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        pending?.success(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }

    const val REQUEST_VPN = 7340
}
