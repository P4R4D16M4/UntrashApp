package org.untrash.untrash_app

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Downloads started in the Desk web view go to Android's DownloadManager,
 * with the web view's session cookie (the Desk sends files as attachments,
 * which a web view cannot save by itself). The NAS's mesh address is routed
 * through the tunnel for every app, the DownloadManager included.
 */
class Downloads(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "download") return result.notImplemented()
        try {
            val url = call.argument<String>("url") ?: throw IllegalArgumentException("no url")
            val name = call.argument<String>("name")?.takeIf { it.isNotBlank() }
                ?: URLUtil.guessFileName(url, null, null)
            val req = DownloadManager.Request(Uri.parse(url))
                .setTitle(name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            CookieManager.getInstance().getCookie(url)?.let { req.addRequestHeader("Cookie", it) }
            call.argument<String>("agent")?.let { req.addRequestHeader("User-Agent", it) }
            val dm = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            result.success(dm.enqueue(req))
        } catch (e: Exception) {
            result.error("download", e.message ?: e.toString(), null)
        }
    }
}
