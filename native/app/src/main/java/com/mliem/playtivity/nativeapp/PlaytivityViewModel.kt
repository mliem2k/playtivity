package com.mliem.playtivity.nativeapp

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.mliem.playtivity.core.Activity
import com.mliem.playtivity.core.SpotifyAuthException
import com.mliem.playtivity.core.TopContent
import com.mliem.playtivity.core.Track
import com.mliem.playtivity.core.User
import com.mliem.playtivity.core.UpdateInfo
import com.mliem.playtivity.core.mergeActivities
import com.mliem.playtivity.core.parseFriends
import com.mliem.playtivity.core.userIdFromJwt
import com.mliem.playtivity.core.widgetSignature
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class Page { Activities, Profile, Settings }

data class PlaytivityState(
    val ready: Boolean = false,
    val cookie: String? = null,
    val signingIn: Boolean = false,
    val loginError: String? = null,
    val page: Page = Page.Activities,
    val activities: List<Activity> = emptyList(),
    val top: TopContent? = null,
    val nowPlaying: Track? = null,
    val artistListeners: Map<String, Int> = emptyMap(),
    val user: User? = null,
    val loadingFeed: Boolean = false,
    val loadingProfile: Boolean = false,
    val feedError: String? = null,
    val profileError: String? = null,
    val updateInfo: UpdateInfo? = null,
    val updateMessage: String? = null,
    val checkingUpdate: Boolean = false,
    val installingUpdate: Boolean = false,
    val nightlyUpdates: Boolean = false,
    val hapticsEnabled: Boolean = true,
    val version: String = "",
)

class PlaytivityViewModel(private val app: PlaytivityApp) : ViewModel() {
    private val _state = MutableStateFlow(PlaytivityState())
    val state: StateFlow<PlaytivityState> = _state.asStateFlow()
    private var token: String? = null
    private var pollJob: Job? = null
    private var nowPlayingJob: Job? = null
    private var lastWidgetSignature: String? = null
    private var lastTopFetchAt: Long = 0

    init {
        viewModelScope.launch {
            _state.update { it.copy(nightlyUpdates = app.updates.nightly, hapticsEnabled = app.hapticsEnabled, version = app.updates.currentVersion().version) }
            app.secrets.initialize(viewModelScope)
            val cookie = app.sessions.readOrImportCookie()
            val cached = if (cookie != null) mergeActivities(app.activityCache.load(), emptyList()) else emptyList()
            _state.update { it.copy(ready = true, cookie = cookie, activities = cached) }
            if (cookie != null) {
                try {
                    refreshToken(cookie)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    // The feed retries when the connection returns.
                }
                loadUser()
                startPolling()
            }
            checkUpdate(force = app.updates.nightly)
        }
    }

    fun signIn(cookie: String) {
        if (_state.value.signingIn) return
        viewModelScope.launch {
            _state.update { it.copy(signingIn = true, loginError = null) }
            try {
                val fresh = app.spotify.fetchBearerToken(cookie)
                if (fresh == null) {
                    _state.update { it.copy(loginError = "Spotify rejected the session. Try again.") }
                    return@launch
                }
                app.sessions.saveCookie(cookie)
                token = fresh
                _state.update { it.copy(cookie = cookie, page = Page.Activities) }
                loadUser()
                startPolling()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                _state.update { it.copy(loginError = "Could not sign in. Check the connection and try again.") }
            } finally {
                _state.update { it.copy(signingIn = false) }
            }
        }
    }

    fun signOut() {
        viewModelScope.coroutineContext.cancelChildren()
        synchronized(app.sessions) {
            FriendActivityWidget.cancelRefreshes()
            app.sessions.clear()
            app.activityCache.clear()
            lastWidgetSignature = null
            FriendActivityWidget.render(app)
        }
        pollJob?.cancel()
        pollJob = null
        nowPlayingJob?.cancel()
        nowPlayingJob = null
        token = null
        lastTopFetchAt = 0
        _state.value = PlaytivityState(ready = true, nightlyUpdates = app.updates.nightly, hapticsEnabled = app.hapticsEnabled, version = app.updates.currentVersion().version)
    }

    fun open(page: Page) {
        _state.update { it.copy(page = page) }
        if (page == Page.Profile) {
            if (_state.value.top == null || System.currentTimeMillis() - lastTopFetchAt >= TOP_STALE_MS) refreshProfile()
            startNowPlayingPolling()
        } else {
            nowPlayingJob?.cancel()
            nowPlayingJob = null
        }
    }

    fun refreshFeed() = viewModelScope.launch { loadFeed() }

    fun refreshProfile() = viewModelScope.launch { loadProfile() }

    fun setNightlyUpdates(enabled: Boolean) {
        app.updates.nightly = enabled
        _state.update { it.copy(nightlyUpdates = enabled) }
    }

    fun setHapticsEnabled(enabled: Boolean) {
        app.hapticsEnabled = enabled
        _state.update { it.copy(hapticsEnabled = enabled) }
    }

    fun checkUpdateNow() = viewModelScope.launch { checkUpdate(force = true) }

    fun dismissUpdate() {
        _state.update { it.copy(updateInfo = null, updateMessage = null) }
    }

