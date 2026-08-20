import Foundation
import SwiftUI
import XCTest
@testable import Playtivity

// `OpenURLAction.init(handler:)` is `@MainActor`-isolated (confirmed via a real build failure
// while writing this file: constructing one from a plain nonisolated test method triggers
// "sending value of non-Sendable type ... risks causing data races" under Swift 6). The whole
// class is marked `@MainActor` rather than each test individually, since every test here
// constructs an `OpenURLAction`.
@MainActor
final class SpotifyDeepLinkLogicTests: XCTestCase {
    // MARK: - contentTarget / webURL(fromSpotifyUri:) (ref_spotify_launcher.dart:72-83)

    func testContentTargetForTrackUri() {
        let target = SpotifyDeepLink.contentTarget(uri: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(target.appURL, URL(string: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh"))
        XCTAssertEqual(target.webURL, URL(string: "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"))
    }

    func testContentTargetForPlaylistUri() {
        let target = SpotifyDeepLink.contentTarget(uri: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        XCTAssertEqual(target.appURL, URL(string: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"))
        XCTAssertEqual(target.webURL, URL(string: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"))
    }

    func testFriendProfileTargetBuildsUserUri() {
        let target = SpotifyDeepLink.friendProfileTarget(userId: "spotifyuser123")
        XCTAssertEqual(target.appURL, URL(string: "spotify:user:spotifyuser123"))
        XCTAssertEqual(target.webURL, URL(string: "https://open.spotify.com/user/spotifyuser123"))
    }

    func testContentTargetForEmptyUriHasNoUrls() {
        let target = SpotifyDeepLink.contentTarget(uri: "")
        XCTAssertNil(target.appURL)
        XCTAssertNil(target.webURL)
    }

    func testWebUrlNilWhenUriHasNoSpotifyPrefix() {
        XCTAssertNil(SpotifyDeepLink.webURL(fromSpotifyUri: "https://example.com/track/123"))
    }

    func testWebUrlNilWhenUriHasFewerThanThreeParts() {
        XCTAssertNil(SpotifyDeepLink.webURL(fromSpotifyUri: "spotify:track"))
    }

    func testWebUrlNilForEmptyUri() {
        XCTAssertNil(SpotifyDeepLink.webURL(fromSpotifyUri: ""))
    }

    // MARK: - open(_:using:)

    func testOpenTriesAppUrlFirstAndStopsWhenAccepted() {
        var opened: [URL] = []
        let action = OpenURLAction(handler: { url in
            opened.append(url)
            return .handled
        })
        let target = SpotifyDeepLink.contentTarget(uri: "spotify:track:abc")
        SpotifyDeepLink.open(target, using: action)
        XCTAssertEqual(opened, [target.appURL!])
    }

    func testOpenFallsBackToWebUrlWhenAppUrlDiscarded() {
        var opened: [URL] = []
        let action = OpenURLAction(handler: { url in
            opened.append(url)
            return .discarded
        })
        let target = SpotifyDeepLink.contentTarget(uri: "spotify:track:abc")
        SpotifyDeepLink.open(target, using: action)
        XCTAssertEqual(opened, [target.appURL!, target.webURL!])
    }

    func testOpenIsNoOpWhenTargetHasNoUrls() {
        var opened: [URL] = []
        let action = OpenURLAction(handler: { url in
            opened.append(url)
            return .handled
        })
        SpotifyDeepLink.open(SpotifyDeepLink.contentTarget(uri: ""), using: action)
        XCTAssertTrue(opened.isEmpty)
    }

    func testOpenGoesStraightToWebUrlWhenNoAppUrl() {
        // Constructed directly since contentTarget never itself produces a nil-appURL/non-nil-webURL
        // combination; exercises open(_:using:)'s own nil-appURL branch in isolation.
        var opened: [URL] = []
        let action = OpenURLAction(handler: { url in
            opened.append(url)
            return .handled
        })
        let webOnly = SpotifyDeepLink.Target(appURL: nil, webURL: URL(string: "https://open.spotify.com/track/abc")!)
        SpotifyDeepLink.open(webOnly, using: action)
        XCTAssertEqual(opened, [webOnly.webURL!])
    }
}
