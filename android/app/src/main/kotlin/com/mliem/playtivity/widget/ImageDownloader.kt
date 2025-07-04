package com.mliem.playtivity.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.security.MessageDigest

object ImageDownloader {
    
    private fun getImageCacheDir(context: Context): File {
        val cacheDir = File(context.cacheDir, "friend_images")
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }
        return cacheDir
    }
    
    private fun getImageFileName(imageUrl: String): String {
        // Create a hash of the URL to use as filename
        val digest = MessageDigest.getInstance("MD5")
        val hash = digest.digest(imageUrl.toByteArray())
        return hash.joinToString("") { "%02x".format(it) } + ".png"
    }
    
    private fun makeCircularBitmap(bitmap: Bitmap): Bitmap {
        val size = minOf(bitmap.width, bitmap.height)
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        
        val paint = Paint().apply {
            isAntiAlias = true
        }
        
        val rect = Rect(0, 0, size, size)
        val rectF = RectF(rect)
        
        canvas.drawOval(rectF, paint)
        
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        
        // Center crop the original bitmap
        val x = (bitmap.width - size) / 2
        val y = (bitmap.height - size) / 2
        val srcRect = Rect(x, y, x + size, y + size)
        canvas.drawBitmap(bitmap, srcRect, rect, paint)
        
        return output
    }
    
    suspend fun downloadAndCacheImage(context: Context, imageUrl: String, friendIndex: Int): String? {
        if (imageUrl.isEmpty()) return null
        
        return withContext(Dispatchers.IO) {
            try {
                val cacheDir = getImageCacheDir(context)
                val fileName = "friend_${friendIndex}_${getImageFileName(imageUrl)}"
                val file = File(cacheDir, fileName)
                
                // If already cached, return the path
                if (file.exists()) {
                    return@withContext file.absolutePath
                }
                
                // Download the image
                val url = URL(imageUrl)
                val connection = url.openConnection()
                connection.connectTimeout = 5000
                connection.readTimeout = 10000
                
                val inputStream = connection.getInputStream()
                val originalBitmap = BitmapFactory.decodeStream(inputStream)
                inputStream.close()
                
                if (originalBitmap != null) {
                    // Make it circular and resize to 64x64
                    val circularBitmap = makeCircularBitmap(originalBitmap)
                    val resizedBitmap = Bitmap.createScaledBitmap(circularBitmap, 64, 64, true)
                    
                    // Save to cache
                    val outputStream = FileOutputStream(file)
                    resizedBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                    outputStream.close()
                    
                    // Clean up
                    originalBitmap.recycle()
                    circularBitmap.recycle()
                    resizedBitmap.recycle()
                    
                    return@withContext file.absolutePath
                }
                
                null
            } catch (e: Exception) {
                android.util.Log.e("ImageDownloader", "Failed to download/cache image", e)
                null
            }
        }
    }
    
    fun getCachedImagePath(context: Context, friendIndex: Int, imageUrl: String): String? {
        if (imageUrl.isEmpty()) return null
        
        val cacheDir = getImageCacheDir(context)
        val fileName = "friend_${friendIndex}_${getImageFileName(imageUrl)}"
        val file = File(cacheDir, fileName)
        
        return if (file.exists()) file.absolutePath else null
    }
    
    fun clearImageCache(context: Context) {
        try {
            val cacheDir = getImageCacheDir(context)
            cacheDir.listFiles()?.forEach { it.delete() }
        } catch (e: Exception) {
            android.util.Log.e("ImageDownloader", "Failed to clear image cache", e)
        }
    }
} 