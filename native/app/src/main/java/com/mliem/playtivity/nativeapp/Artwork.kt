package com.mliem.playtivity.nativeapp

import android.graphics.Bitmap
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun Artwork(url: String?, modifier: Modifier = Modifier, size: Dp = 48.dp, shape: Shape = RoundedCornerShape(4.dp)) {
    val cache = (LocalContext.current.applicationContext as PlaytivityApp).artworkCache
    val bitmap by produceState<Bitmap?>(initialValue = cache.peek(url), key1 = url, key2 = cache) {
        if (url.isNullOrBlank()) return@produceState
        cache.peek(url)?.let { value = it; return@produceState }
        value = cache.load(url)
    }
    val image = bitmap
    if (image == null) Box(modifier.size(size).clip(shape).background(PlaytivityColors.surfaceElevated))
    else Image(image.asImageBitmap(), contentDescription = null, modifier = modifier.size(size).clip(shape), contentScale = ContentScale.Crop)
}
