# Playtivity Home Screen Widget

This document describes the home screen widget implementation for the Playtivity app, showing your current playing track and friends' Spotify activities.

## Widget Features

- **Size**: 4x2 to 5x3 home screen widget (resizable)
- **Content**: 
  - Your current playing track with album art
  - Up to 3 friends' recent listening activities
  - User name display
  - Modern dark theme with Spotify green accent
- **Updates**: Automatically refreshes every 30 minutes
- **Interaction**: Tapping the widget opens the main app

## Implementation Details

### Flutter/Dart Components

1. **WidgetService** (`lib/services/widget_service.dart`)
   - Handles data synchronization between Flutter app and native widgets
   - Manages SharedPreferences/UserDefaults for cross-platform data sharing
   - Updates widget display data

2. **Integration Points**
   - `SpotifyProvider`: Automatically updates widget when music data changes
   - `AuthProvider`: Provides current user information for the widget
   - `HomeScreen`: Triggers widget updates on data refresh

### Android Implementation

1. **Widget Provider** (`android/app/src/main/kotlin/.../PlaytivityWidgetProvider.kt`)
   - Handles widget updates and user interactions
   - Loads data from SharedPreferences
   - Manages click events to open the main app

2. **Layout** (`android/app/src/main/res/layout/playtivity_widget.xml`)
   - Modern UI with rounded corners and transparency
   - Responsive layout for different widget sizes
   - Dynamic content visibility based on available data

3. **Resources**
   - Colors, drawables, and vector icons
   - Widget configuration and preview image
   - AndroidManifest.xml registration

### iOS Implementation

1. **Widget Extension** (`ios/PlaytivityWidget/`)
   - SwiftUI-based widget implementation
   - Timeline provider for automatic updates
   - Modern iOS widget design patterns

2. **Data Models**
   - CurrentTrack and FriendActivity structures
   - UserDefaults integration for data sharing
   - AsyncImage loading for album artwork

## Setup Instructions

### Prerequisites
- Flutter app with home_widget dependency added
- Android: Widget provider registered in AndroidManifest.xml
- iOS: Widget extension added to Xcode project

### Adding the Widget

#### Android
1. Long press on home screen
2. Select "Widgets"
3. Find "Playtivity Widget"
4. Drag to desired location
5. Resize as needed (4x2 to 5x3)

#### iOS
1. Long press on home screen
2. Tap "+" in top corner
3. Search for "Playtivity"
4. Select medium or large widget size
5. Add to home screen

### Customization

The widget automatically adapts to show:
- Current track if music is playing
- Recent friends' activities
- Fallback content when no data is available

## Development Notes

### Data Flow
1. Flutter app loads Spotify data
2. Data is saved to SharedPreferences (Android) / UserDefaults (iOS)
3. Widget provider reads shared data
4. Widget UI updates automatically

### Update Triggers
- App launch
- Data refresh in main app
- Automatic refresh every 30 minutes
- Manual refresh when widget is interacted with

### Debugging
- Check console logs for "📱 Widget updated successfully" messages
- Verify SharedPreferences keys match between Flutter and native code
- Test widget updates by refreshing data in the main app

## Future Enhancements

- Real-time updates when music changes
- Multiple widget sizes with different layouts
- Customizable widget themes
- Direct playback controls in widget
- Friend-specific activity filtering 