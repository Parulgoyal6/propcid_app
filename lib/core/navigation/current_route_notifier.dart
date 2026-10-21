import 'package:flutter/material.dart';

/// Tracks the name of the topmost route, so widgets placed outside the
/// Navigator's subtree (in `MaterialApp.builder`, alongside `FloatingAiOrb`)
/// can react to which screen is currently on top — e.g. the global compare
/// floating bar hiding itself while the Compare screen is already open.
///
/// A `NavigatorObserver` + `ValueNotifier` rather than a `RouteObserver` +
/// `RouteAware`: the floating bar lives above the Navigator, not inside one
/// of its routes, so there is no `ModalRoute` for it to subscribe from.
class CurrentRouteNotifier extends NavigatorObserver {
  CurrentRouteNotifier._();
  static final CurrentRouteNotifier instance = CurrentRouteNotifier._();

  final ValueNotifier<String?> routeName = ValueNotifier<String?>(null);

  void _update(Route<dynamic>? route) {
    routeName.value = route?.settings.name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
  }
}
