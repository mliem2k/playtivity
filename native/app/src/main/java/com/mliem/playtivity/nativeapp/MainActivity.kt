package com.mliem.playtivity.nativeapp

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.mliem.playtivity.core.Activity
import com.mliem.playtivity.core.Artist
import com.mliem.playtivity.core.Track
import com.mliem.playtivity.core.SpotifyHttpClient
import com.mliem.playtivity.core.timeAgo
import com.mliem.playtivity.core.formatCount
import com.mliem.playtivity.core.formatDuration
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val viewModel: PlaytivityViewModel by viewModels { PlaytivityViewModel.Factory }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.getStringExtra("spotify_url")?.takeIf { it.startsWith("https://open.spotify.com/") }?.let { url ->
            startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
            intent.removeExtra("spotify_url")
        }
        setContent {
            val state by viewModel.state.collectAsStateWithLifecycle()
            PlaytivityTheme {
                when {
                    !state.ready -> LoadingScreen()
                    state.cookie == null -> LoginScreen(state.loginError, state.signingIn, viewModel::signIn)
                    else -> AppScreen(state, viewModel)
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        viewModel.resume()
    }

    override fun onStop() {
        viewModel.pause()
        super.onStop()
    }
}

@Composable
private fun LoadingScreen() {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) { CircularProgressIndicator() }
}

@Composable
private fun LoginScreen(error: String?, signingIn: Boolean, onCookie: (String) -> Unit) {
    var webLogin by remember { mutableStateOf(false) }
    if (!webLogin) {
        Column(
            Modifier.fillMaxSize().padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(painterResource(R.drawable.playtivity_icon), contentDescription = null, modifier = Modifier.width(120.dp).height(120.dp))
            Spacer(Modifier.height(24.dp))
            Text("Playtivity", style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(12.dp))
            Text("See what your friends are listening to")
            Spacer(Modifier.height(32.dp))
            Button(onClick = { webLogin = true }) { Text("Log in with Spotify") }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            if (error != null) {
                Text(error, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error)
                Button(onClick = { webLogin = false }, modifier = Modifier.padding(horizontal = 12.dp)) { Text("Try again") }
            }
            if (signingIn) CircularProgressIndicator(Modifier.padding(12.dp))
            val scope = rememberCoroutineScope()
            var capturing by remember { mutableStateOf(false) }
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        settings.javaScriptEnabled = true
                        settings.userAgentString = SpotifyHttpClient.WEB_USER_AGENT
                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, url: String) {
                                if (!url.startsWith("https://open.spotify.com/") ||
                                    listOf("/login", "/auth", "/challenge", "/error").any(url::contains) || capturing
                                ) return
                                capturing = true
                                scope.launch {
                                    repeat(8) {
                                        val cookie = CookieManager.getInstance().getCookie("https://open.spotify.com")
                                            ?.split(';')?.map(String::trim)
                                            ?.firstOrNull { it.startsWith("sp_dc=") }
                                            ?.removePrefix("sp_dc=")
                                        if (!cookie.isNullOrEmpty()) {
                                            onCookie(cookie)
                                            capturing = false
                                            return@launch
                                        }
                                        delay(1_000)
                                    }
                                    capturing = false
                                }
                            }
                        }
                        loadUrl("https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F")
                    }
                },
            )
        }
    }
}

@Composable
private fun AppScreen(state: PlaytivityState, viewModel: PlaytivityViewModel) {
    Scaffold(
        topBar = {
            state.updateInfo?.let { info ->
                Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Update ${info.version} available", Modifier.weight(1f).padding(8.dp))
                    Button(onClick = viewModel::installUpdate, enabled = !state.installingUpdate) { Text("Install") }
                    Button(onClick = viewModel::dismissUpdate) { Text("Dismiss") }
                }
            }
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(selected = state.page == Page.Activities, onClick = { viewModel.open(Page.Activities) }, icon = {}, label = { Text("Activities") })
                NavigationBarItem(selected = state.page == Page.Profile, onClick = { viewModel.open(Page.Profile) }, icon = {}, label = { Text("Profile") })
                NavigationBarItem(selected = state.page == Page.Settings, onClick = { viewModel.open(Page.Settings) }, icon = {}, label = { Text("Settings") })
            }
        },
    ) { padding ->
        when (state.page) {
            Page.Activities -> ActivitiesPage(state, viewModel::refreshFeed, Modifier.padding(padding))
            Page.Profile -> ProfilePage(state, viewModel::refreshProfile, Modifier.padding(padding))
            Page.Settings -> SettingsPage(state, viewModel, Modifier.padding(padding))
        }
    }
}

