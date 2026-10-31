package org.untrash.untrash_app

import android.app.Activity
import android.content.Intent
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import java.util.concurrent.Executors

/**
 * The UntrashMesh tunnel (docs: app-api.md §1) on the official WireGuard
 * tunnel library. Dart builds the wg-quick config; this side only asks for
 * the VPN permission and brings the one tunnel up or down.
 */
class MeshTunnel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val backend by lazy { GoBackend(activity.applicationContext) }
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null

    private object Mesh : Tunnel {
        override fun getName() = "untrash-mesh"
        override fun onStateChange(newState: Tunnel.State) {}
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val intent = GoBackend.VpnService.prepare(activity)
                if (intent == null) {
                    result.success(true)
                } else {
                    pending = result
                    activity.startActivityForResult(intent, REQUEST_VPN)
                }
            }
            "up" -> run(result) {
                val text = call.argument<String>("config") ?: throw IllegalArgumentException("no config")
                val config = Config.parse(BufferedReader(StringReader(text)))
                backend.setState(Mesh, Tunnel.State.UP, config)
                null
            }
            "down" -> run(result) {
                backend.setState(Mesh, Tunnel.State.DOWN, null)
                null
            }
            "handshakes" -> run(result) {
                if (backend.getState(Mesh) != Tunnel.State.UP) {
                    emptyMap<String, Long>()
                } else {
                    val stats = backend.getStatistics(Mesh)
                    stats.peers().associate { it.toBase64() to (stats.peer(it)?.latestHandshakeEpochMillis ?: 0L) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Backend calls block; they run off the UI thread, answers go back on it. */
    private fun run(result: MethodChannel.Result, body: () -> Any?) {
        worker.execute {
            try {
                val v = body()
                activity.runOnUiThread { result.success(v) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("tunnel", e.message ?: e.toString(), null) }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        pending?.success(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }

    companion object {
        const val REQUEST_VPN = 7340
    }
}
