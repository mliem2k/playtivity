package com.mliem.playtivity.nativeapp

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class ArtworkDiskStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private fun store(maxBytes: Long = 1024, maxFiles: Int = 8) = ArtworkDiskStore(folder.root, maxBytes, maxFiles)

    @Test fun keysMapToJpegFilesUnderTheRoot() {
        val store = store()
        assertEquals(File(folder.root, "abc.jpg"), store.file("abc"))
        store.write("abc", byteArrayOf(1, 2, 3))
        assertEquals(listOf("abc.jpg"), folder.root.list()!!.toList())
    }

    @Test fun writeThenReadReturnsTheBytes() {
        val bytes = byteArrayOf(1, 2, 3, 4)
        store().write("key", bytes)
        assertArrayEquals(bytes, store().read("key"))
    }

    @Test fun missingFileIsAMiss() {
        assertNull(store().read("missing"))
    }

    @Test fun temporaryFileIsNotServedAndIsGoneAfterWrite() {
        val store = store()
        File(folder.root, "key.tmp").writeBytes(byteArrayOf(9, 9))
        assertNull(store.read("key"))

        store.write("key", byteArrayOf(1, 2))
        assertArrayEquals(byteArrayOf(1, 2), store.read("key"))
        assertFalse(File(folder.root, "key.tmp").exists())
    }

    @Test fun writeReplacesExistingContent() {
        val store = store()
        store.write("key", byteArrayOf(1))
        store.write("key", byteArrayOf(2, 3))
        assertArrayEquals(byteArrayOf(2, 3), store.read("key"))
        assertEquals(1, folder.root.listFiles()!!.count { it.name.endsWith(".jpg") })
    }

    @Test fun writeEvictsTheOldestFilesByLastModified() {
        val store = store(maxFiles = 3)
        store.write("oldest", byteArrayOf(1))
        store.write("middle", byteArrayOf(2))
        store.write("newest", byteArrayOf(3))
        assertTrue(store.file("oldest").setLastModified(1_000))
        assertTrue(store.file("middle").setLastModified(2_000))
        assertTrue(store.file("newest").setLastModified(3_000))

        store.write("added", byteArrayOf(4))

        assertFalse(store.file("oldest").exists())
        assertTrue(store.file("middle").exists())
        assertTrue(store.file("newest").exists())
        assertTrue(store.file("added").exists())
    }

    @Test fun writeEvictsTheOldestFilesOverTheByteLimit() {
        val store = store(maxBytes = 12, maxFiles = 100)
        store.write("a", ByteArray(4))
        store.write("b", ByteArray(4))
        store.write("c", ByteArray(4))
        assertTrue(store.file("a").exists())
        assertTrue(store.file("a").setLastModified(1_000))
        assertTrue(store.file("b").setLastModified(2_000))
        assertTrue(store.file("c").setLastModified(3_000))

        store.write("d", ByteArray(4))

        assertFalse(store.file("a").exists())
        assertTrue(store.file("b").exists())
        assertTrue(store.file("c").exists())
        assertTrue(store.file("d").exists())
    }

    @Test fun emptyFileIsDeletedAndTreatedAsAMiss() {
        val store = store()
        val target = store.file("key")
        target.writeBytes(ByteArray(0))
        assertNull(store.read("key"))
        assertFalse(target.exists())
    }

    @Test fun directoryAtTheKeyPathIsDeletedAndTreatedAsAMiss() {
        val store = store()
        val target = store.file("key")
        assertTrue(target.mkdirs())
        assertNull(store.read("key"))
        assertFalse(target.exists())
    }
}
