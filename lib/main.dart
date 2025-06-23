import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/spotify_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'services/widget_service.dart';
import 'services/background_service.dart';
import 'services/http_interceptor.dart';
import 'services/update_service.dart';
import 'utils/theme.dart';
import 'utils/auth_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  
  // Initialize widget service
  await WidgetService.initialize();
  
  // Initialize background service
  await BackgroundService.initialize();
  
  // Check for updates on startup if needed
  _checkForUpdatesOnStartup();
  
  runApp(MyApp(prefs: prefs));
}

// Check for updates on app startup if enough time has passed
Future<void> _checkForUpdatesOnStartup() async {
  try {
    // First, auto-enable nightly builds if applicable
    await UpdateService.autoEnableNightlyIfApplicable();
    
    // Check if we should check for updates 
    if (await UpdateService.shouldCheckForUpdates()) {
      // Check for updates in the background
      final updateResult = await UpdateService.checkForUpdates();
      
      // Store the result for later use
      if (updateResult.hasUpdate) {
        // We'll handle the update notification in the app UI later
        print('Update available: ${updateResult.updateInfo?.version}');
      }
    }
  } catch (e) {
    // Ignore errors during startup, we don't want to block app launch
    print('Error checking for updates on startup: $e');
  }
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  
  const MyApp({super.key, required this.prefs});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => AuthProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SpotifyProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Playtivity',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            // Add the update checker wrapper
            builder: (context, child) => _UpdateCheckerWrapper(child: child!),
            home: const AppWrapper(),
            routes: {
              '/login': (context) {
                print('🔗 Navigating to LoginScreen via route');
                return const LoginScreen();
              },
              '/home': (context) {
                print('🔗 Navigating to HomeScreen via route');
                return const HomeScreen();
              },
              '/profile': (context) {
                print('🔗 Navigating to ProfileScreen via route');
                return const ProfileScreen();
              },
              '/settings': (context) {
                print('🔗 Navigating to SettingsScreen via route');
                return const SettingsScreen();
              },
            },
          );
        },
      ),
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {

  @override
  void dispose() {
    // Clear the context when the widget is disposed
    HttpInterceptor.clearContext();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Set the context for HttpInterceptor to handle 401 errors globally
    HttpInterceptor.setContext(context);
    
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Debug logging for troubleshooting
        print('🔍 AppWrapper rebuild - AuthProvider state:');
        print('   - isInitialized: ${authProvider.isInitialized}');
        print('   - isLoading: ${authProvider.isLoading}');
        print('   - isAuthenticated: ${authProvider.isAuthenticated}');
        print('   - currentUser: ${authProvider.currentUser?.displayName ?? 'null'}');
        print('   - bearerToken exists: ${authProvider.bearerToken != null}');
        
        // Only verify authentication state on app resume, not immediately after login
        // This prevents the user from being kicked out right after successful login
        // The verification will happen when the app is resumed from background
        
        // Show loading screen while authentication is being initialized or in progress
        if (!authProvider.isInitialized || authProvider.isLoading) {
          print('📱 Showing loading screen...');
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        // Add explicit check with fallback
        final isAuth = authProvider.isAuthenticated;
        print('📊 Final authentication decision: $isAuth');
        
        if (isAuth) {
          print('📱 Showing MainNavigationScreen...');
          return const MainNavigationScreen();
        } else {
          print('📱 Showing LoginScreen...');
          return const LoginScreen();
        }
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    print('🏠 MainNavigationScreen initialized');
    
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Register background widget updates when user is authenticated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerBackgroundUpdates();
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed, verifying authentication...');
      // Verify authentication when app resumes, but only if we're not in an active login flow
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          
          // Skip verification if user is actively logging in or if auth provider is not initialized
          if (authProvider.isLoading || !authProvider.isInitialized) {
            print('⚠️ Skipping auth verification - login in progress or not initialized');
            return;
          }
          
          // Only verify if we think we should be authenticated
          if (authProvider.isAuthenticated) {
            print('🔄 Verifying existing authentication...');
            final isValid = await authProvider.verifyAndRefreshAuth();
            if (!isValid) {
              print('⚠️ Authentication invalid after app resume - clearing state');
              // Clear the authentication state but don't force logout
              // This allows the user to login again if needed
              await authProvider.resetAuthenticationState();
            } else {
              print('✅ Authentication verified successfully after app resume');
            }
          } else {
            print('ℹ️ No authentication to verify - user not logged in');
          }
        }
      });
    }
  }
  
  Future<void> _registerBackgroundUpdates() async {
    try {
      await BackgroundService.registerWidgetUpdateTask();
      print('✅ Background widget updates registered');
    } catch (e) {
      print('❌ Failed to register background updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🏠 MainNavigationScreen building with tab index: $_currentIndex');
    
    return Consumer<SpotifyProvider>(
      builder: (context, spotifyProvider, child) {
        // Check for authentication errors and handle them
        if (spotifyProvider.hasAuthError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            spotifyProvider.clearAuthError();
            AuthUtils.handleAuthenticationError(
              context, 
              errorMessage: spotifyProvider.authErrorMessage,
            );
          });
        }
        
        return _buildMainScaffold();
      },
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      extendBody: true, // Extend body behind bottom nav bar
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Activities',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Widget wrapper to check for updates and show notifications
class _UpdateCheckerWrapper extends StatefulWidget {
  final Widget child;
  
  const _UpdateCheckerWrapper({
    required this.child,
  });

  @override
  State<_UpdateCheckerWrapper> createState() => _UpdateCheckerWrapperState();
}

class _UpdateCheckerWrapperState extends State<_UpdateCheckerWrapper> {
  UpdateInfo? _updateInfo;
  bool _hasCheckedForUpdates = false;
  
  @override
  void initState() {
    super.initState();
    // Delay the update check to avoid affecting app startup performance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }
  
  Future<void> _checkForUpdates() async {
    try {
      // Only check once per app session
      if (_hasCheckedForUpdates) return;
      _hasCheckedForUpdates = true;
      
      // Check if auto-download is enabled
      final autoDownload = await UpdateService.getAutoDownloadPreference();
      
      // Check for updates
      final updateResult = await UpdateService.checkForUpdates();
      
      // If update available, show banner
      if (updateResult.hasUpdate && updateResult.updateInfo != null) {
        setState(() {
          _updateInfo = updateResult.updateInfo;
        });
        
        // If auto-download is enabled, download immediately
        if (autoDownload && mounted) {
          _handleUpdateDownload();
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
  }
  
  // Handle downloading an update
  Future<void> _handleUpdateDownload() async {
    if (_updateInfo == null || !mounted) return;
    
    // Show download dialog and get the downloaded file path
    final filePath = await UpdateService.showDownloadDialog(
      context,
      _updateInfo!,
    );
    
    if (filePath != null && mounted) {
      // Show installation dialog
      await UpdateService.showInstallDialog(context, filePath);
      
      // Clear update info if user cancels installation
      setState(() {
        _updateInfo = null;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // If no update available, just return the child
    if (_updateInfo == null) {
      return widget.child;
    }
    
    // If update is available, show a notification banner
    return Material(
      child: Column(
        children: [
          // Update notification banner at the top
          Container(
            color: _updateInfo!.isNightly ? Colors.orange.shade700 : Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Icon(
                    _updateInfo!.isNightly ? Icons.science : Icons.system_update,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _updateInfo!.isNightly
                          ? 'New nightly build available: ${_updateInfo!.version}'
                          : 'Update available: ${_updateInfo!.version}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: _handleUpdateDownload,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.2),
                    ),
                    child: const Text('Update'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _updateInfo = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Main app content
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
