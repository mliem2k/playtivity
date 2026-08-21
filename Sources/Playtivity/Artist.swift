import Foundation

/// Pure-Swift port of lib/models/artist.dart (`/tmp/ref_artist.dart`). Uses the same
/// `[String: Any]` dictionary-based `fromJson`/`toJson` pattern as `Track.swift` rather than
/// `Decodable`/`JSONDecoder`, per this phase's established Skip Kotlin-transpile constraint.
struct Artist: Codable, Equatable {
    let id: String
    let name: String
    let imageUrl: String?
    let followers: Int
    let monthlyListeners: Int
    let uri: String

    /// Ported from `ref_artist.dart`'s `Artist.fromJson` (lines 18-27). `followers` and
    /// `monthlyListeners` default to `-1`, not `0`: `-1` is a real "not yet fetched" sentinel
    /// `ArtistTile` (a later task) gates its monthly-listeners display on (`>= 0`), distinct from
    /// a confirmed `0`. Do not copy `Track`'s `?? 0` idiom here.
    static func fromJson(_ json: [String: Any]) -> Artist {
        Artist(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            imageUrl: json["image_url"] as? String,
            followers: Artist.intValue(from: json["followers"]) ?? -1,
            monthlyListeners: Artist.intValue(from: json["monthly_listeners"]) ?? -1,
            uri: json["uri"] as? String ?? ""
        )
    }

    /// Ported from `ref_artist.dart`'s `Artist.toJson` (lines 29-38).
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "followers": followers,
            "monthly_listeners": monthlyListeners,
            "uri": uri,
        ]
        if let imageUrl { json["image_url"] = imageUrl }
        return json
    }

    // JSON numeric values from `JSONSerialization` can arrive boxed as either a 32-bit or 64-bit
    // integer depending on magnitude and platform, so both are tried explicitly, same fix as
    // `Track.intValue`/`SpotifySecretsService.intValue`/`AuthStore.intValue`.
    private static func intValue(from element: Any?) -> Int? {
        if let value = element as? Int { return value }
        if let value = element as? Int32 { return Int(value) }
        return nil
    }
}
