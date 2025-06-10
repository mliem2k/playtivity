import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/spotify_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer2<ThemeProvider, AuthProvider>(
        builder: (context, themeProvider, authProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Appearance Section
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        themeProvider.isDarkMode 
                            ? Icons.dark_mode 
                            : Icons.light_mode,
                      ),
                      title: const Text('Dark Mode'),
                      subtitle: Text(
                        themeProvider.isDarkMode ? 'Enabled' : 'Disabled',
                      ),
                      trailing: Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (value) {
                          themeProvider.toggleTheme();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Account Section
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (authProvider.currentUser != null) ...[
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: const Text('Display Name'),
                        subtitle: Text(authProvider.currentUser!.displayName),
                      ),
                      ListTile(
                        leading: const Icon(Icons.email),
                        title: const Text('Email'),
                        subtitle: Text(authProvider.currentUser!.email),
                      ),
                      ListTile(
                        leading: const Icon(Icons.public),
                        title: const Text('Country'),
                        subtitle: Text(authProvider.currentUser!.country),
                      ),
                    ],
                    ListTile(
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red),
                      ),
                      subtitle: const Text('Sign out from your Spotify account'),
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // About Section
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'About',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),                    ListTile(
                      leading: Image.asset(
                        'assets/images/playtivity_logo_small_icon.png',
                        width: 24,
                        height: 24,
                      ),
                      title: const Text('Playtivity'),
                      subtitle: const Text('Version 0.0.1'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('About'),
                      subtitle: Text('See what your friends are listening to on Spotify'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout from your Spotify account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performLogout(context);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Clear Spotify provider data first
    spotifyProvider.clearData();
    
    // Use the new force logout method that handles both clearing and navigation
    await authProvider.forceLogoutAndNavigate(context);
  }
} 