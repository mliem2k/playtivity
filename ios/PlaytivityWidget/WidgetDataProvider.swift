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
                    albumArt: ""
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
        
        // Get friends' activities
        var friendsActivities: [FriendActivity] = []
        for i in 0..<3 {
            let friendTrack = userDefaults?.string(forKey: "friend_\(i)_track") ?? ""
            let friendArtist = userDefaults?.string(forKey: "friend_\(i)_artist") ?? ""
            let friendName = userDefaults?.string(forKey: "friend_\(i)_name") ?? ""
            let friendAlbumArt = userDefaults?.string(forKey: "friend_\(i)_album_art") ?? ""
            
            if !friendTrack.isEmpty {
                friendsActivities.append(FriendActivity(
                    name: friendTrack,
                    artist: friendArtist,
                    friendName: friendName,
                    albumArt: friendAlbumArt
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