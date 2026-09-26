package com.example.secret_gallery

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService

class VaultCryptoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var executor: ExecutorService
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newFixedThreadPool(2)
        channel = MethodChannel(binding.binaryMessenger, "secret_gallery/crypto")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun privateOutput(path: String): File {
        val file = File(path).canonicalFile
        val root = File(context.applicationInfo.dataDir).canonicalPath + File.separator
        require(file.path.startsWith(root)) { "Output must be inside app storage" }
        return file
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("encryptFile", "prepareExport", "hashFile", "decryptBytes")) {
            result.notImplemented()
            return
        }
        executor.execute {
            var key: ByteArray? = null
            try {
                val source = File(requireNotNull(call.argument<String>("source")))
                val value: Any = when (call.method) {
                    "decryptBytes" -> {
                        key = requireNotNull(call.argument<ByteArray>("key"))
                        VaultCrypto.decryptBytes(source, key)
                    }
                    "hashFile" -> VaultCrypto.hash(source)
                    "encryptFile" -> {
                        key = requireNotNull(call.argument<ByteArray>("key"))
                        val iv = requireNotNull(call.argument<ByteArray>("iv"))
                        val target = privateOutput(requireNotNull(call.argument<String>("destination")))
                        VaultCrypto.encrypt(source, target, key, iv)
                        target.path
                    }
                    else -> {
                        key = requireNotNull(call.argument<ByteArray>("key"))
                        val target = call.argument<String>("destination")?.let { privateOutput(it) }
                        val output = VaultCrypto.decrypt(source, target, key)
                        check(output.length > 0) { "Empty private file" }
                        output.digest
                    }
                }
                main.post { result.success(value) }
            } catch (e: OutOfMemoryError) {
                main.post { result.error("vault_memory", "No hay memoria suficiente para esta vista previa.", null) }
            } catch (e: Exception) {
                // Do not log key material or private paths.
                main.post { result.error("vault_crypto", "No se pudo procesar el archivo de forma segura.", null) }
            } finally {
                key?.fill(0)
            }
        }
    }
}