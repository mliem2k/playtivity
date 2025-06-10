import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../widgets/spotify_webview_login.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
                      color: theme.primaryColor.withOpacity(0.25),
                      blurRadius: 15,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
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
              Text(
                'Playtivity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onBackground,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              
              const SizedBox(height: 16),              // Subtitle
              Text(
                'See what your friends are listening to',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getSecondaryTextColor(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
              
              const SizedBox(height: 80),
              
              // Login Button
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return ElevatedButton.icon(
                    onPressed: authProvider.isLoading ? null : () => _handleLogin(context),                    icon: authProvider.isLoading
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
                        color: Colors.white,
                      ),
                    ),                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: isDark ? 0 : 3,
                      shadowColor: isDark ? Colors.transparent : theme.primaryColor.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),              // Info Text
              Text(
                'You\'ll be redirected to Spotify to authorize this app',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getSecondaryTextColor(context),
                  fontSize: 14,
                ),
              ),
              
              const Spacer(),              // Footer
              Text(
                'Made with ❤️ for music lovers',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.getTertiaryTextColor(context),
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
            onAuthComplete: (bearerToken, headers) async {
              print('🔄 Login screen received auth completion callback');
              try {
                await authProvider.handleAuthComplete(bearerToken, headers);
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