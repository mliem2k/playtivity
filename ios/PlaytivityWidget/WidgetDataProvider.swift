import WidgetKit
import SwiftUI

struct CurrentTrack {
    let name: String
    let artist: String
    let albumArt: String
}

struct FriendActivity {
    let name: String
    let artist: String
    let friendName: String
    let albumArt: String
    let timestamp: Int64
    let isCurrentlyPlaying: Bool
    let activityType: String
    let userId: String
    
    func getStatusText() -> String {
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000) // Current time in milliseconds
        let timestampDate = timestamp > 0 ? timestamp : currentTime
        let timeDiffMinutes = (currentTime - timestampDate) / (1000 * 60)
        
        // Consider recent if within 1 minute (like Flutter app)
        let isRecent = timeDiffMinutes < 1
        
        if isCurrentlyPlaying || isRecent {
            if activityType == "playlist" {
                return "Listening to playlist now"
            } else {
                return "Listening now"
            }
        } else {
            let timeAgoText = formatTimeAgo(minutes: timeDiffMinutes)
            if activityType == "playlist" {
                return "Played playlist \(timeAgoText)"
            } else {
                return "Played \(timeAgoText)"
            }
        }
    }
    
    func isRecentOrPlaying() -> Bool {
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        let timestampDate = timestamp > 0 ? timestamp : currentTime
        let timeDiffMinutes = (currentTime - timestampDate) / (1000 * 60)
        return isCurrentlyPlaying || timeDiffMinutes < 1
    }
    
    private func formatTimeAgo(minutes: Int64) -> String {
        switch minutes {
        case 0..<1:
            return "just now"
        case 1..<60:
            return "\(minutes)m ago"
        case 60..<1440:
            return "\(minutes / 60)h ago"
        default:
            return "\(minutes / 1440)d ago"
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let currentTrack: CurrentTrack
    let userName: String
    let friendsActivities: [FriendActivity]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            currentTrack: CurrentTrack(
                name: "Sample Track",
                artist: "Sample Artist",
                albumArt: ""
            ),
            userName: "User",
            friendsActivities: [
                FriendActivity(
                    name: "Friend Track",
                    artist: "Artist",
                    friendName: "Friend",
                    albumArt: "",
                    timestamp: 0,
                    isCurrentlyPlaying: false,
                    activityType: "track"
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let entry = createEntry()
        
        // Refresh every 30 minutes
        let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
        
        completion(timeline)
    }
    
    private func createEntry() -> SimpleEntry {
        // Get data from UserDefaults shared with Flutter app
        let userDefaults = UserDefaults(suiteName: "group.com.mliem.playtivity")
        
        let currentTrackName = userDefaults?.string(forKey: "current_track_name") ?? ""
        let currentArtistName = userDefaults?.string(forKey: "current_artist_name") ?? ""
        let currentAlbumArt = userDefaults?.string(forKey: "current_album_art") ?? ""
        let userName = userDefaults?.string(forKey: "user_name") ?? "User"
        
        let currentTrack = CurrentTrack(
            name: currentTrackName,
            artist: currentArtistName,
            albumArt: currentAlbumArt
        )
        
        // Get friends' activities - check activities_count first
        var friendsActivities: [FriendActivity] = []
        let activitiesCount = userDefaults?.string(forKey: "activities_count") ?? "0"
        let count = Int(activitiesCount) ?? 0
        
        // Read all available friends (up to 10 for iOS widget)
        let maxFriends = min(count, 10)
        for i in 0..<maxFriends {
            let friendTrack = userDefaults?.string(forKey: "friend_\(i)_track") ?? ""
            let friendArtist = userDefaults?.string(forKey: "friend_\(i)_artist") ?? ""
            let friendName = userDefaults?.string(forKey: "friend_\(i)_name") ?? ""
            let friendAlbumArt = userDefaults?.string(forKey: "friend_\(i)_album_art") ?? ""
            let timestampString = userDefaults?.string(forKey: "friend_\(i)_timestamp") ?? "0"
            let isCurrentlyPlayingString = userDefaults?.string(forKey: "friend_\(i)_is_currently_playing") ?? "false"
            let activityType = userDefaults?.string(forKey: "friend_\(i)_activity_type") ?? "track"
            let userId = userDefaults?.string(forKey: "friend_\(i)_user_id") ?? ""
            
            let timestamp = Int64(timestampString) ?? 0
            let isCurrentlyPlaying = Bool(isCurrentlyPlayingString) ?? false
            
            if !friendTrack.isEmpty {
                friendsActivities.append(FriendActivity(
                    name: friendTrack,
                    artist: friendArtist,
                    friendName: friendName,
                    albumArt: friendAlbumArt,
                    timestamp: timestamp,
                    isCurrentlyPlaying: isCurrentlyPlaying,
                    activityType: activityType,
                    userId: userId
                ))
            }
        }
        
        return SimpleEntry(
            date: Date(),
            currentTrack: currentTrack,
            userName: userName,
            friendsActivities: friendsActivities
        )
    }
} 