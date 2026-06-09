import 'package:flutter/material.dart';

/// App-wide navigator key. Set on [MaterialApp.navigatorKey] so that any
/// layer of the app (including HTTP interceptors) can access the current
/// navigator and context without storing a BuildContext in a singleton.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
