package com.danylooliinyk.pixelcode

import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CLIPBOARD_CHANNEL = "com.pixelcode/clipboard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getImageFromClipboard" -> {
                    // Run on background thread to avoid blocking UI
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val imageBytes = getImageFromClipboard()
                            result.success(imageBytes)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error getting image from clipboard", e)
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getImageFromClipboard(): ByteArray? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = clipboard.primaryClip ?: return null

        if (!clipData.description.hasMimeType("image/*")) {
            return null
        }

        val item = clipData.getItemAt(0) ?: return null
        val uri = item.uri ?: return null

        return try {
            val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val source = ImageDecoder.createSource(contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.isMutableRequired = true
                }
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(contentResolver, uri)
            }

            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val imageBytes = outputStream.toByteArray()

            // Free bitmap memory
            bitmap.recycle()

            imageBytes
        } catch (e: Exception) {
            Log.e("MainActivity", "Error compressing image from clipboard", e)
            null
        }
    }
}
