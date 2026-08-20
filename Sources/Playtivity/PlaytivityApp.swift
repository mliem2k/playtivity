import Foundation
import OSLog
import SwiftUI

/// A logger for the Playtivity module.
let logger: Logger = Logger(subsystem: "com.mliem.playtivity", category: "Playtivity")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// Port of the Dart original's `AppWrapper` (`lib/widgets/app_wrapper.dart`): owns the single
/// `AuthStore`/`SpotifyStore` instance pair for the whole app (constructed once as `@State`,
/// matching `ContentView`'s own `@State var viewModel = ViewModel()` precedent in this codebase),
/// drives `authStore.initialize()` once on appear, routes between a loading placeholder,
/// `LoginScreen`, and `ActivitiesScreen` by `authStore`'s state, and bridges bearer-token changes
/// into `SpotifyStore` the same way Dart's `AppWrapper` does on every `Consumer<AuthProvider>`
/// rebuild: `authState == .authenticated && bearerToken != nil` -> `setBearer`, `authState ==
/// .unauthenticated` -> `clearBearer`. Ported here as an `.onChange(of: authStore.bearerToken)`
/// observer instead of a rebuild-time check, since SwiftUI has no direct equivalent of Provider's
/// "run this on every rebuild" `Consumer` callback; observing the token itself (rather than
/// `authState`) covers the same transitions `AppWrapper` cares about (fresh login, logout) plus
/// AuthStore's own silent-refresh/token-recovery paths that also mutate `bearerToken` without an
/// `authState` change, which the Dart original does not have to consider separately since Dart's
/// `notifyListeners()`-driven rebuild fires on every state mutation regardless of which field
/// changed.
public struct PlaytivityRootView : View {
    @State private var authStore = AuthStore()
    @State private var spotifyStore = SpotifyStore()

    public init() {
    }

    public var body: some View {
        Group {
            if !authStore.isInitialized {
                loadingBody
            } else if !authStore.isAuthenticated {
                unauthenticatedRoute
            } else {
                ActivitiesScreen(authStore: authStore, spotifyStore: spotifyStore)
            }
        }
        .task {
            logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            await authStore.initialize()
        }
        .onChange(of: authStore.bearerToken) { _, newToken in
            Task {
                if let newToken, !newToken.isEmpty {
                    await spotifyStore.setBearer(newToken)
                } else {
                    await spotifyStore.clearBearer()
                }
            }
        }
    }

    /// Minimal loading placeholder shown before `authStore.initialize()` completes, matching the
    /// minimalism of `ActivitiesScreen.initializingBody` (this screen has no debug event panel
    /// like Dart's `AuthLoadingScreen`, since none of this phase's files build one).
    private var loadingBody: some View {
        VStack {
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `LoginScreen` itself is gated `#if SKIP || os(iOS)` (its own WebView dependency, SkipWeb,
    /// only exists for the real Android/iOS targets, not a native macOS build), so this root view
    /// mirrors the same gate rather than referencing a type that does not exist when `swift build`/
    /// `swift test` compile natively on macOS. The native-macOS branch is dev-machine-only; this
    /// app never ships to macOS (see `LoginScreen.swift`'s own doc comment for the full rationale).
    @ViewBuilder
    private var unauthenticatedRoute: some View {
        #if SKIP || os(iOS)
        LoginScreen(authStore: authStore)
        #else
        Text("Login is only available on iOS/Android builds.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
public final class PlaytivityAppDelegate : Sendable {
    public static let shared = PlaytivityAppDelegate()

    private init() {
    }

    public func onInit() {
        logger.debug("onInit")
    }

    public func onLaunch() {
        logger.debug("onLaunch")
    }

    public func onResume() {
        logger.debug("onResume")
    }

    public func onPause() {
        logger.debug("onPause")
    }

    public func onStop() {
        logger.debug("onStop")
    }

    public func onDestroy() {
        logger.debug("onDestroy")
    }

    public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
