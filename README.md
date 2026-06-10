<div align="center">
  <img src="assets/images/playtivity_logo_large_display.png" alt="Playtivity Logo" width="200"/>
  
  # Playtivity - Spotify Friends Activity App
  
  A Flutter app that shows your friends' Spotify activities in real-time. Built with Flutter and the Spotify Web API.

  <img src="https://img.shields.io/badge/Flutter-3.8+-blue?logo=flutter" alt="Flutter Version"/>
  <img src="https://img.shields.io/badge/Platform-Android-green" alt="Platform Support"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License"/>
</div>

## Features

- **Secure Login**: OAuth authentication through embedded WebView
- **Real Friend Activities**: Automatically extracts `sp_dc` cookie during login for friend activity access
- **Profile Dashboard**: View currently playing, top tracks, and top artists
- **Home Screen Widget**: Android widget showing friend activity and currently playing track
- **Spotify Design**: Authentic Spotify dark theme, branding and colors

## Screenshots

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="screenshots/login.png" alt="Login Screen" width="250"/>
        <br><em>Login Screen</em>
      </td>
      <td align="center">
        <img src="screenshots/home.png" alt="Home Screen" width="250"/>
        <br><em>Home Screen</em>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="screenshots/profile_top_artists.png" alt="Profile Top Artists" width="250"/>
        <br><em>Profile - Top Artists</em>
      </td>
      <td align="center">
        <img src="screenshots/profile_top_songs.png" alt="Profile Top Songs" width="250"/>
        <br><em>Profile - Top Songs</em>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="screenshots/settings.png" alt="Settings Screen" width="250"/>
        <br><em>Settings Screen</em>
      </td>
    </tr>
  </table>
</div>

## How It Works

### Friend Activities
The app uses an innovative approach to show friend activities without requiring your own Spotify API credentials:

1. **Direct Web Authentication**: Uses Spotify's web login flow directly without requiring API registration
2. **Automatic Cookie Extraction**: During the login process, the app automatically extracts the `sp_dc` cookie from the WebView
3. **Internal API Access**: Uses the extracted cookie to generate access tokens for Spotify's internal buddy list API
4. **Real-time Data**: Accesses the same endpoints used by Spotify's web player for friend activities

### Technical Implementation
- **TOTP Generation**: Implements the same TOTP algorithm used by Spotify's internal systems
- **Token Generation**: Automatically generates access tokens using the `sp_dc` cookie and TOTP
- **API Integration**: Calls the same endpoints used by Spotify's web player for friend activities

## Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd playtivity
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   flutter run
   ```

## Development Scripts

The `scripts/` folder contains utility scripts for development:

### Icon & Image Generator
Automatically generates all required app icons and images from a single source image:

```bash
# Install Python dependencies
cd scripts
pip install -r requirements.txt

# Generate icons from your image (run from project root)
python scripts/convert_icon.py your_logo.svg
python scripts/convert_icon.py your_logo.png
```

**What it creates:**
- Android Icons: All mipmap densities (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- Flutter Images: Login screen logos, button icons, display images
- Multiple Sizes: 24x24 to 200x200 pixels for different use cases

See `scripts/README.md` for detailed usage instructions.

## Dependencies

- `provider` - State management
- `http` - API requests
- `shared_preferences` - Local storage
- `flutter_inappwebview` - Embedded OAuth login via WebView
- `cached_network_image` - Image caching
- `timeago` - Time formatting
- `url_launcher` - Deep-link into the Spotify app
- `crypto` - HMAC-SHA1 for TOTP generation
- `home_widget` - Home screen widget support
- `workmanager` - Background widget refresh
- `logger` - Structured logging
- `package_info_plus` - App version info

## Architecture

- **Providers**: State management for authentication and Spotify data
- **Services**: API integration for Spotify Web API and buddy list
- **Models**: Data structures for User, Track, and Activity
- **Screens**: Login, Home (activities), Profile, and Settings
- **Widgets**: Reusable components for activities and tracks

## Current Status

- OAuth authentication with automatic cookie extraction
- Real friend activities via unofficial API
- Profile data (currently playing, top tracks/artists)
- Home screen widget with background refresh
- 341 automated tests passing

## Platform Support

**Android**: Fully tested on Android 15.

**iOS**: Not yet supported. iOS support is planned for a future release. The app is built with Flutter and the majority of the code is cross-platform, but iOS-specific integration has not been implemented or tested. Contributions are welcome.

## Testing

- **Android**: Fully tested on Android 15
- **iOS**: Not yet tested - community contributions welcome

## Roadmap

- [x] Complete API-free implementation - Remove all dependencies on Spotify API client/secret
- [x] Home screen widgets - Android widgets showing friend activity and currently playing
- [ ] iOS support - Implement and test iOS-specific integration

**Want to contribute?** Check out our [Contributing](#contributing) section below.

## Contributing

We welcome contributions from the community! Here's how you can help:

### Bug Reports
- **Found a bug?** Please [open an issue](../../issues) with:
  - Clear description of the problem
  - Steps to reproduce
  - Expected vs actual behavior
  - Screenshots if applicable
  - Device/OS information

### Pull Requests
- **Pull requests are welcome!** Please:
  - Fork the repository
  - Create a feature branch (`git checkout -b feature/amazing-feature`)
  - Make your changes
  - Test thoroughly
  - Commit with clear messages
  - Push to your branch
  - Open a pull request with detailed description

### Forks
- **Forks are encouraged!** Feel free to:
  - Fork this project for your own use
  - Customize it for your needs
  - Share your improvements back with the community
  - Create your own variations

### Feature Requests
- Have an idea? [Open an issue](../../issues) with the `enhancement` label
- Describe your use case and proposed solution

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

**TL;DR**: You can do whatever you want with this code - use it, modify it, distribute it, even commercially. Just keep the copyright notice.

### Third-Party Notices
- Spotify is a trademark of Spotify AB
- This project is not affiliated with or endorsed by Spotify
- Built for educational and personal use

---

Made with ❤️ for music lovers
