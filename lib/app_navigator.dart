import 'package:flutter/material.dart';

/// Global navigator key — registered on [MaterialApp] so that code outside
/// the Navigator's subtree (e.g. widgets placed in MaterialApp.builder) can
/// push routes and show modals without holding a stale [BuildContext].
///
/// Usage:
///   - Pass to MaterialApp: `navigatorKey: appNavigatorKey`
///   - Push a route:        `appNavigatorKey.currentState?.pushNamed('/path')`
///   - Show a modal:        `showModalBottomSheet(context: appNavigatorKey.currentState!.overlay!.context, ...)`
///
/// Why overlay?.context and not currentContext?
///   currentContext IS the Navigator widget's own context. Navigator.of(currentContext)
///   would look for a Navigator ABOVE it — none exists at the root level, so it throws.
///   overlay.context is the Overlay widget built INSIDE the Navigator, so walking up
///   its ancestor chain reaches the Navigator itself.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
