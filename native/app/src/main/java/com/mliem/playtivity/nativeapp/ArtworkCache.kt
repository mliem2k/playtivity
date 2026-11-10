package com.mliem.playtivity.nativeapp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.roundToInt

/** Longest side, in pixels, of a decoded artwork bitmap. */
private const val TARGET_PX = 192
private const val JPEG_QUALITY = 85
private const val MIN_MEMORY_BYTES = 8L * 1024 * 1024
private const val MAX_MEMORY_BYTES = 64L * 1024 * 1024

/**
 * Memory budget for the artwork cache: one eighth of the heap, clamped to 8..64 MB.
 * Pure so it can be tested on the JVM without Android.
 */
internal fun memoryCacheBytes(maxHeapBytes: Long): Int =
    (maxHeapBytes / 8).coerceIn(MIN_MEMORY_BYTES, MAX_MEMORY_BYTES).toInt()

/**
 * Bounded on-disk JPEG store. Pure file IO so it can be tested on the JVM.
 * Files are written to a temporary sibling and renamed into place, and the
 * oldest files by [File.lastModified] are evicted after every write.
 */
internal class ArtworkDiskStore(
    private val root: File,
    private val maxBytes: Long = 64L * 1024 * 1024,
    private val maxFiles: Int = 512,
) {
    fun file(key: String): File = File(root, "$key.jpg")

    fun read(key: String): ByteArray? {
        val target = file(key)
        return try {
            when {
                !target.exists() -> null
                !target.isFile -> { target.delete(); null }
                else -> target.readBytes().takeIf { it.isNotEmpty() } ?: run { target.delete(); null }
            }
        } catch (_: IOException) {
            target.delete()
            null
        }
    }

    fun write(key: String, bytes: ByteArray) {
        val target = file(key)
        val temp = File(root, "$key.tmp")
        try {
            root.mkdirs()
            temp.writeBytes(bytes)
            if (!temp.renameTo(target)) {
                target.delete()
                if (!temp.renameTo(target)) { temp.delete(); return }
            }
            trim()
        } catch (_: IOException) {
            temp.delete()
        }
    }

    fun delete(key: String) {
        file(key).delete()
    }

    private fun trim() {
        val files = root.listFiles()?.filter { it.isFile && !it.name.endsWith(".tmp") } ?: return
        var count = files.size
        var bytes = files.sumOf(File::length)
        if (count <= maxFiles && bytes <= maxBytes) return
        for (oldest in files.sortedBy(File::lastModified)) {
            if (count <= maxFiles && bytes <= maxBytes) break
            val length = oldest.length()
            if (oldest.delete()) {
                count--
                bytes -= length
            }
        }
    }
}

/**
 * Two-level artwork cache: an in-memory LRU backed by a disk store, with one
 * in-flight load per URL shared across concurrent callers.
 */
class ArtworkCache(context: Context) {
    private val client = OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build()
    private val memory = object : LruCache<String, Bitmap>(memoryCacheBytes(Runtime.getRuntime().maxMemory())) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }
    private val disk = ArtworkDiskStore(File(context.applicationContext.cacheDir, "artwork"))
    private val flights = SingleFlight<String, Bitmap?>()

    /** Memory-only lookup for the first frame; never touches the disk or the network. */
    fun peek(url: String?): Bitmap? = url?.takeIf { it.isNotBlank() }?.let(memory::get)

    suspend fun load(url: String?): Bitmap? {
        if (url.isNullOrBlank()) return null
        memory.get(url)?.let { return it }
        val httpUrl = url.toHttpUrlOrNull() ?: return null
        if (httpUrl.scheme != "https") return null
        val key = artworkKey(url)
        return try {
            flights.run(key) { loadFrom(httpUrl, url, key) }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun loadFrom(url: HttpUrl, memoryKey: String, diskKey: String): Bitmap? = withContext(Dispatchers.IO) {
        disk.read(diskKey)?.let { bytes ->
            decode(bytes)?.let { bitmap ->
                memory.put(memoryKey, bitmap)
                return@withContext bitmap
            }
            disk.delete(diskKey)
        }
        currentCoroutineContext().ensureActive()
        val bytes = fetch(url) ?: return@withContext null
        currentCoroutineContext().ensureActive()
        val bitmap = decode(bytes) ?: return@withContext null
        memory.put(memoryKey, bitmap)
        // A disk failure must not throw away a decoded bitmap that is already in memory.
        runCatching { encodeJpeg(bitmap)?.let { disk.write(diskKey, it) } }
        bitmap
    }

    private suspend fun fetch(url: HttpUrl): ByteArray? = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(Request.Builder().url(url).build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resume(null)
            }

            override fun onResponse(call: Call, response: Response) {
                val bytes = try {
                    response.use { if (it.isSuccessful) it.body.bytes() else null }
                } catch (error: Exception) {
                    continuation.resumeWithException(error)
                    return
                }
                continuation.resume(bytes)
            }
        })
    }

    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= TARGET_PX) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val longest = maxOf(decoded.width, decoded.height)
        if (longest <= TARGET_PX) return decoded
        val ratio = TARGET_PX.toFloat() / longest
        val scaled = Bitmap.createScaledBitmap(
            decoded,
            (decoded.width * ratio).roundToInt().coerceAtLeast(1),
            (decoded.height * ratio).roundToInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== decoded) decoded.recycle()
        return scaled
    }

    private fun encodeJpeg(bitmap: Bitmap): ByteArray? {
        val output = ByteArrayOutputStream()
        return if (bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)) output.toByteArray() else null
    }

    private fun artworkKey(url: String): String =
        MessageDigest.getInstance("SHA-256").digest("$url@$TARGET_PX".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}