    fun installUpdate() {
        val info = _state.value.updateInfo ?: return
        if (_state.value.installingUpdate) return
        viewModelScope.launch {
            _state.update { it.copy(installingUpdate = true, updateMessage = null) }
            try {
                app.updates.downloadAndInstall(info)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(updateMessage = error.message ?: "Could not install update") }
            } finally {
                _state.update { it.copy(installingUpdate = false) }
            }
        }
    }

    private suspend fun checkUpdate(force: Boolean) {
        if (_state.value.checkingUpdate) return
        _state.update { it.copy(checkingUpdate = true, updateMessage = null) }
        try {
            val result = app.updates.check(force)
            _state.update { it.copy(updateInfo = result.info, updateMessage = if (force && result.info == null) result.error ?: "Up to date" else null) }
        } finally {
            _state.update { it.copy(checkingUpdate = false) }
        }
    }

    fun resume() {
        if (_state.value.cookie != null) {
            startPolling()
            if (_state.value.page == Page.Profile) startNowPlayingPolling()
        }
    }

    fun pause() {
        pollJob?.cancel()
        pollJob = null
        nowPlayingJob?.cancel()
        nowPlayingJob = null
    }

    private fun startPolling() {
        if (pollJob?.isActive == true) return
        pollJob = viewModelScope.launch {
            while (isActive && _state.value.cookie != null) {
                loadFeed()
                delay(30_000)
            }
        }
    }

    private fun startNowPlayingPolling() {
        if (nowPlayingJob?.isActive == true || _state.value.cookie == null) return
        nowPlayingJob = viewModelScope.launch {
            while (isActive && _state.value.cookie != null && _state.value.page == Page.Profile) {
                try {
                    val playing = withToken(app.spotify::fetchCurrentlyPlaying)
                    _state.update { it.copy(nowPlaying = playing) }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    // Keep the last known track while the connection is unavailable.
                }
                delay(30_000)
            }
        }
    }

    private suspend fun refreshToken(cookie: String): String? {
        val first = app.spotify.fetchBearerToken(cookie)
        if (first == null) app.secrets.refresh()
        val fresh = first ?: app.spotify.fetchBearerToken(cookie)
        token = fresh
        if (fresh == null) signOut()
        return fresh
    }

    private suspend fun <T> withToken(action: suspend (String) -> T): T {
        val current = token ?: _state.value.cookie?.let { refreshToken(it) }
            ?: throw SpotifyAuthException("Authentication required")
        return try {
            action(current)
        } catch (error: SpotifyAuthException) {
            val cookie = _state.value.cookie ?: throw error
            val fresh = refreshToken(cookie) ?: throw error
            action(fresh)
        }
    }

    private suspend fun loadUser() {
        val cookie = _state.value.cookie ?: return
        val current = token ?: return
        val account = app.spotify.fetchAccountProfile(cookie)
        val id = account?.username?.takeIf { it.isNotEmpty() } ?: userIdFromJwt(current) ?: return
        val user = try {
            app.spotify.fetchProfile(current, id)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        } ?: User(id, id)
        _state.update { it.copy(user = user.copy(email = account?.email, country = account?.country)) }
    }

    private suspend fun loadFeed() {
        if (_state.value.loadingFeed || _state.value.cookie == null) return
        _state.update { it.copy(loadingFeed = true, feedError = null) }
        try {
            val body = withToken(app.spotify::fetchBuddyList)
            val activities = mergeActivities(_state.value.activities, parseFriends(body))
            if (activities.isNotEmpty()) {
                app.activityCache.save(activities)
                val signature = widgetSignature(activities)
                if (signature != lastWidgetSignature) {
                    FriendActivityWidget.render(app)
                    lastWidgetSignature = signature
                }
            }
            _state.update { it.copy(activities = activities) }
            if (_state.value.user == null) {
                try {
                    loadUser()
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    // Feed data remains available when profile lookup fails.
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(feedError = error.message ?: "Could not load friend activity") }
        } finally {
            _state.update { it.copy(loadingFeed = false) }
        }
    }

    private suspend fun loadProfile() {
        if (_state.value.loadingProfile || _state.value.cookie == null) return
        _state.update { it.copy(loadingProfile = true, profileError = null) }
        try {
            val top = withToken { app.spotify.fetchTop(it) }
            lastTopFetchAt = System.currentTimeMillis()
            _state.update { it.copy(top = top) }
            val listeners = mutableMapOf<String, Int>()
            for (artists in top.artists.chunked(4)) {
                val batch = coroutineScope {
                    artists.map { artist ->
                        async {
                            val id = artist.uri.substringAfterLast(':')
                            id to withToken { app.spotify.fetchArtistListeners(it, id) }
                        }
                    }.awaitAll()
                }
                listeners.putAll(batch)
            }
            _state.update { it.copy(artistListeners = listeners) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(profileError = error.message ?: "Could not load profile") }
        } finally {
            _state.update { it.copy(loadingProfile = false) }
        }
    }

    companion object {
        private const val TOP_STALE_MS = 5 * 60_000L
        val Factory = viewModelFactory {
            initializer { PlaytivityViewModel(this[APPLICATION_KEY] as PlaytivityApp) }
        }
    }
}
