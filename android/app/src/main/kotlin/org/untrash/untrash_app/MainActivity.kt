package org.untrash.untrash_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

/** Shows the process-wide engine of UntrashApplication. */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId() = UntrashApplication.ENGINE

    override fun onResume() {
        super.onResume()
        MeshTunnelChannel.activity = this
    }

    override fun onDestroy() {
        if (MeshTunnelChannel.activity === this) MeshTunnelChannel.activity = null
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!MeshTunnelChannel.onActivityResult(requestCode, resultCode)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
