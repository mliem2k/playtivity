package com.mliem.playtivity.core

import org.junit.Assert.assertEquals
import org.junit.Test

class TotpTest {
    @Test fun matchesExistingVectors() {
        val totp = TotpSecrets()
        assertEquals(61, totp.activeVersion)
        assertEquals("204513", totp.generateCode(0))
        assertEquals("371947", totp.generateCode(1_000_000_000_000))
        assertEquals("848996", totp.generateCode(1_750_000_000_000))
        assertEquals("345437", totp.generateCode(1_752_300_000_000))
    }

    @Test fun appliesNewSecretVersion() {
        val totp = TotpSecrets()
        totp.apply(mapOf(70 to listOf(1, 2, 3)))
        assertEquals(70, totp.activeVersion)
    }
}
