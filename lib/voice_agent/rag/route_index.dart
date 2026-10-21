// Route index — Phase 1 end-user routes only.
// Phase 3: knowledge_service.dart, memory_service.dart,
//          conversation_history_service.dart go in this same rag/ directory.

class RouteEntry {
  final String path;
  final String title;
  final String tier; // 'public' | 'authenticated' | 'admin' | 'super_admin'
  final String section;
  final String description;
  final List<String> concepts;
  final List<String> keywords;

  const RouteEntry({
    required this.path,
    required this.title,
    required this.tier,
    required this.section,
    required this.description,
    required this.concepts,
    required this.keywords,
  });
}

// ─── Phase 1 route catalogue ──────────────────────────────────────────────────

const List<RouteEntry> _routes = [
  // Public routes
  RouteEntry(
    path: '/',
    title: 'Home',
    tier: 'public',
    section: 'main',
    description: 'Home screen with featured properties and categories',
    concepts: ['home', 'homepage', 'main', 'start'],
    keywords: ['home', 'main', 'start', 'ghar'],
  ),
  RouteEntry(
    path: '/search',
    title: 'Search',
    tier: 'public',
    section: 'discovery',
    description: 'Search and discover properties',
    concepts: ['search', 'find property', 'properties', 'property search'],
    keywords: ['search', 'find', 'property', 'properties', 'dhundho', 'khojo'],
  ),
  RouteEntry(
    path: '/shortlist',
    title: 'Shortlist',
    tier: 'public',
    section: 'discovery',
    description: 'Saved and bookmarked properties',
    concepts: [
      'shortlist',
      'saved',
      'bookmarks',
      'liked',
      'favourites',
      'favorites',
    ],
    keywords: ['shortlist', 'saved', 'bookmark', 'liked', 'wishlist', 'pasand'],
  ),
  RouteEntry(
    path: '/reels',
    title: 'Property Reels',
    tier: 'public',
    section: 'discovery',
    description: 'Short property video reels',
    concepts: [
      'reels',
      'videos',
      'property videos',
      'property reels',
      'influencer',
    ],
    keywords: ['reels', 'video', 'shorts', 'reel'],
  ),
  RouteEntry(
    path: '/emi-calculator',
    title: 'EMI Calculator',
    tier: 'public',
    section: 'tools',
    description: 'Calculate home loan EMI',
    concepts: [
      'emi calculator',
      'loan calculator',
      'emi',
      'home loan',
      'mortgage',
    ],
    keywords: ['emi', 'loan', 'calculator', 'mortgage', 'interest'],
  ),
  RouteEntry(
    path: '/compare-properties',
    title: 'Compare Properties',
    tier: 'public',
    section: 'tools',
    description: 'Compare multiple properties side by side',
    concepts: ['compare', 'comparison', 'compare properties', 'tulna'],
    keywords: ['compare', 'comparison', 'versus', 'vs', 'tulna'],
  ),
  RouteEntry(
    path: '/auth',
    title: 'Sign In / Sign Up',
    tier: 'public',
    section: 'auth',
    description: 'Authentication — sign in or create an account',
    concepts: ['sign in', 'login', 'sign up', 'register', 'auth', 'account'],
    keywords: ['login', 'signin', 'signup', 'register', 'auth', 'account'],
  ),

  // Authenticated routes
  RouteEntry(
    path: '/profile',
    title: 'Profile',
    tier: 'authenticated',
    section: 'account',
    // "dashboard" / "my dashboard" concepts deliberately removed — that
    // concept now belongs to '/manage-dashboard' (ManageDashboardDispatcher)
    // below. Leaving both entries claim "dashboard" would tie the fuzzy
    // matcher and silently fall back to whichever entry happens to be
    // earlier in this list.
    //
    // "articles" / "my articles" added: there is no dedicated Articles hub
    // screen in this app yet — a user's own articles are shown inside the
    // Profile screen's "My Content" section (see profile_screen.dart), so
    // that is the closest existing destination for an "open articles" command.
    description: 'User profile — includes "My Content" (listings, articles, videos)',
    concepts: ['profile', 'my profile', 'account', 'articles', 'my articles'],
    keywords: ['profile', 'account', 'mera', 'my', 'article', 'blog'],
  ),
  RouteEntry(
    path: '/post-property',
    title: 'Post Property',
    tier: 'authenticated',
    section: 'listings',
    description: 'Create a new property listing',
    // "list a property" / "i want to list a property" added: without a
    // concept containing the exact phrase "list a property", this route tied
    // with /shortlist at the same keyword score (both keyword sets contain a
    // substring of "list" — "listing" here, "wishlist"/"shortlist" there) and
    // the fuzzy matcher's first-entry-wins tiebreak sent "I want to list a
    // property" to /shortlist instead of the actual listing form.
    concepts: [
      'post property',
      'create listing',
      'add property',
      'new listing',
      'list property',
      'list a property',
      'list my property',
      'listing form',
    ],
    keywords: [
      'post',
      'create',
      'add',
      'new',
      'listing',
      'property',
      'sell',
      'rent',
    ],
  ),
  // The builder project wizard. Without this entry the voice agent could not
  // reach it by intent at all, so "create a project" had no correct destination.
  //
  // `tier` is deliberately 'authenticated', not 'builder'. `_canAccess` compares
  // positions in the ladder ['public','authenticated','admin','super_admin'], so
  // an unrecognised value gives `indexOf == -1` and `userIdx >= -1` is always
  // true — a 'builder' tier would make this entry reachable by **logged-out**
  // users, the exact opposite of gating. The role check therefore lives where it
  // can actually be enforced: AddProjectRouteGate on the route itself.
  RouteEntry(
    path: '/add-project',
    title: 'Add Project',
    tier: 'authenticated',
    section: 'listings',
    description: 'Create a new builder project',
    concepts: [
      'add project',
      'create project',
      'new project',
      'post project',
      'list project',
    ],
    keywords: [
      'project',
      'add',
      'create',
      'new',
      'launch',
      'township',
      'builder',
    ],
  ),
  // The influencer video form. Reachable by intent for the same reason
  // '/add-project' is: post_content(video) now resolves here, and without an entry
  // "upload a video" had no destination the agent could name.
  //
  // `tier` is 'authenticated' for the same reason, too — `_canAccess` compares
  // positions in the ladder ['public','authenticated','admin','super_admin'], so an
  // unrecognised 'influencer' tier would yield indexOf == -1 and make this entry
  // reachable by logged-out users. The role check lives on the route instead, in
  // InfluencerVideoRouteGate.
  RouteEntry(
    path: '/influencer-video',
    title: 'Upload Video',
    tier: 'authenticated',
    section: 'listings',
    description: 'Create a new influencer video',
    concepts: [
      'upload video',
      'create video',
      'post video',
      'new video',
      'post reel',
    ],
    keywords: [
      'video',
      'upload',
      'create',
      'post',
      'reel',
      'influencer',
      'content',
    ],
  ),
  RouteEntry(
    path: '/notifications',
    title: 'Notifications',
    tier: 'authenticated',
    section: 'account',
    description: 'Notifications and alerts',
    concepts: ['notifications', 'alerts', 'updates'],
    keywords: ['notification', 'alert', 'update', 'suchna'],
  ),
  // Added — the app already has a dedicated Feed screen (FeedScreen at
  // AppConstants.feedScreen), but the voice agent's route index never
  // learned about it, so "open my feed" fell through to Home.
  RouteEntry(
    path: '/feed',
    title: 'Feed',
    tier: 'authenticated',
    section: 'social',
    description:
        'Your social feed — properties, projects and videos merged',
    concepts: ['feed', 'my feed', 'social feed', 'home feed', 'timeline'],
    keywords: ['feed', 'timeline', 'posts', 'updates', 'social'],
  ),
  // Added — MessagesListScreen at AppConstants.messagesScreen already exists
  // and is registered in app.dart, but had no route-index entry, so
  // "messages" natural-language queries fell through to /notifications (the
  // notifications entry's now-removed "message" keyword collided with it).
  RouteEntry(
    path: '/messages',
    title: 'Messages',
    tier: 'authenticated',
    section: 'account',
    description: 'Direct messages and conversations',
    concepts: ['messages', 'chat', 'my messages', 'inbox', 'conversations'],
    keywords: ['message', 'chat', 'inbox', 'conversation', 'dm', 'baat'],
  ),
  RouteEntry(
    path: '/visits',
    title: 'My Visits',
    tier: 'authenticated',
    section: 'bookings',
    description: 'Property visit bookings',
    concepts: [
      'visits',
      'my visits',
      'visit bookings',
      'appointments',
      'schedule',
    ],
    keywords: ['visit', 'booking', 'appointment', 'schedule', 'site visit'],
  ),
  RouteEntry(
    path: '/search-results',
    title: 'Search Results',
    tier: 'public',
    section: 'discovery',
    description: 'Property search results',
    concepts: ['search results', 'results', 'listings', 'properties list'],
    keywords: ['results', 'listings', 'properties'],
  ),
  RouteEntry(
    path: '/filters',
    title: 'Filters',
    tier: 'public',
    section: 'discovery',
    description: 'Search filters',
    concepts: ['filters', 'filter', 'search filters', 'refine'],
    keywords: ['filter', 'refine', 'narrow', 'sort'],
  ),

  // Dashboard routes
  RouteEntry(
    path: '/dashboard/broker',
    title: 'Broker Dashboard',
    tier: 'authenticated',
    section: 'dashboard',
    description: 'Broker management dashboard',
    concepts: ['broker dashboard', 'manage broker', 'broker panel'],
    keywords: ['broker', 'dashboard', 'manage', 'leads'],
  ),
  RouteEntry(
    path: '/dashboard/builder',
    title: 'Builder Dashboard',
    tier: 'authenticated',
    section: 'dashboard',
    description: 'Builder management dashboard',
    concepts: [
      'builder dashboard',
      'manage builder',
      'builder panel',
      'projects',
    ],
    keywords: ['builder', 'dashboard', 'manage', 'projects'],
  ),
  RouteEntry(
    path: '/dashboard/influencer',
    title: 'Influencer Dashboard',
    tier: 'authenticated',
    section: 'dashboard',
    description: 'Influencer management dashboard',
    concepts: [
      'influencer dashboard',
      'manage influencer',
      'content dashboard',
    ],
    keywords: ['influencer', 'dashboard', 'content', 'reel', 'video'],
  ),

  // ── Added — Phase 9 / dashboard-redesign routes that already exist in
  // app_constants.dart + app.dart but were never taught to the voice agent ──
  RouteEntry(
    path: '/manage-dashboard',
    title: 'My Dashboard',
    tier: 'authenticated',
    section: 'dashboard',
    // ManageDashboardDispatcher — resolves to the caller's own role dashboard
    // (builder/broker/influencer/individual/team_member) in one place. Most
    // of those dashboards default-open on their Analytics tab (Broker,
    // Individual, Influencer all do; Builder opens on Overview), so this
    // also doubles as the best available destination for a bare "analytics"
    // request — mirroring the portal's own fallback, where a non-admin's
    // "analytics"/"reports" concept resolves to their generic dashboard too.
    description:
        'Your dashboard — resolves to the correct dashboard for your account type',
    concepts: [
      'dashboard',
      'my dashboard',
      'manage dashboard',
      'work dashboard',
      'management dashboard',
      'analytics',
      'reports',
    ],
    keywords: ['dashboard', 'manage', 'analytics', 'reports', 'overview'],
  ),
  RouteEntry(
    path: '/network/memberships',
    title: 'My Networks',
    tier: 'authenticated',
    section: 'network',
    description: 'View and manage your network connections and memberships',
    concepts: [
      'my network',
      'my networks',
      'my connections',
      'network memberships',
      'connections',
    ],
    keywords: ['network', 'connections', 'memberships', 'members'],
  ),
  RouteEntry(
    path: '/network',
    title: 'Network Hub',
    tier: 'authenticated',
    section: 'network',
    description: 'Network hub — memberships, leads and referrals',
    concepts: ['network', 'network hub', 'networks'],
    keywords: ['network', 'hub', 'referrals'],
  ),
  // "CRM Leads" — this app has no admin-tier CRM console yet; the closest
  // standalone, always-reachable leads pipeline (assign/track leads with
  // status) is Network ▸ My Leads. (A role-scoped "Leads" tab also exists
  // inside the Broker/Builder dashboards, but it isn't independently
  // routable — see the voice agent report for details.)
  RouteEntry(
    path: '/network/leads',
    title: 'My Leads',
    tier: 'authenticated',
    section: 'network',
    description: 'Distribute and track leads shared through your network',
    concepts: [
      'crm',
      'crm leads',
      'leads',
      'my leads',
      'lead pipeline',
      'enquiries',
    ],
    keywords: ['crm', 'leads', 'enquiries', 'pipeline'],
  ),
];

