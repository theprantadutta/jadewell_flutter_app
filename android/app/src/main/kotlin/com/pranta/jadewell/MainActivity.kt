package com.pranta.jadewell

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jadewell/mail").setMethodCallHandler { call, result ->
            if (call.method != "compose") return@setMethodCallHandler result.notImplemented()
            val to = call.argument<String>("to").orEmpty()
            val subject = call.argument<String>("subject").orEmpty()
            val body = call.argument<String>("body").orEmpty()
            result.success(compose(to, subject, body))
        }
    }

    /** Opens a new email in Gmail, or in any mail app when Gmail isn't installed. */
    private fun compose(to: String, subject: String, body: String): Boolean {
        fun intent() = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent().setPackage(GMAIL))
            true
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(intent())
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    private companion object {
        const val GMAIL = "com.google.android.gm"
    }
}
