# Home Widget Integration with Jetpack Glance

This directory contains the Android widget implementation using the `home_widget` Flutter plugin with Jetpack Glance.

## Files Overview

### Core Widget Implementation
- `PlaytivityWidgetProvider.kt` - Main widget implementation using Glance composables
- `RefreshWidgetCallback.kt` - Action callback for refresh functionality

### Home Widget Library Integration
- `HomeWidgetGlanceState.kt` - State class from home_widget library
- `HomeWidgetGlanceStateDefinition.kt` - State definition from home_widget library

### Example Implementation
- `CounterWidgetExample.kt` - Simple counter example following the home_widget pattern

## Usage from Flutter

### Updating Widget Data
```dart
// Save data to widget
await HomeWidget.saveWidgetData('activities_count', 3);
await HomeWidget.saveWidgetData('friend_0_name', 'John');
await HomeWidget.saveWidgetData('friend_0_track', 'Song Title');
await HomeWidget.saveWidgetData('friend_0_artist', 'Artist Name');

// Update the widget
await HomeWidget.updateWidget(
  androidName: 'PlaytivityWidgetReceiver',
);
```

### Interactive Callbacks
```dart
// Register callback for interactive features
await HomeWidget.registerInteractivityCallback(backgroundCallback);

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  // Handle widget interactions
  print('Widget interacted: ${uri?.host}');
}
```

## Key Features

✅ **Jetpack Glance UI** - Modern Compose-like declarative UI  
✅ **Material Design 3** - Dynamic theming support  
✅ **Home Widget Integration** - Flutter-to-Android data sync  
✅ **Interactive Callbacks** - Handle widget interactions  
✅ **Automatic Updates** - Seamless data updates from Flutter  

## Configuration

The widget is configured in:
- `android/app/src/main/res/xml/playtivity_widget_glance.xml`
- `android/app/src/main/AndroidManifest.xml`

## Dependencies

- `androidx.glance:glance-appwidget:1.1.1`
- `androidx.glance:glance-material3:1.1.1`
- `home_widget: ^0.6.0` (Flutter dependency) 