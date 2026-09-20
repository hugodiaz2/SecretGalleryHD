package com.example.secret_gallery

import android.view.WindowManager
import android.os.Build
import android.os.Environment
import android.media.MediaScannerConnection
import java.io.File
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (en vez de FlutterActivity) es requerido por
// local_auth para poder mostrar el diálogo de huella dactilar.
class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "secret_gallery/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(VaultCryptoPlugin::class.java)) {
            flutterEngine.plugins.add(VaultCryptoPlugin())
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secret_gallery/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "publishLegacy" -> {
                        if (Build.VERSION.SDK_INT >= 29) {
                            result.error("unsupported", "Use MediaStore on Android 29+", null)
                        } else {
                            val source = call.argument<String>("source")
                            val name = call.argument<String>("name")
                            if (source == null || name == null) {
                                result.error("arguments", "Missing source or name", null)
                            } else {
                                Thread {
                                    var destination: File? = null
                                    try {
                                        val input = File(source).canonicalFile
                                        require(input.path.startsWith(cacheDir.canonicalPath + File.separator))
                                        val dir = File(Environment.getExternalStoragePublicDirectory(
                                            Environment.DIRECTORY_DCIM), "Secret")
                                        check(dir.isDirectory || dir.mkdirs())
                                        // One physical public copy. The scanner is the only registrar.
                                        val safeName = File(name).name
                                        val output = File(dir, safeName)
                                        // A persisted unique name makes a retry after a crash
                                        // reuse its file. Never overwrite another file.
                                        if (output.exists()) {
                                            fun digest(file: File): ByteArray {
                                                val hash = MessageDigest.getInstance("SHA-256")
                                                file.inputStream().use { stream ->
                                                    val buffer = ByteArray(65536)
                                                    var count = stream.read(buffer)
                                                    while (count >= 0) {
                                                        if (count > 0) hash.update(buffer, 0, count)
                                                        count = stream.read(buffer)
                                                    }
                                                }
                                                return hash.digest()
                                            }
                                            check(digest(input).contentEquals(digest(output)))
                                        } else {
                                            destination = output
                                            input.copyTo(output, overwrite = false)
                                        }

                                        val publishedPath = output.absolutePath
                                        MediaScannerConnection.scanFile(this,
                                            arrayOf(publishedPath), null) { _, uri ->
                                            runOnUiThread {
                                                if (uri == null) {
                                                    result.error("scan", "Could not index public file; private copy retained", null)
                                                } else {
                                                    result.success(uri.lastPathSegment)
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        // Only our new partial copy is eligible for cleanup.
                                        destination?.delete()
                                        runOnUiThread { result.error("publish", e.message, null) }
                                    }
                                }.start()
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
