import Foundation

/// Pure-Swift port of lib/models/track.dart. `fromJson`/`toJson` handle two distinct JSON shapes
/// for the same logical data: the nested Spotify Web API shape (album as an object, artists as a
/// list of `{name, uri}` objects) and this app's own flat persisted shape (this type's own
/// `toJson()` output, round-tripped through `UserDefaults` inside `Activity`). This dual handling
/// is what lets `Activity` round-trip through `UserDefaults` correctly; it is not incidental
/// complexity and must not be simplified to a single format.
///
/// `fromJson`/`toJson` work on raw `[String: Any]` dictionaries (the shape
/// `JSONSerialization.jsonObject(with:)` produces) rather than through Swift's `Decodable`
/// container machinery: Skip's Kotlin transpiler silently mis-decodes an array of a locally-nested
/// custom struct through `Decoder`/`KeyedDecodingContainer` (elements come back as untyped maps at
/// runtime rather than typed struct instances, or the array's element type fails to compile,
/// depending on the exact shape), while plain dictionary/array access with `as?` casts is the same
/// proven pattern already used throughout this codebase for external API responses (`AuthStore`,
/// `SpotifyTokenService`, `SpotifySecretsService`). `Codable` conformance below is plain
/// compiler-synthesized (every stored property maps 1:1 to the flat shape via `CodingKeys`), kept
/// only to satisfy the type's own contract; `fromJson`/`toJson` are the dual-format API this phase
/// actually needs.
struct Track: Codable, Equatable {
    let id: String
    let name: String
    let artists: [String]
    let artistUris: [String]
    let album: String
    let albumUri: String?
    let imageUrl: String?
    let durationMs: Int
    let previewUrl: String?
    let uri: String

    init(
        id: String,
        name: String,
        artists: [String],
        artistUris: [String] = [],
        album: String,
        albumUri: String? = nil,
        imageUrl: String? = nil,
        durationMs: Int,
        previewUrl: String? = nil,
        uri: String
    ) {
        self.id = id
        self.name = name
        self.artists = artists
        self.artistUris = artistUris
        self.album = album
        self.albumUri = albumUri
        self.imageUrl = imageUrl
        self.durationMs = durationMs
        self.previewUrl = previewUrl
        self.uri = uri
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, artists
        case artistUris = "artist_uris"
        case album
        case albumUri = "album_uri"
        case imageUrl = "image_url"
        case durationMs = "duration_ms"
        case previewUrl = "preview_url"
        case uri
    }

    /// Dual-format factory, ported from `ref_track_model.dart`'s `Track.fromJson` (lines 28-83).
    static func fromJson(_ json: [String: Any]) -> Track {
        let albumRaw = json["album"]
        let albumName: String
        let albumUri: String?
        let imageUrl: String?

        // album is a nested object in the live Spotify API shape, a flat string in this app's own
        // persisted shape.
        if let albumMap = albumRaw as? [String: Any] {
            albumName = albumMap["name"] as? String ?? ""
            albumUri = albumMap["uri"] as? String
            let images = albumMap["images"] as? [[String: Any]]
            imageUrl = (json["image_url"] as? String)
                ?? (albumMap["imageUrl"] as? String)
                ?? (images?.first?["url"] as? String)
        } else {
            albumName = albumRaw as? String ?? ""
            albumUri = json["album_uri"] as? String
            imageUrl = json["image_url"] as? String
        }

        // artists is a list of {name, uri} objects in the API shape, a list of plain name strings
        // in the persisted shape. artist_uris carries the persisted shape's separate URI list;
        // URIs found on the artist objects themselves take priority over it, matching the Dart
        // original.
        let rawArtists = json["artists"] as? [Any] ?? []
        var artistNames: [String] = []
        var urisFromList: [String] = []
        for element in rawArtists {
            if let name = element as? String {
                if !name.isEmpty { artistNames.append(name) }
            } else if let artistMap = element as? [String: Any] {
                let name = artistMap["name"] as? String ?? ""
                let uri = artistMap["uri"] as? String ?? ""
                if !name.isEmpty { artistNames.append(name) }
                if !uri.isEmpty { urisFromList.append(uri) }
            }
        }
        let rawUris = json["artist_uris"] as? [String]
        let artistUris = !urisFromList.isEmpty ? urisFromList : (rawUris ?? [])

        return Track(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            artists: artistNames,
            artistUris: artistUris,
            album: albumName,
            albumUri: albumUri,
            imageUrl: imageUrl,
            durationMs: Track.intValue(from: json["duration_ms"]) ?? 0,
            previewUrl: json["preview_url"] as? String,
            uri: json["uri"] as? String ?? ""
        )
    }

    /// Ported from `ref_track_model.dart`'s `Track.toJson` (lines 85-97). Always the flat
    /// persisted shape (this is the format `fromJson` reads back on the next app launch).
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "artists": artists,
            "artist_uris": artistUris,
            "album": album,
            "duration_ms": durationMs,
            "uri": uri,
        ]
        json["album_uri"] = albumUri
        json["image_url"] = imageUrl
        json["preview_url"] = previewUrl
        return json
    }

    // JSON numeric values from `JSONSerialization` can arrive boxed as either a 32-bit or 64-bit
    // integer depending on magnitude and platform, so both are tried explicitly, same fix as
    // `SpotifySecretsService.intValue`/`AuthStore.intValue`.
    private static func intValue(from element: Any?) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    var artistsString: String { artists.joined(separator: ", ") }

    var duration: String {
        let minutes = durationMs / 60000
        let seconds = (durationMs % 60000) / 1000
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }

    var firstArtistUri: String? { artistUris.first }
}
