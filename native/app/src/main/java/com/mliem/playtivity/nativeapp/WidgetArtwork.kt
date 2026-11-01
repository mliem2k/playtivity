package com.mliem.playtivity.nativeapp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.core.graphics.scale
import kotlinx.coroutines.CancellationException
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal object WidgetArtwork {
    private val client = OkHttpClient.Builder().callTimeout(2, TimeUnit.SECONDS).build()
    private val memory = object : LruCache<String, Bitmap>(2 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun cached(context: Context, url: String?): Bitmap? {
        if (url.isNullOrBlank()) return null
        memory.get(url)?.let { return it }
        val file = cacheFile(context, url)
        return BitmapFactory.decodeFile(file.absolutePath)?.also { memory.put(url, it) }
    }

    fun load(context: Context, url: String?): Bitmap? {
        if (url.isNullOrBlank() || !url.startsWith("https://")) return null
        cached(context, url)?.let { return it }
        return try {
            val request = Request.Builder().url(url).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                val bytes = response.body.bytes()
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
                val sample = (maxOf(bounds.outWidth, bounds.outHeight) / 48).coerceAtLeast(1)
                val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
                val image = decoded.scale(48, 48)
                if (image !== decoded) decoded.recycle()
                memory.put(url, image)
                val file = cacheFile(context, url).also { it.parentFile?.mkdirs() }
                file.outputStream().use { output ->
                    image.compress(Bitmap.CompressFormat.PNG, 100, output)
                }
                file.parentFile?.listFiles()?.takeIf { it.size > 256 }
                    ?.sortedByDescending(File::lastModified)?.drop(256)?.forEach(File::delete)
                image
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    private fun cacheFile(context: Context, url: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(File(context.cacheDir, "widget_art"), "$hash.png")
    }
}
