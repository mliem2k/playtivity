import Foundation

/// Pure-Swift port of lib/models/user.dart. Persisted to `UserDefaults` as JSON under the
/// `spotify_user` key with snake_case keys (`display_name`, `image_url`) so data written by an
/// older build of this app (storage keys are kept identical on purpose for upgrade continuity)
/// still round-trips correctly.
struct User: Codable, Equatable {
    let id: String
    let displayName: String
    let email: String
    let imageUrl: String?
    let followers: Int
    let country: String

    init(id: String, displayName: String, email: String, imageUrl: String?, followers: Int, country: String) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.imageUrl = imageUrl
        self.followers = followers
        self.country = country
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case imageUrl = "image_url"
        case followers
        case country
    }

    // Defensive decode (missing/null/wrong-typed fields default rather than throw), mirroring the
    // Dart original's `JsonHelpers.getString`/`getInt` forgiving-default behavior. This matters
    // because `spotify_user` may hold data written by an older app build.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        displayName = (try? container.decode(String.self, forKey: .displayName)) ?? ""
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
        imageUrl = try? container.decodeIfPresent(String.self, forKey: .imageUrl)
        followers = (try? container.decode(Int.self, forKey: .followers)) ?? 0
        country = (try? container.decode(String.self, forKey: .country)) ?? ""
    }
}
