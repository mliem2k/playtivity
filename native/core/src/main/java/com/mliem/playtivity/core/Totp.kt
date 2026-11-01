package com.mliem.playtivity.core

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class TotpSecrets(initial: Map<Int, List<Int>> = FALLBACK_SECRETS) {
    private var secrets: Map<Int, List<Int>> = initial

    val activeVersion: Int get() = secrets.keys.maxOrNull() ?: error("TOTP secret table is empty")

    fun apply(table: Map<Int, List<Int>>) {
        require(table.isNotEmpty() && table.values.all { values -> values.isNotEmpty() && values.all { it in 0..255 } })
        secrets = table
    }

    fun generateCode(timestampMs: Long): String {
        val cipher = secrets.getValue(activeVersion)
        val joined = cipher.mapIndexed { index, byte -> byte xor ((index % 33) + 9) }.joinToString("")
        val ascii = joined.toByteArray(Charsets.UTF_8)
        val key = ascii.copyOf(((ascii.size + 4) / 5) * 5)
        val step = Math.floorDiv(timestampMs, 30_000L)
        val message = ByteBuffer.allocate(Long.SIZE_BYTES).putLong(step).array()
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(key, "HmacSHA1"))
        val digest = mac.doFinal(message)
        val offset = digest.last().toInt() and 0x0f
        val number = ((digest[offset].toInt() and 0x7f) shl 24) or
            ((digest[offset + 1].toInt() and 0xff) shl 16) or
            ((digest[offset + 2].toInt() and 0xff) shl 8) or
            (digest[offset + 3].toInt() and 0xff)
        return (number % 1_000_000).toString().padStart(6, '0')
    }

    companion object {
        val FALLBACK_SECRETS: Map<Int, List<Int>> = mapOf(
            59 to listOf(123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72),
            60 to listOf(79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87),
            61 to listOf(44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78),
        )
    }
}
