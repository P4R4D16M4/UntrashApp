package org.untrash.untrash_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * One Flutter engine for the whole process, not one per activity: the app
 * state (mesh, keys, the directory sync) keeps running while the tunnel is
 * used by other apps and the UntrashApp is in the background or swiped away.
 */
class UntrashApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        val messenger = engine.dartExecutor.binaryMessenger
        MeshTunnelChannel.init(this)
        MethodChannel(messenger, "org.untrash.app/tunnel").setMethodCallHandler(MeshTunnelChannel)
        MethodChannel(messenger, "org.untrash.app/download").setMethodCallHandler(Downloads(this))
        MeshVpn.events = MethodChannel(messenger, "org.untrash.app/tunnel-events")
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE, engine)
    }

    companion object {
        const val ENGINE = "main"
    }
}
