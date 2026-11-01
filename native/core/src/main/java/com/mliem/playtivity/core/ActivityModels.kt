package com.mliem.playtivity.core

data class User(
    val id: String,
    val displayName: String,
    val imageUrl: String? = null,
    val followers: Int = 0,
    val country: String? = null,
    val email: String? = null,
)

data class Track(
    val name: String,
    val artists: List<String>,
    val album: String,
    val imageUrl: String? = null,
    val uri: String,
    val durationMs: Long = 0,
)

data class Playlist(
    val name: String,
    val imageUrl: String? = null,
    val trackCount: Int = 0,
    val uri: String,
    val ownerName: String,
)

data class Activity(
    val user: User,
    val track: Track? = null,
    val playlist: Playlist? = null,
    val timestamp: Long,
    val playing: Boolean,
)

data class Artist(
    val name: String,
    val imageUrl: String? = null,
    val uri: String,
    val monthlyListeners: Int? = null,
)

data class TopContent(val tracks: List<Track>, val artists: List<Artist>)

data class AccountProfile(val username: String, val email: String, val country: String)
