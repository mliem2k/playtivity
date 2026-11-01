package com.mliem.playtivity.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class SpotifyHttpClientTest {
    private lateinit var server: MockWebServer
    private lateinit var spotify: SpotifyHttpClient

    @Before fun setUp() {
        server = MockWebServer()
        server.start()
        val base = server.url("/").toString().removeSuffix("/")
        spotify = SpotifyHttpClient(endpoints = SpotifyEndpoints(base, base, base, base, base))
    }

    @After fun tearDown() {
        server.shutdown()
    }

    @Test fun bearerTokenUsesCookieAndRejectsAnonymousToken() = runTest {
        server.enqueue(MockResponse().setResponseCode(200))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"accessToken":"token","isAnonymous":false}"""))
        assertEquals("token", spotify.fetchBearerToken("cookie"))
        server.takeRequest()
        val request = server.takeRequest()
        assertEquals("sp_dc=cookie", request.getHeader("Cookie"))
        assertTrue(request.path.orEmpty().contains("totpVer=61"))
        assertTrue(request.path.orEmpty().contains("totpServer="))

        server.enqueue(MockResponse().setResponseCode(200))
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"accessToken":"guest","isAnonymous":true}"""))
        assertNull(spotify.fetchBearerToken("cookie"))
    }

    @Test fun cancellationStopsInitialClockRequest() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setHeadersDelay(3, TimeUnit.SECONDS))
        val request = launch(Dispatchers.IO) { spotify.fetchBearerToken("cookie") }
        assertNotNull(server.takeRequest(2, TimeUnit.SECONDS))
        withTimeout(1000) { request.cancelAndJoin() }
        assertEquals(1, server.requestCount)
    }

    @Test fun cancellationStopsInFlightCookieRequest() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200))
        server.enqueue(MockResponse().setResponseCode(200).setBodyDelay(3, TimeUnit.SECONDS).setBody("""{"accessToken":"token"}"""))
        val request = launch(Dispatchers.IO) { spotify.fetchBearerToken("cookie") }
        assertNotNull(server.takeRequest(2, TimeUnit.SECONDS))
        assertEquals("sp_dc=cookie", server.takeRequest(2, TimeUnit.SECONDS)?.getHeader("Cookie"))
        withTimeout(1000) { request.cancelAndJoin() }
    }

    @Test fun authorizationRefusalDoesNotRetry() = runTest {
        server.enqueue(MockResponse().setResponseCode(403))
        val error = runCatching { spotify.fetchBuddyList("token") }.exceptionOrNull()
        assertTrue(error is SpotifyAuthException)
        assertEquals(1, server.requestCount)
        assertEquals("Bearer token", server.takeRequest().getHeader("Authorization"))
    }

    @Test fun topRequestIncludesBothContentTypes() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"data":{"me":{"profile":{"topTracks":{"items":[]},"topArtists":{"items":[]}}}}}"""))
        val top = spotify.fetchTop("token")
        assertTrue(top.tracks.isEmpty())
        assertTrue(top.artists.isEmpty())
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        val body = request.body.readUtf8()
        assertTrue(body.contains("includeTopTracks"))
        assertTrue(body.contains("includeTopArtists"))
        assertFalse(body.contains("sp_dc"))
    }
}
