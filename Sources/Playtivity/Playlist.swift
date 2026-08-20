import Foundation

/// Pure-Swift port of lib/models/playlist.dart. `fromJson`/`toJson` handle both this app's own
/// flat persisted shape (this type's own `toJson()` output) and the nested Spotify Web API shape,
/// distinguished by which keys are present, exactly mirroring the Dart original's `containsKey`
/// checks (a key mapped to JSON `null` still counts as present). Implemented via raw
/// `[String: Any]` dictionary access rather than `Decodable`; see `Track`'s doc comment for why.
struct Playlist: Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let imageUrl: String?
    let trackCount: Int
    let uri: String
    let ownerId: String
    let ownerName: String
    let isPublic: Bool

    init(
        id: String,
        name: String,
        description: String? = nil,
        imageUrl: String? = nil,
        trackCount: Int,
        uri: String,
        ownerId: String,
        ownerName: String,
        isPublic: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.imageUrl = imageUrl
        self.trackCount = trackCount
        self.uri = uri
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.isPublic = isPublic
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case imageUrl = "image_url"
        case trackCount = "track_count"
        case uri
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case isPublic = "is_public"
    }

    /// Dual-format factory, ported from `ref_playlist_model.dart`'s `Playlist.fromJson`
    /// (lines 24-62).
    static func fromJson(_ json: [String: Any]) -> Playlist {
        let imageUrl: String?
        if let flatImageUrl = json["image_url"] as? String {
            imageUrl = flatImageUrl
        } else if json["image_url"] != nil {
            // key present but not a String (e.g. explicit null): matches the Dart original's
            // `json['image_url'] as String?`, which yields nil rather than falling through to
            // the API shape.
            imageUrl = nil
        } else if let images = json["images"] as? [[String: Any]], let first = images.first {
            imageUrl = first["url"] as? String
        } else {
            imageUrl = nil
        }

        let trackCount: Int
        if json["track_count"] != nil {
            trackCount = Playlist.intValue(from: json["track_count"]) ?? 0
        } else if let tracks = json["tracks"] as? [String: Any] {
            trackCount = Playlist.intValue(from: tracks["total"]) ?? 0
        } else {
            trackCount = 0
        }

        let owner = json["owner"] as? [String: Any]

        let ownerId: String
        if json["owner_id"] != nil {
            ownerId = json["owner_id"] as? String ?? ""
        } else {
            ownerId = owner?["id"] as? String ?? ""
        }

        let ownerName: String
        if json["owner_name"] != nil {
            ownerName = json["owner_name"] as? String ?? ""
        } else {
            ownerName = owner?["display_name"] as? String ?? ""
        }

        let isPublic: Bool
        if json["is_public"] != nil {
            isPublic = json["is_public"] as? Bool ?? false
        } else {
            isPublic = json["public"] as? Bool ?? false
        }

        return Playlist(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            description: json["description"] as? String,
            imageUrl: imageUrl,
            trackCount: trackCount,
            uri: json["uri"] as? String ?? "",
            ownerId: ownerId,
            ownerName: ownerName,
            isPublic: isPublic
        )
    }

    /// Ported from `ref_playlist_model.dart`'s `Playlist.toJson` (lines 64-76). Always the flat
    /// persisted shape (this is the format `fromJson` reads back on the next app launch).
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "track_count": trackCount,
            "uri": uri,
            "owner_id": ownerId,
            "owner_name": ownerName,
            "is_public": isPublic,
        ]
        json["description"] = description
        json["image_url"] = imageUrl
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
}