@Composable
private fun ActivitiesPage(state: PlaytivityState, refresh: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Friend Activity", style = MaterialTheme.typography.titleLarge)
            Button(onClick = refresh, enabled = !state.loadingFeed) { Text("Refresh") }
        }
        if (state.loadingFeed) CircularProgressIndicator()
        if (state.feedError != null) Text(state.feedError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
        if (state.activities.isEmpty() && !state.loadingFeed) Text("No friend activity", Modifier.padding(16.dp))
        LazyColumn {
            items(state.activities, key = { it.user.id }) { activity ->
                ActivityRow(activity)
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun ActivityRow(activity: Activity) {
    val context = LocalContext.current
    val view = LocalView.current
    val hapticsEnabled = (context.applicationContext as PlaytivityApp).hapticsEnabled
    val content = activity.track?.name ?: activity.playlist?.name.orEmpty()
    val detail = activity.track?.let { track ->
        listOf(track.artists.joinToString(", "), track.album).filter(String::isNotEmpty).joinToString(" · ")
    } ?: activity.playlist?.let { playlist ->
        listOfNotNull(
            playlist.ownerName.takeIf(String::isNotEmpty),
            playlist.trackCount.takeIf { it > 0 }?.let { "$it tracks" },
        ).joinToString(" · ").ifEmpty { "Playlist" }
    }.orEmpty()
    val uri = activity.track?.uri ?: activity.playlist?.uri.orEmpty()
    Row(
        Modifier.fillMaxWidth().clickable(enabled = uri.isNotEmpty()) {
            if (hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            context.startActivity(Intent(Intent.ACTION_VIEW, uri.toSpotifyUrl().toUri()))
        }.padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.clickable {
            context.startActivity(Intent(Intent.ACTION_VIEW, "https://open.spotify.com/user/${Uri.encode(activity.user.id)}".toUri()))
        }) {
            Artwork(activity.user.imageUrl, size = 44.dp)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(activity.user.displayName, style = MaterialTheme.typography.titleMedium)
            Text(if (activity.playing) "Listening now" else timeAgo(activity.timestamp), color = if (activity.playing) PlaytivityColors.primary else PlaytivityColors.textSecondary, style = MaterialTheme.typography.bodySmall)
            Text(content)
            if (detail.isNotEmpty()) Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        Artwork(activity.track?.imageUrl ?: activity.playlist?.imageUrl)
    }
}

@Composable
private fun ProfilePage(state: PlaytivityState, refresh: () -> Unit, modifier: Modifier = Modifier) {
    var tab by remember { mutableIntStateOf(0) }
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Column {
                Artwork(state.user?.imageUrl, size = 72.dp)
                Text(state.user?.displayName ?: "Profile", style = MaterialTheme.typography.titleLarge)
                Text("${state.user?.followers ?: 0} followers")
            }
            Button(onClick = refresh, enabled = !state.loadingProfile) { Text("Refresh") }
        }
        state.nowPlaying?.let { track ->
            val context = LocalContext.current
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).clickable {
                    context.startActivity(Intent(Intent.ACTION_VIEW, track.uri.toSpotifyUrl().toUri()))
                }.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(track.imageUrl, size = 40.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1)
                    Text(track.artists.joinToString(", "), color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
                Text("♫", color = PlaytivityColors.primary)
            }
        }
        if (state.loadingProfile) CircularProgressIndicator()
        if (state.profileError != null) Text(state.profileError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
        PrimaryTabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Top Songs") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Top Artists") })
        }
        if (tab == 0) {
            LazyColumn {
                items(state.top?.tracks.orEmpty().withIndex().toList(), key = { it.index }) { (index, track) -> TrackRow(track, index + 1) }
            }
        } else {
            LazyColumn {
                items(state.top?.artists.orEmpty().withIndex().toList(), key = { it.index }) { (index, artist) ->
                    ArtistRow(artist.copy(monthlyListeners = state.artistListeners[artist.uri.substringAfterLast(':')]?.takeIf { it >= 0 }), index + 1)
                }
            }
        }
    }
}

