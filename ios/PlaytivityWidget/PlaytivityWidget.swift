import WidgetKit
import SwiftUI
import Intents

struct PlaytivityWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(16)
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("Playtivity")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(entry.userName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Current track section
                HStack(spacing: 12) {
                    // Album art
                    AsyncImage(url: URL(string: entry.currentTrack.albumArt)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    }
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
                    
                    // Track info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.currentTrack.name.isEmpty ? "No music playing" : entry.currentTrack.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if !entry.currentTrack.artist.isEmpty {
                            Text(entry.currentTrack.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "music.note")
                        .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .font(.system(size: 16))
                }
                .padding(8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
                
                // Friends' activities
                if !entry.friendsActivities.isEmpty {
                    Text("Friends listening")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    VStack(spacing: 3) {
                        ForEach(Array(entry.friendsActivities.prefix(3).enumerated()), id: \.offset) { index, activity in
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                                    .font(.system(size: 12))
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(activity.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Text("\(activity.friendName) • \(activity.artist)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(12)
        }
    }
}

struct PlaytivityWidget: Widget {
    let kind: String = "PlaytivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PlaytivityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Playtivity")
        .description("See what you and your friends are listening to on Spotify.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PlaytivityWidget_Previews: PreviewProvider {
    static var previews: some View {
        PlaytivityWidgetEntryView(entry: SimpleEntry(
            date: Date(),
            currentTrack: CurrentTrack(
                name: "Blinding Lights",
                artist: "The Weeknd",
                albumArt: ""
            ),
            userName: "John",
            friendsActivities: [
                FriendActivity(
                    name: "Bad Habit",
                    artist: "Steve Lacy",
                    friendName: "Alice",
                    albumArt: ""
                ),
                FriendActivity(
                    name: "As It Was",
                    artist: "Harry Styles",
                    friendName: "Bob",
                    albumArt: ""
                )
            ]
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
} 