package com.mliem.playtivity.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateModelsTest {
    private val nightly = JSONObject("""{
      "tag_name":"nightly-20260611-050901",
      "published_at":"2026-06-11T05:09:01Z",
      "body":"**Version**: `0.0.2-nightly-20260611-050901+1781212141`",
      "assets":[{"name":"p.apk","browser_download_url":"https://x/p.apk","size":5}]
    }""")

    @Test fun parsesNightlyAndComparesItsBuild() {
        val info = infoFromRelease(nightly, true)
        assertEquals("0.0.2-nightly-20260611-050901", info.version)
        assertEquals("1781212141", info.buildNumber)
        assertEquals("p.apk", info.apkFileName)
        assertTrue(shouldUpdateToNightly(AppVersion("0.0.2-nightly-x", "1781212140"), info))
        assertFalse(shouldUpdateToNightly(AppVersion("0.0.2-nightly-x", "1781212141"), info))
        assertTrue(shouldUpdateToNightly(AppVersion("0.0.2", "1"), info))
        assertFalse(shouldUpdateToNightly(AppVersion("0.0.3", "1"), info))
    }

    @Test fun comparesStableReleasesAndSelectsLatestPublished() {
        assertTrue(isNewerVersion("0.0.2", "0.0.3"))
        assertFalse(isNewerVersion("0.0.3", "0.0.2"))
        assertTrue(isNewerVersion("0.0.2-nightly-20260611-050901", "0.0.3"))
        assertFalse(isNewerVersion("0.0.2", "0.0.3-nightly-20260611-050901"))
        val releases = JSONArray().put(JSONObject("""{"tag_name":"v0.0.3","published_at":"2026-06-12T00:00:00Z"}"""))
            .put(JSONObject("""{"tag_name":"v0.0.4","published_at":"2026-06-14T00:00:00Z"}"""))
            .put(nightly)
        assertEquals("0.0.4", checkRelease(releases, AppVersion("0.0.2", "1")).info?.version)
    }
}
