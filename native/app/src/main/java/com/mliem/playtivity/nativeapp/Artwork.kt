package com.mliem.playtivity.nativeapp

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

private val imageClient = OkHttpClient()
private val imageCache = object : LruCache<String, Bitmap>(20 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
}

@Composable
fun Artwork(url: String?, size: Dp = 48.dp, modifier: Modifier = Modifier) {
    val bitmap by produceState<Bitmap?>(initialValue = url?.let(imageCache::get), key1 = url) {
        if (url.isNullOrBlank()) return@produceState
        imageCache.get(url)?.let { value = it; return@produceState }
        value = try {
            withContext(Dispatchers.IO) {
                val request = Request.Builder().url(url).build()
                imageClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    val bytes = response.body.bytes()
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    val sample = (bounds.outWidth.coerceAtLeast(bounds.outHeight) / 192).coerceAtLeast(1)
                    val options = BitmapFactory.Options().apply { inSampleSize = sample }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.also { imageCache.put(url, it) }
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }
    val shape = RoundedCornerShape(4.dp)
    val image = bitmap
    if (image == null) Box(modifier.size(size).clip(shape).background(PlaytivityColors.surfaceElevated))
    else Image(image.asImageBitmap(), contentDescription = null, modifier = modifier.size(size).clip(shape), contentScale = ContentScale.Crop)
}
