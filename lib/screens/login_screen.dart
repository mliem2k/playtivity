import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../widgets/spotify_webview_login.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.spotifyBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              
              // Playtivity Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.spotifyGreen.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/playtivity_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // App Title
              const Text(
                'Playtivity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Subtitle
              const Text(
                'See what your friends are listening to',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.spotifyLightGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
              
              const SizedBox(height: 80),
              
              // Login Button
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return ElevatedButton.icon(
                    onPressed: authProvider.isLoading ? null : () => _handleLogin(context),
                    icon: authProvider.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : SizedBox(
                            width: 20,
                            height: 20,
                            child: Image.asset(
                              'assets/images/playtivity_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                    label: Text(
                      authProvider.isLoading ? 'Connecting...' : 'Login with Spotify',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.spotifyGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Info Text
              const Text(
                'You\'ll be redirected to Spotify to authorize this app',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.spotifyLightGray,
                  fontSize: 14,
                ),
              ),
              
              const Spacer(),
              
              // Footer
              const Text(
                'Made with ❤️ for music lovers',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.spotifyLightGray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    authProvider.startLogin();
    
    try {
      // Navigate to WebView login
      final result = await Navigator.of(context).push<bool>(        MaterialPageRoute(
          builder: (context) => SpotifyWebViewLogin(
            onAuthComplete: (oauthCode, spDcCookie) async {
              print('🔄 Login screen received auth completion callback');
              try {
                await authProvider.handleAuthComplete(oauthCode, spDcCookie);
                print('✅ Authentication handling completed successfully');
                
                // Ensure we're back on the login screen before popping
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                print('❌ Error in auth completion: $e');
                if (context.mounted) {
                  // Pop the WebView first
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop(false);
                  }
                  
                  // Show error message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Login failed: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            onCancel: () {
              Navigator.of(context).pop(false);
              authProvider.cancelLogin();
            },
          ),
        ),
      );
      
      // If user cancelled or result is null, stop loading
      if (result != true) {
        authProvider.cancelLogin();
      }
    } catch (e) {
      authProvider.cancelLogin();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
} 