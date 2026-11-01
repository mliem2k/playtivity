package com.mliem.playtivity.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SpotifyCookieTest {
    @Test fun readsExactSessionCookieAmongOtherCookies() {
        assertEquals("valid=value", spotifySessionCookie("sp_dc_backup=old; foo=bar; sp_dc=valid=value; other=1"))
    }

    @Test fun refusesMissingOrEmptySessionCookie() {
        assertNull(spotifySessionCookie("sp_dc_backup=old; foo=bar"))
        assertNull(spotifySessionCookie("sp_dc=; foo=bar"))
        assertNull(spotifySessionCookie(null))
    }
}
