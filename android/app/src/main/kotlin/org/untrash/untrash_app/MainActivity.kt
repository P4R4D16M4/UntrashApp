package org.untrash.untrash_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tunnel: MeshTunnel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val t = MeshTunnel(this)
        tunnel = t
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.untrash.app/tunnel").setMethodCallHandler(t)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.untrash.app/download")
            .setMethodCallHandler(Downloads(this))
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (tunnel?.onActivityResult(requestCode, resultCode) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
