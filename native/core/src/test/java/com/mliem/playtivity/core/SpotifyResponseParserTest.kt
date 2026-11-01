package com.mliem.playtivity.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SpotifyResponseParserTest {
    @Test fun parsesTopContentWithPreferredImages() {
        val body = """{"data":{"me":{"profile":{
          "topTracks":{"items":[{"data":{"name":"Song","uri":"spotify:track:1","artists":{"items":[{"profile":{"name":"Singer"}}]},"albumOfTrack":{"name":"Album","coverArt":{"sources":[{"height":640,"url":"large"},{"height":300,"url":"preferred"}]}},"duration":{"totalMilliseconds":185000}}}]},
          "topArtists":{"items":[{"data":{"profile":{"name":"Singer"},"uri":"spotify:artist:2","visuals":{"avatarImage":{"sources":[{"height":320,"url":"portrait"}]}}}}]}
        }}}}"""
        val top = parseTopContent(body)
        assertEquals("Song", top.tracks.single().name)
        assertEquals(listOf("Singer"), top.tracks.single().artists)
        assertEquals("preferred", top.tracks.single().imageUrl)
        assertEquals(185_000, top.tracks.single().durationMs)
        assertEquals("portrait", top.artists.single().imageUrl)
    }

    @Test fun parsesPlaybackAccountAndLinks() {
        val playing = parseCurrentlyPlaying("""{"item":{"name":"Song","artists":[{"name":"Singer"}],"album":{"name":"Album","images":[{"url":"cover"}]},"uri":"spotify:track:1","duration_ms":1234}}""")
        assertEquals("Song", playing?.name)
        assertEquals("cover", playing?.imageUrl)
        assertEquals(listOf("Singer"), playing?.artists)
        assertNull(parseCurrentlyPlaying("{}"))
        assertEquals(AccountProfile("u", "e", "US"), parseAccountProfile("""{"profile":{"username":"u","email":"e","country":"US"}}"""))
        assertEquals(42, parseArtistListeners("""{"data":{"artist":{"stats":{"monthlyListeners":42}}}}"""))
        assertEquals("https://open.spotify.com/track/1", spotifyUrl("spotify:track:1"))
        assertEquals("https://open.spotify.com/", spotifyUrl("invalid"))
    }
}
