package com.mliem.playtivity.core

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class TotpSecretRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var secrets: TotpSecrets
    private lateinit var cache: FakeCache
    private lateinit var repository: TotpSecretRepository

    @Before fun setUp() {
        server = MockWebServer()
        server.start()
        secrets = TotpSecrets()
        cache = FakeCache()
        repository = TotpSecretRepository(secrets, cache, url = server.url("/").toString())
    }

    @After fun tearDown() {
        server.shutdown()
    }

    @Test fun freshCacheLoadsWithoutNetwork() = runTest {
        cache.value = """{"at":1000,"data":{"70":[1,2,3]}}"""
        repository.initialize(this, now = 1000)
        assertEquals(70, secrets.activeVersion)
        assertEquals(0, server.requestCount)
    }

    @Test fun refreshReplacesValidTableAndRetainsOldTableOnInvalidResponse() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"71":[4,5,6]}"""))
        assertTrue(repository.refresh(now = 2000))
        assertEquals(71, secrets.activeVersion)
        assertTrue(cache.value.orEmpty().contains("\"at\":2000"))

        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"bad":[1],"72":[]}"""))
        assertFalse(repository.refresh())
        assertEquals(71, secrets.activeVersion)
    }

    private class FakeCache : SecretCache {
        var value: String? = null
        override suspend fun read(): String? = value
        override suspend fun write(value: String) { this.value = value }
    }
}
