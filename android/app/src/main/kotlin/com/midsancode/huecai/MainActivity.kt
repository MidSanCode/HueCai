package com.midsancode.huecai

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "hue_cai/launch"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchFile" -> result.success(extractLaunchPath(intent))
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep the latest intent so a hot restart or re-launch picks it up.
        setIntent(intent)
    }

    /// Pulls a `.hcproj` / `.hcp` path out of a VIEW intent.
    private fun extractLaunchPath(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return when (uri.scheme) {
            "file" -> uri.path?.takeIf { isProjectFile(it) }
            "content" -> copyContentToCache(uri)
            else -> null
        }
    }

    private fun isProjectFile(path: String): Boolean {
        val lower = path.lowercase()
        return lower.endsWith(".hcproj") || lower.endsWith(".hcp")
    }

    /// Content URIs (SAF) cannot be read as plain files, so copy them into the
    /// cache dir and hand Dart a real path.
    private fun copyContentToCache(uri: Uri): String? {
        return try {
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "incoming.hcproj"
            val target = File(cacheDir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