// ─── Tier resolution ──────────────────────────────────────────────────────────

const _adminRoles = {
  'admin',
  'crm_manager',
  'crm_agent',
  'seo_manager',
  'content_editor',
  'finance_manager',
  'support_agent',
};

String roleToTier(String? role, bool isAuthenticated) {
  if (role == 'super_admin') return 'super_admin';
  if (role != null && _adminRoles.contains(role)) return 'admin';
  return isAuthenticated ? 'authenticated' : 'public';
}

bool _canAccess(String routeTier, String userTier) {
  const order = ['public', 'authenticated', 'admin', 'super_admin'];
  final routeIdx = order.indexOf(routeTier);
  final userIdx = order.indexOf(userTier);
  return userIdx >= routeIdx;
}

// ─── Concept resolver ─────────────────────────────────────────────────────────

/// Fuzzy-match [concept] against the route catalogue.
/// Returns the best-matching [RouteEntry] the user's tier can access, or null.
RouteEntry? resolveConcept(String concept, String userTier) {
  final lower = concept.trim().toLowerCase();
  RouteEntry? best;
  int bestScore = 0;

  for (final route in _routes) {
    if (!_canAccess(route.tier, userTier)) continue;

    int score = 0;

    // Exact concept match
    for (final c in route.concepts) {
      if (c.toLowerCase() == lower) {
        score += 5;
      } else if (c.toLowerCase().contains(lower) ||
          lower.contains(c.toLowerCase())) {
        score += 2;
      }
    }

    // Keyword partial match
    for (final k in route.keywords) {
      final words = lower.split(RegExp(r'\s+'));
      for (final w in words) {
        if (k.toLowerCase().contains(w) && w.length > 2) {
          score += 1;
        }
      }
    }

    if (score > bestScore) {
      bestScore = score;
      best = route;
    }
  }

  return bestScore > 0 ? best : null;
}

/// Exact path lookup.
RouteEntry? findByPath(String path) {
  try {
    return _routes.firstWhere((r) => r.path == path);
  } catch (_) {
    return null;
  }
}
