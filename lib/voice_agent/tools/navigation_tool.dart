import '../models/tool_result.dart';
import '../rag/route_index.dart';
import 'registry.dart';

void registerNavigationTool() {
  toolRegistry.register(
    ToolDefinition(
      name: 'navigate',
      description:
          'Navigate to any route. Accepts an exact path or natural-language destination.',
      execute: (params, ctx) async {
        final raw = (params['route'] as String?) ?? '/';
        final resolved = resolveRoute(raw, ctx.userRole, ctx.userType);
        ctx.navigate(resolved);
        return ToolResult.ok(userMessage: 'Navigated to $resolved');
      },
    ),
  );
}

// ─── Route resolution (5-step pipeline) ──────────────────────────────────────

/// Resolves a raw route string or natural-language destination to a Flutter route.
String resolveRoute(String raw, String? userRole, String? userType) {
  final lower = raw.trim().toLowerCase();
  if (lower.isEmpty) return '/';

  // Step 1: Role-aware virtual aliases
  final alias = _resolveVirtualAlias(lower, userRole, userType);
  if (alias.isNotEmpty) return alias;

  // Step 2: Exact path match in known paths
  final exact = _knownPaths[lower] ?? _knownPaths[raw];
  if (exact != null) return exact;

  // Step 3: Dynamic path families — pass through as-is
  if (_isDynamicPath(raw)) return raw;

  // Step 4: Concept fuzzy match via route index
  final tier = roleToTier(
    userRole,
    true,
  ); // navigation tool only runs when logged in or guest
  final entry = resolveConcept(lower, tier);
  if (entry != null) return entry.path;

  // Step 5: Fallback
  return '/';
}

// Step 1 — virtual aliases
String _resolveVirtualAlias(String lower, String? userRole, String? userType) {
  if (lower == 'dashboard' ||
      lower == 'my dashboard' ||
      lower == 'mera dashboard' ||
      lower == 'profile dashboard' ||
      lower == 'manage dashboard' ||
      lower == 'work dashboard' ||
      lower == 'management dashboard') {
    // AppConstants.manageDashboardScreen — ManageDashboardDispatcher resolves
    // this to the correct role screen itself (builder/broker/influencer/
    // individual/team_member), so route there directly instead of
    // duplicating (and, for 'individual', dropping) that switch here. Was a
    // hardcoded builder/broker/influencer-only map that fell back to
    // '/profile' for every other account type.
    return '/manage-dashboard';
  }

  if (lower == 'home' || lower == 'homepage' || lower == 'ghar') {
    return '/';
  }

  if (lower == 'login' || lower == 'sign in' || lower == 'signin') {
    return '/auth';
  }

  if (lower == 'settings' ||
      lower == 'open settings' ||
      lower == 'account settings' ||
      lower == 'settings kholo') {
    // Settings has no route of its own — it's a modal bottom sheet
    // (showSettingsSheet in screens/profile/actions/settings_sheet.dart) that
    // needs a BuildContext, and ToolContext.navigate only supports
    // pushNamed(route). Land on Profile, where the real Settings entry point
    // lives, rather than falling through to Home.
    return '/profile';
  }

  // Phase 2: admin aliases go here.

  return '';
}

// Step 2 — known paths map
const Map<String, String> _knownPaths = {
  '/': '/',
  '/search': '/search',
  '/search-results': '/search-results',
  '/shortlist': '/shortlist',
  '/profile': '/profile',
  '/visits': '/visits',
  '/notifications': '/notifications',
  '/reels': '/reels',
  '/post-property': '/post-property',
  // The builder project wizard. Both wizards are role-gated at the route
  // (PostPropertyRouteGate / AddProjectRouteGate), so listing either here is
  // safe whatever the speaker's role — the gate sends them to the right one.
  '/add-project': '/add-project',
  '/influencer-video': '/influencer-video',
  '/filters': '/filters',
  '/auth': '/auth',
  '/emi-calculator': '/emi-calculator',
  '/compare-properties': '/compare-properties',
  '/dashboard/broker': '/dashboard/broker',
  '/dashboard/builder': '/dashboard/builder',
  '/dashboard/influencer': '/dashboard/influencer',
  // Added — already registered in app.dart via AppConstants, but missing here.
  '/feed': '/feed',
  '/messages': '/messages',
  '/manage-dashboard': '/manage-dashboard',
  '/network': '/network',
  '/network/memberships': '/network/memberships',
  '/network/leads': '/network/leads',
};

// Step 3 — dynamic path families
bool _isDynamicPath(String raw) {
  return raw.startsWith('/property-detail') ||
      raw.startsWith('/gallery-viewer') ||
      raw.startsWith('/explore_');
}
