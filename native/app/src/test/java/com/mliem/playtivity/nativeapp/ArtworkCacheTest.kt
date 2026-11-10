package com.mliem.playtivity.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class ArtworkCacheTest {
    private val mb = 1024 * 1024

    @Test fun memoryBudgetIsOneEighthOfTheHeapClampedToTheBounds() {
        assertEquals(8 * mb, memoryCacheBytes(0L))
        assertEquals(8 * mb, memoryCacheBytes(32L * mb))
        assertEquals(8 * mb, memoryCacheBytes(64L * mb))
        assertEquals(32 * mb, memoryCacheBytes(256L * mb))
        assertEquals(64 * mb, memoryCacheBytes(1024L * mb))
        assertEquals(64 * mb, memoryCacheBytes(Long.MAX_VALUE))
    }
}
