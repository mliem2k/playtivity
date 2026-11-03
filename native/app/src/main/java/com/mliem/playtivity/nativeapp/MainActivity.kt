package com.mliem.playtivity.nativeapp

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.mliem.playtivity.core.Activity
import com.mliem.playtivity.core.Artist
import com.mliem.playtivity.core.SpotifyHttpClient
import com.mliem.playtivity.core.Track
import com.mliem.playtivity.core.formatCount
import com.mliem.playtivity.core.formatDuration
import com.mliem.playtivity.core.timeAgo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val viewModel: PlaytivityViewModel by viewModels { PlaytivityViewModel.Factory }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openWidgetLink(intent)
        setContent {
            val state by viewModel.state.collectAsStateWithLifecycle()
            PlaytivityTheme {
                when {
                    !state.ready -> LoadingScreen()
                    state.cookie == null -> LoginScreen(state, viewModel)
                    else -> AppScreen(state, viewModel)
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        viewModel.resume()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openWidgetLink(intent)
    }

    private fun openWidgetLink(intent: Intent?) {
        val url = intent?.getStringExtra("spotify_url") ?: return
        val uri = url.toUri()
        intent.removeExtra("spotify_url")
        if (uri.scheme == "https" && uri.host == "open.spotify.com") {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        }
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
private fun LoginScreen(state: PlaytivityState, viewModel: PlaytivityViewModel) {
    var webLogin by remember { mutableStateOf(false) }
    if (!webLogin) {
        Column(Modifier.fillMaxSize().background(Color.Black)) {
            Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.End) {
                IconButton(onClick = viewModel::checkUpdateNow, enabled = !state.checkingUpdate) {
                    Icon(Icons.Filled.SystemUpdate, contentDescription = "Check for updates", tint = PlaytivityColors.textSecondary)
                }
            }
            Column(
                Modifier.fillMaxSize().padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.weight(2f))
                Image(painterResource(R.drawable.playtivity_logo), contentDescription = null, modifier = Modifier.size(120.dp))
                Spacer(Modifier.height(32.dp))
                Text("Playtivity", style = TextStyle(fontFamily = playtivityFont, fontWeight = FontWeight.ExtraBold, fontSize = 32.sp, color = Color.White))
                Spacer(Modifier.height(12.dp))
                Text("See what your friends are listening to", color = PlaytivityColors.textSecondary, textAlign = TextAlign.Center)
                Spacer(Modifier.weight(3f))
                Button(onClick = { webLogin = true }, modifier = Modifier.fillMaxWidth().height(56.dp), shape = CircleShape) {
                    Image(painterResource(R.drawable.playtivity_logo_button_icon), contentDescription = null, modifier = Modifier.size(20.dp), colorFilter = ColorFilter.tint(Color.Black))
                    Spacer(Modifier.width(10.dp))
                    Text("Log in with Spotify", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(24.dp))
                Text("Playtivity uses your Spotify account", style = MaterialTheme.typography.bodySmall, color = PlaytivityColors.textSecondary)
                state.updateMessage?.let { Text(it, Modifier.padding(top = 8.dp), color = PlaytivityColors.textSecondary) }
                state.updateInfo?.let { info -> TextButton(onClick = viewModel::installUpdate) { Text("Install ${info.version}") } }
                Spacer(Modifier.weight(1f))
            }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            if (state.loginError != null) {
                Text(state.loginError, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error)
                Button(onClick = { webLogin = false }, modifier = Modifier.padding(horizontal = 12.dp)) { Text("Try again") }
            }
            if (state.signingIn) CircularProgressIndicator(Modifier.padding(12.dp))
            val scope = rememberCoroutineScope()
            var capturing by remember { mutableStateOf(false) }
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
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
                                            viewModel.signIn(cookie)
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
    BackHandler(enabled = state.page == Page.Settings) { viewModel.open(Page.Profile) }
    val pager = rememberPagerState(initialPage = if (state.page == Page.Profile) 1 else 0) { 2 }
    var profileTab by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(pager.settledPage) {
        val target = if (pager.settledPage == 0) Page.Activities else Page.Profile
        if (state.page != Page.Settings && state.page != target) viewModel.open(target)
    }
    Scaffold(
        topBar = {
            state.updateInfo?.let { info ->
                Column {
                    Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Update ${info.version} available", Modifier.weight(1f).padding(8.dp))
                        Button(onClick = viewModel::installUpdate, enabled = !state.installingUpdate) { Text("Install") }
                        Button(onClick = viewModel::dismissUpdate) { Text("Dismiss") }
                    }
                    state.updateMessage?.let { Text(it, Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.error) }
                }
            }
        },
        bottomBar = {
            if (state.page != Page.Settings) {
                Row(Modifier.fillMaxWidth().height(64.dp).background(Color.Black)) {
                    listOf(Triple(Page.Activities, "Activities", Icons.Filled.Home), Triple(Page.Profile, "Profile", Icons.Filled.Person))
                        .forEach { (page, label, icon) ->
                            val selected = (if (pager.currentPage == 0) Page.Activities else Page.Profile) == page
                            Column(
                                Modifier.weight(1f).fillMaxHeight().selectable(selected = selected, role = Role.Tab, onClick = { scope.launch { pager.animateScrollToPage(if (page == Page.Activities) 0 else 1) } }),
                                verticalArrangement = Arrangement.Center,
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Icon(icon, contentDescription = null, tint = if (selected) Color.White else PlaytivityColors.textSecondary)
                                Spacer(Modifier.height(4.dp))
                                Text(label, style = MaterialTheme.typography.bodySmall, color = if (selected) Color.White else PlaytivityColors.textSecondary)
                            }
                        }
                }
            }
        },
        containerColor = PlaytivityColors.background,
    ) { padding ->
        if (state.page == Page.Settings) {
            SettingsPage(state, viewModel, Modifier.padding(padding))
        } else {
            // Each page paints its own background, so nothing changes colour while a swipe is in flight.
            // The profile page owns its tab swipe, so the pager only scrolls by touch from Activities.
            HorizontalPager(pager, Modifier.fillMaxSize(), userScrollEnabled = pager.settledPage == 0) { index ->
                if (index == 0) {
                    ActivitiesPage(state, viewModel::refreshFeed, Modifier.background(PlaytivityColors.background).padding(padding))
                } else {
                    ProfilePage(
                        state, viewModel::refreshProfile, { viewModel.open(Page.Settings) }, profileTab, { profileTab = it },
                        { scope.launch { pager.animateScrollToPage(0) } },
                        Modifier.background(PlaytivityColors.primary).padding(padding),
                    )
                }
            }
        }
    }
}

/** Fires [onLeft] or [onRight] after a horizontal drag of 100 px or more; vertical scrolling is unaffected. */
@Composable
private fun Modifier.swipeHorizontally(onLeft: () -> Unit, onRight: () -> Unit): Modifier {
    val left by rememberUpdatedState(onLeft)
    val right by rememberUpdatedState(onRight)
    return pointerInput(Unit) {
        var total = 0f
        detectHorizontalDragGestures(
            onDragStart = { total = 0f },
            onDragEnd = { if (total < -100f) left() else if (total > 100f) right() },
        ) { _, delta -> total += delta }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivitiesPage(state: PlaytivityState, refresh: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
            Text("Friend Activity", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        }
        Box(Modifier.fillMaxWidth().height(2.dp).background(if (state.loadingFeed && state.activities.isNotEmpty()) PlaytivityColors.primary else Color.Transparent))
        PullToRefreshBox(isRefreshing = state.loadingFeed, onRefresh = refresh, modifier = Modifier.fillMaxSize()) {
            LazyColumn(Modifier.fillMaxSize()) {
                if (state.feedError != null) item { Text(state.feedError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
                if (state.activities.isEmpty() && !state.loadingFeed) item { Text("No friend activity", Modifier.padding(16.dp)) }
                items(state.activities, key = { it.user.id }) { activity ->
                    ActivityRow(activity)
                    HorizontalDivider(color = PlaytivityColors.divider)
                }
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
        }.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.clickable {
            context.startActivity(Intent(Intent.ACTION_VIEW, "https://open.spotify.com/user/${Uri.encode(activity.user.id)}".toUri()))
        }) {
            Artwork(activity.user.imageUrl, size = 44.dp, shape = CircleShape)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(activity.user.displayName, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (activity.playing) {
                    Text("▮▮▮", fontSize = 11.sp, color = PlaytivityColors.primaryActive)
                } else {
                    Icon(Icons.Filled.History, contentDescription = null, modifier = Modifier.size(12.dp), tint = PlaytivityColors.textSecondary)
                }
                Spacer(Modifier.width(4.dp))
                Text(if (activity.playing) "Listening now" else timeAgo(activity.timestamp), fontSize = 11.sp, color = if (activity.playing) PlaytivityColors.primaryActive else PlaytivityColors.textSecondary, maxLines = 1)
            }
            if (content.isNotEmpty()) Text(content, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (detail.isNotEmpty()) Text(detail, fontSize = 13.sp, color = PlaytivityColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(12.dp))
        Artwork(
            activity.track?.imageUrl ?: activity.playlist?.imageUrl,
            modifier = if (activity.playing) Modifier.border(2.dp, PlaytivityColors.primaryActive, RoundedCornerShape(4.dp)) else Modifier,
        )
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun ProfilePage(state: PlaytivityState, refresh: () -> Unit, onSettings: () -> Unit, tab: Int, onTab: (Int) -> Unit, onSwipeBack: () -> Unit, modifier: Modifier = Modifier) {
    CompositionLocalProvider(LocalContentColor provides Color.White) {
        PullToRefreshBox(isRefreshing = state.loadingProfile, onRefresh = refresh, modifier = modifier.fillMaxSize().background(PlaytivityColors.background)) {
            LazyColumn(Modifier.fillMaxSize()) {
                item { ProfileHero(state, onSettings) }
                stickyHeader {
                    Row(Modifier.fillMaxWidth().height(48.dp).background(PlaytivityColors.background)) {
                        listOf("Top Songs", "Top Artists").forEachIndexed { index, label ->
                            Box(Modifier.weight(1f).fillMaxHeight().selectable(selected = tab == index, role = Role.Tab, onClick = { onTab(index) }), contentAlignment = Alignment.Center) {
                                Text(label, fontSize = 13.sp, fontWeight = if (tab == index) FontWeight.SemiBold else FontWeight.Normal, color = if (tab == index) Color.White else PlaytivityColors.textSecondary)
                                if (tab == index) Box(Modifier.align(Alignment.BottomCenter).width(72.dp).height(2.dp).background(PlaytivityColors.primary))
                            }
                        }
                    }
                }
                if (state.profileError != null) item { Text(state.profileError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
                // Only this list slides between tabs; the header above stays put.
                item {
                    AnimatedContent(
                        targetState = tab,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 400.dp).clipToBounds().background(PlaytivityColors.background)
                            .swipeHorizontally(onLeft = { onTab(1) }, onRight = { if (tab == 1) onTab(0) else onSwipeBack() }),
                        transitionSpec = {
                            val forward = targetState > initialState
                            (slideInHorizontally { if (forward) it else -it } + fadeIn()) togetherWith
                                (slideOutHorizontally { if (forward) -it else it } + fadeOut())
                        },
                        label = "profileTab",
                    ) { shown ->
                        Column(Modifier.fillMaxWidth()) {
                            if (shown == 0) {
                                state.top?.tracks.orEmpty().forEachIndexed { index, track -> TrackRow(track, index + 1) }
                            } else {
                                state.top?.artists.orEmpty().forEachIndexed { index, artist ->
                                    ArtistRow(artist.copy(monthlyListeners = state.artistListeners[artist.uri.substringAfterLast(':')]?.takeIf { it >= 0 }), index + 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProfileHero(state: PlaytivityState, onSettings: () -> Unit) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxWidth().background(Brush.verticalGradient(0f to PlaytivityColors.primary, 0.7f to PlaytivityColors.background, 1f to PlaytivityColors.background)),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 8.dp), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = onSettings) { Icon(Icons.Filled.Settings, contentDescription = "Settings", tint = Color.White) }
        }
        Artwork(
            state.user?.imageUrl,
            size = 92.dp,
            shape = CircleShape,
            modifier = Modifier.border(BorderStroke(2.dp, Color.White.copy(alpha = 0.2f)), CircleShape).clickable(enabled = state.user != null) {
                state.user?.let { context.startActivity(Intent(Intent.ACTION_VIEW, "https://open.spotify.com/user/${Uri.encode(it.id)}".toUri())) }
            },
        )
        Spacer(Modifier.height(12.dp))
        Text(state.user?.displayName ?: "Profile", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Text("${state.user?.followers ?: 0} followers", fontSize = 13.sp, color = PlaytivityColors.textSecondary)
        state.nowPlaying?.let { track ->
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp).background(PlaytivityColors.surfaceRaised).clickable {
                    context.startActivity(Intent(Intent.ACTION_VIEW, track.uri.toSpotifyUrl().toUri()))
                }.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(track.imageUrl, size = 40.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(track.name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(track.artists.joinToString(", "), fontSize = 13.sp, color = PlaytivityColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Icon(Icons.Filled.MusicNote, contentDescription = "Playing", tint = PlaytivityColors.primaryActive)
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun TrackRow(track: Track, rank: Int) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, track.uri.toSpotifyUrl().toUri())) }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rank.toString(), Modifier.width(36.dp), fontSize = 14.sp, color = PlaytivityColors.textSubdued)
        Artwork(track.imageUrl)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(track.name, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(track.artists.joinToString(", "), fontSize = 13.sp, color = PlaytivityColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(formatDuration(track.durationMs), fontSize = 11.sp, color = PlaytivityColors.textSubdued)
    }
    HorizontalDivider(color = PlaytivityColors.divider)
}

@Composable
private fun ArtistRow(artist: Artist, rank: Int) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, artist.uri.toSpotifyUrl().toUri())) }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rank.toString(), Modifier.width(36.dp), fontSize = 14.sp, color = PlaytivityColors.textSubdued)
        Artwork(artist.imageUrl, shape = CircleShape)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(artist.name, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            artist.monthlyListeners?.let { Text("${formatCount(it)} monthly listeners", fontSize = 12.sp, color = PlaytivityColors.textSecondary, maxLines = 1) }
        }
    }
    HorizontalDivider(color = PlaytivityColors.divider)
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
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().height(56.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { viewModel.open(Page.Profile) }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
            Text("Settings", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Row(
                Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(PlaytivityColors.primary, PlaytivityColors.background))).padding(horizontal = 16.dp, vertical = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(state.user?.imageUrl, size = 80.dp, shape = CircleShape)
                Spacer(Modifier.width(16.dp))
                Text(state.user?.displayName ?: "Profile", Modifier.weight(1f), fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                state.user?.let { user ->
                    IconButton(onClick = { openUrl("https://open.spotify.com/user/${Uri.encode(user.id)}") }) {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = "Open Spotify profile", tint = PlaytivityColors.textSecondary)
                    }
                }
            }
            SettingsSection("ACCOUNT")
            SettingsTile(Icons.Filled.Public, "Country", state.user?.country)
            SettingsDivider()

            SettingsSection("PREFERENCES")
            SettingsTile(Icons.Filled.Vibration, "Haptic Feedback", "Vibrate on taps and swipes", onClick = { viewModel.setHapticsEnabled(!state.hapticsEnabled) }) {
                Switch(checked = state.hapticsEnabled, onCheckedChange = viewModel::setHapticsEnabled, colors = SwitchDefaults.colors(checkedTrackColor = PlaytivityColors.primary))
            }
            SettingsDivider()

            SettingsSection("UPDATES")
            SettingsTile(Icons.Filled.Update, "Nightly Builds", "Get early access to new features (may be unstable)", onClick = {
                val enabled = !state.nightlyUpdates
                viewModel.setNightlyUpdates(enabled)
                if (enabled) confirmNightly = true
            }) {
                Switch(checked = state.nightlyUpdates, onCheckedChange = { enabled ->
                    viewModel.setNightlyUpdates(enabled)
                    if (enabled) confirmNightly = true
                }, colors = SwitchDefaults.colors(checkedTrackColor = PlaytivityColors.primary))
            }
            SettingsDivider()
            SettingsTile(Icons.Filled.SystemUpdate, "Check for Updates", "Look for new versions of the app", onClick = viewModel::checkUpdateNow)
            state.updateMessage?.let { Text(it, Modifier.padding(horizontal = 56.dp), color = PlaytivityColors.textSecondary) }

            SettingsSection("ABOUT")
            SettingsTile(Icons.Filled.Info, "Playtivity", "Version ${state.version}")
            SettingsDivider()
            SettingsTile(Icons.Filled.OpenInBrowser, "GitHub Releases", "View all releases and download APKs", onClick = { openUrl("https://github.com/mliem2k/playtivity/releases") })
            SettingsDivider()
            SettingsTile(Icons.Filled.MusicNote, "About", "See what your friends are listening to on Spotify")
            Spacer(Modifier.height(32.dp))
            SettingsTile(Icons.AutoMirrored.Filled.Logout, "Log Out", onClick = { confirmLogout = true }, danger = true)
            Spacer(Modifier.height(16.dp))
        }
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

@Composable
private fun SettingsSection(label: String) {
    Text(label, Modifier.fillMaxWidth().padding(start = 16.dp, top = 24.dp, bottom = 12.dp), fontSize = 11.sp, letterSpacing = 1.5.sp, color = PlaytivityColors.textSecondary)
}

@Composable
private fun SettingsDivider() {
    HorizontalDivider(Modifier.padding(start = 56.dp), color = PlaytivityColors.divider)
}

@Composable
private fun SettingsTile(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    danger: Boolean = false,
    trailing: @Composable (() -> Unit)? = null,
) {
    val color = if (danger) PlaytivityColors.error else Color.White
    Row(
        Modifier.fillMaxWidth().clickable(enabled = onClick != null) { onClick?.invoke() }.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (danger) PlaytivityColors.error else PlaytivityColors.textSecondary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(18.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 14.sp, fontWeight = if (danger) FontWeight.Bold else FontWeight.Medium, color = color)
            subtitle?.let { Text(it, fontSize = 13.sp, color = PlaytivityColors.textSecondary) }
        }
        if (trailing != null) trailing()
        else if (onClick != null && !danger) Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = PlaytivityColors.textSecondary)
    }
}

private fun String.toSpotifyUrl(): String = com.mliem.playtivity.core.spotifyUrl(this)
