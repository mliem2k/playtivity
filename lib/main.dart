import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:ui';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/spotify_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'services/spotify_service.dart';
import 'utils/theme.dart';
import 'utils/auth_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
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
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Debug logging for troubleshooting
        print('🔍 AppWrapper rebuild - AuthProvider state:');
        print('   - isInitialized: ${authProvider.isInitialized}');
        print('   - isLoading: ${authProvider.isLoading}');
        print('   - isAuthenticated: ${authProvider.isAuthenticated}');
        print('   - currentUser: ${authProvider.currentUser?.displayName ?? 'null'}');
        print('   - bearerToken exists: ${authProvider.bearerToken != null}');
        
        // Show loading screen while authentication is being initialized or in progress
        if (!authProvider.isInitialized || authProvider.isLoading) {
          print('📱 Showing loading screen...');
          return const Scaffold(
            body: Center(
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

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    print('🏠 MainNavigationScreen initialized');
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