@Composable
private fun TrackRow(track: Track, rank: Int) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, track.uri.toSpotifyUrl().toUri())) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rank.toString(), Modifier.width(30.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Artwork(track.imageUrl)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1)
            Text(track.artists.joinToString(", "), maxLines = 1)
        }
        Text(formatDuration(track.durationMs), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    HorizontalDivider()
}

@Composable
private fun ArtistRow(artist: Artist, rank: Int) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, artist.uri.toSpotifyUrl().toUri())) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rank.toString(), Modifier.width(30.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Artwork(artist.imageUrl)
        Spacer(Modifier.width(12.dp))
        Column {
            Text(artist.name, style = MaterialTheme.typography.titleMedium)
            artist.monthlyListeners?.let { Text("${formatCount(it)} monthly listeners") }
        }
    }
    HorizontalDivider()
}

@Composable
private fun SettingsPage(state: PlaytivityState, viewModel: PlaytivityViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val view = LocalView.current
    var confirmLogout by remember { mutableStateOf(false) }
    var confirmNightly by remember { mutableStateOf(false) }
    fun openUrl(url: String) {
        if (state.hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
    }
    Column(modifier.fillMaxSize().padding(16.dp)) {
        Text("Settings", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(24.dp))
        state.user?.let { user ->
            Text(user.displayName, style = MaterialTheme.typography.titleMedium)
            user.email?.let { Text(it) }
            user.country?.let { Text("Country: $it") }
            TextButton(onClick = { openUrl("https://open.spotify.com/user/${Uri.encode(user.id)}") }) { Text("Open Spotify profile") }
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Haptic feedback")
            Switch(checked = state.hapticsEnabled, onCheckedChange = viewModel::setHapticsEnabled)
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Nightly builds")
            Switch(checked = state.nightlyUpdates, onCheckedChange = { enabled ->
                viewModel.setNightlyUpdates(enabled)
                if (enabled) confirmNightly = true
            })
        }
        Spacer(Modifier.height(12.dp))
        Button(onClick = viewModel::checkUpdateNow, enabled = !state.checkingUpdate) { Text("Check for updates") }
        state.updateMessage?.let { Text(it, Modifier.padding(top = 8.dp)) }
        Spacer(Modifier.height(24.dp))
        Text("Playtivity ${state.version}")
        TextButton(onClick = { openUrl("https://github.com/mliem2k/playtivity/releases") }) { Text("GitHub releases") }
        Text("See what your friends are listening to on Spotify")
        Spacer(Modifier.height(24.dp))
        Button(onClick = { confirmLogout = true }) { Text("Log out") }
    }
    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text("Log out?") },
            text = { Text("Are you sure you want to log out from your Spotify account?") },
            confirmButton = { TextButton(onClick = { confirmLogout = false; viewModel.signOut() }) { Text("Log out") } },
            dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("Cancel") } },
        )
    }
    if (confirmNightly) {
        AlertDialog(
            onDismissRequest = { confirmNightly = false },
            title = { Text("Nightly builds enabled") },
            text = { Text("You will now be offered nightly builds, which can be unstable. Check for updates now?") },
            confirmButton = { TextButton(onClick = { confirmNightly = false; viewModel.checkUpdateNow() }) { Text("Check now") } },
            dismissButton = { TextButton(onClick = { confirmNightly = false }) { Text("Later") } },
        )
    }
}

private fun String.toSpotifyUrl(): String = com.mliem.playtivity.core.spotifyUrl(this)
