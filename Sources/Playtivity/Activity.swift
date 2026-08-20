import Foundation

enum ActivityType: String, Codable, Equatable {
    case track
    case playlist
}

private struct ActivityDecodingError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Pure-Swift port of lib/models/activity.dart. `type` decodes from the JSON string ("playlist"
/// vs. anything else, defaulting to "track"), matching the Dart original's ternary. Deliberate
/// deviation from a straight port: `isCurrentlyPlaying` is always recomputed from the current
/// clock in `fromJson` rather than trusted from the persisted value, because a persisted activity
/// can be hours old and a stale `true` must not show "Listening now" forever after a friend
/// stopped playing.
///
/// `fromJson`/`toJson` work on raw `[String: Any]` dictionaries rather than through `Decodable`'s
/// container machinery, matching `Track`/`Playlist` (see their doc comments for why: Skip's
/// Kotlin transpiler is unreliable for nested custom-struct arrays decoded that way). `Codable`
/// conformance below is plain compiler-synthesized, kept only to satisfy the type's own contract;
/// `fromJson`/`toJson` are the API this phase actually uses.
struct Activity: Codable, Equatable {
    let user: User
    let track: Track?
    let playlist: Playlist?
    let timestamp: Date
    let isCurrentlyPlaying: Bool
    let type: ActivityType

    init(
        user: User,
        track: Track? = nil,
        playlist: Playlist? = nil,
        timestamp: Date,
        isCurrentlyPlaying: Bool,
        type: ActivityType
    ) {
        precondition(
            Activity.isValidPairing(track: track, playlist: playlist, type: type),
            "Activity requires exactly one of track/playlist to be set, matching type"
        )
        self.user = user
        self.track = track
        self.playlist = playlist
        self.timestamp = timestamp
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.type = type
    }

    /// The invariant the Dart original enforces with an `assert` in its constructor, extracted as
    /// a pure, directly-testable predicate rather than only living inside the `precondition` call
    /// (which traps the process and so cannot be exercised by a passing test).
    static func isValidPairing(track: Track?, playlist: Playlist?, type: ActivityType) -> Bool {
        (track != nil && playlist == nil && type == ActivityType.track) ||
            (playlist != nil && track == nil && type == ActivityType.playlist)
    }

    /// Recomputes `isCurrentlyPlaying` from the clock, matching the Dart original's decode-time
    /// recompute (it never trusts a persisted flag). Playlists are never "currently playing"; a
    /// track counts as currently playing only if its timestamp is not in the future and is less
    /// than 5 minutes old. `now` is injectable for deterministic tests.
    static func computeIsCurrentlyPlaying(type: ActivityType, timestamp: Date, now: Date = Date()) -> Bool {
        guard type == ActivityType.track else { return false }
        let elapsedMs = now.timeIntervalSince(timestamp) * 1000
        return elapsedMs >= 0 && elapsedMs < Double(5 * 60 * 1000)
    }

    /// Dual-format factory, ported from `ref_activity_model.dart`'s `Activity.fromJson`
    /// (lines 25-48). Throws on malformed input (missing/invalid `user`, `timestamp`, or the
    /// required `track`/`playlist` sub-object for the decoded `type`), matching the Dart
    /// original's own crash-on-malformed-input behavior for this outer shape (only the fields
    /// *within* `Track`/`Playlist` are individually defensive/defaulting).
    static func fromJson(_ json: [String: Any]) throws -> Activity {
        guard let userJson = json["user"] as? [String: Any], let user = Activity.decodeUser(userJson) else {
            throw ActivityDecodingError(message: "Activity.fromJson: missing or invalid 'user'")
        }

        let rawType = json["type"] as? String
        let type: ActivityType = (rawType == "playlist") ? ActivityType.playlist : ActivityType.track

        guard let rawTimestamp = json["timestamp"] as? String,
              let timestamp = Activity.parseTimestamp(rawTimestamp) else {
            throw ActivityDecodingError(message: "Activity.fromJson: missing or invalid 'timestamp'")
        }

        let track: Track?
        if type == ActivityType.track {
            guard let trackJson = json["track"] as? [String: Any] else {
                throw ActivityDecodingError(message: "Activity.fromJson: missing 'track' for type track")
            }
            track = Track.fromJson(trackJson)
        } else {
            track = nil
        }

        let playlist: Playlist?
        if type == ActivityType.playlist {
            guard let playlistJson = json["playlist"] as? [String: Any] else {
                throw ActivityDecodingError(message: "Activity.fromJson: missing 'playlist' for type playlist")
            }
            playlist = Playlist.fromJson(playlistJson)
        } else {
            playlist = nil
        }

        let isCurrentlyPlaying = Activity.computeIsCurrentlyPlaying(type: type, timestamp: timestamp)

        return Activity(
            user: user, track: track, playlist: playlist, timestamp: timestamp,
            isCurrentlyPlaying: isCurrentlyPlaying, type: type
        )
    }

    /// Ported from `ref_activity_model.dart`'s `Activity.toJson` (lines 50-59).
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "user": Activity.userToJson(user),
            "timestamp": Activity.formatTimestamp(timestamp),
            "is_currently_playing": isCurrentlyPlaying,
            "type": type == ActivityType.playlist ? "playlist" : "track",
        ]
        json["track"] = track?.toJson()
        json["playlist"] = playlist?.toJson()
        return json
    }

    // MARK: - User <-> JSON bridging

    // `User` (ported in Phase 2) is a plain `Codable` type with no `fromJson`/`toJson` pair of its
    // own, so a sub-dictionary is bridged through it via a `Data` round trip rather than manual
    // field-by-field extraction. `User`'s fields are all flat primitives (no nested arrays of
    // custom structs), so this is not exposed to the Skip transpile issue `Track`/`Playlist` work
    // around; it is the same `JSONEncoder`/`JSONDecoder` mechanism `AuthStore` already uses to
    // persist `User`.
    private static func decodeUser(_ json: [String: Any]) -> User? {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    private static func userToJson(_ user: User) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(user),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    // MARK: - Timestamp <-> ISO8601 string

    // Fresh DateFormatter per call rather than a cached static instance: DateFormatter is not
    // safe to format/parse concurrently from multiple threads, and fromJson/toJson can both run
    // from background Tasks. Matches the per-call DateFormatter construction already established
    // in AuthStore.addEvent and SpotifyTokenService.parseHttpDate.
    private static func iso8601Formatter(withFractionalSeconds: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = withFractionalSeconds ? "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        iso8601Formatter(withFractionalSeconds: true).date(from: raw)
            ?? iso8601Formatter(withFractionalSeconds: false).date(from: raw)
    }

    private static func formatTimestamp(_ date: Date) -> String {
        iso8601Formatter(withFractionalSeconds: true).string(from: date)
    }

    // MARK: - Computed content properties

    var contentName: String { track?.name ?? playlist?.name ?? "Unknown" }
    var contentUri: String { track?.uri ?? playlist?.uri ?? "" }
    var contentImageUrl: String? { track?.imageUrl ?? playlist?.imageUrl }

    var contentSubtitle: String {
        if let track {
            return track.artistsString
        }
        return "Playlist • \(playlist?.trackCount ?? 0) tracks"
    }

    var contentDetails: String {
        if let track {
            return track.album
        }
        return "by \(playlist?.ownerName ?? "Unknown")"
    }
}
