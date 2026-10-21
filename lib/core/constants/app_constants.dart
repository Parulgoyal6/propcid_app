class AppConstants {
  AppConstants._();

  // Border Radius
  static const double cardRadius = 16.0;
  static const double chipRadius = 8.0;
  static const double buttonRadius = 12.0;
  static const double searchBarRadius = 14.0;
  static const double imageThumbnailRadius = 12.0;

  // Heights
  static const double bottomNavHeight = 64.0;
  static const double searchBarHeight = 54.0;
  static const double heroBannerHeight = 180.0;
  static const double categoryIconSize = 52.0;
  static const double propertyCardWidth = 220.0;
  static const double propertyCardImageHeight = 140.0;
  static const double propertyCardHeight = 280.0;
  static const double filterChipHeight = 36.0;
  static const double propertyListItemImageSize = 160.0;
  static const double promoBannerHeight = 72.0;
  static const double bottomActionBarHeight = 60.0;
  static const double propertyTypeChipWidth = 88.0;
  static const double propertyTypeChipHeight = 90.0;
  static const double selectableChipWidth = 72.0;
  static const double selectableChipHeight = 38.0;
  static const double showResultsButtonHeight = 52.0;
  static const double propertyCompactImageWidth = 130.0;
  static const double propertyCompactImageHeight = 95.0;
  static const double propertyDetailHeroHeight = 260.0;
  static const double stickyBottomBarHeight = 64.0;

  // ── Profile / navigation redesign — prototype-derived dimensions ─────────
  // Values not already covered by an existing constant above. The segmented
  // track radius reuses `buttonRadius` (12), the tile card radius reuses
  // `cardRadius` (16), and the 4 dp track padding/gap reuses `spacingXS`.

  /// Fully-rounded radius for pills, chips and drag handles.
  static const double pillRadius = 999.0;

  /// Radius of the individual pill inside a segmented tab track.
  static const double segmentedTabItemRadius = 9.0;

  /// Square icon container on a card-variant [ManageListTile].
  static const double manageTileIconBoxSize = 42.0;

  /// Diameter of the soft circle behind an empty-state icon.
  static const double emptyStateIconCircleSize = 60.0;

  /// Height of an empty-state call-to-action button.
  static const double emptyStateActionHeight = 44.0;

  // Icon Sizes
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 28.0;
  static const double categoryIconInnerSize = 24.0;
  static const double amenityIconSize = 44.0;
  static const double nearbyIconSize = 40.0;

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXL = 20.0;
  static const double spacingXXL = 24.0;

  // Animation Durations
  static const int animationDurationMs = 300;
  static const int carouselAutoScrollDurationMs = 3000;
  static const int heartAnimationDurationMs = 150;
  static const int staggerDelayMs = 50;
  static const int splashDurationMs = 2600;
  static const int staggerListItemDelayMs = 60;
  static const int pageTransitionMs = 350;
  static const int microInteractionMs = 120;

  // Screen Names — EXISTING
  static const String homeScreen = '/home';
  static const String searchScreen = '/search';
  static const String searchResultsScreen = '/search-results';

  /// People Search — the paginated people list. Property search keeps
  /// [searchResultsScreen] to itself; the two surfaces share no route.
  static const String peopleSearchScreen = '/people-search';

  /// The builder project wizard. Distinct from [postPropertyScreen]: a builder
  /// publishes projects to `builder_projects`, never listings to `properties`.
  static const String addProjectScreen = '/add-project';

  /// One project's page. Distinct from [propertyDetailScreen] — a project is a
  /// `builder_projects` row, not a listing.
  static const String projectDetailScreen = '/project-detail';

  /// Public "browse all" directories for one profile role each — the
  /// destinations for the Home "Popular Categories" tiles of the same name
  /// (`category_icon_grid.dart`). Route names mirror the portal's own
  /// `/brokers` / `/builders` / `/influencers` (`PropertyCategories.tsx`'s
  /// `handleCardClick`).
  static const String brokersDirectoryScreen = '/brokers';
  static const String buildersDirectoryScreen = '/builders';
  static const String influencersDirectoryScreen = '/influencers';

  /// Public "browse all" projects list — the Home "Popular Categories"
  /// Premium Projects tile's destination, mirroring the portal's
  /// `/latest-projects` (`PropertyCategories.tsx`'s `handleCardClick`).
  /// Distinct from [projectDetailScreen] (one project) and the Home rail
  /// widgets, which only ever show a capped preview.
  static const String latestProjectsScreen = '/latest-projects';

  /// The influencer video form. Distinct from [postPropertyScreen] and
  /// [addProjectScreen]: an influencer publishes videos to `influencer_videos`.
  ///
  /// Create mode only. Editing pushes the screen directly with the row, the same
  /// way `MyListingsSection` pushes the listing wizard with its edit bundle.
  static const String influencerVideoFormScreen = '/influencer-video';
  static const String shortlistScreen = '/shortlist';
  static const String filtersScreen = '/filters';
  static const String propertyDetailScreen = '/property-detail';
  static const String profileScreen = '/profile';
  static const String visitsScreen = '/visits';
  static const String reelsScreen = '/reels';
  static const String postPropertyScreen = '/post-property';

  /// The social Feed — properties/projects/videos merged, mirroring the
  /// portal's `/feed` (CombinedFeed.tsx). Reached from the Workspace Drawer
  /// and the More sheet via WorkspaceDestinations.feed.
  static const String feedScreen = '/feed';

  // ── NEW SCREEN ROUTES ──────────────────────
  static const String notificationsScreen = '/notifications';
  static const String emiCalculatorScreen = '/emi-calculator';
  static const String comparePropertiesScreen = '/compare-properties';
  static const String paymentMethodScreen = '/payment-method';
  // ──────────────────────────────────────────

  // ── PROFILE / NAVIGATION REDESIGN ROUTES ───
  // Registered in app.dart during Phase 1B; the constants land here first so
  // the shared navigation primitives can reference them without duplication.
  static const String messagesScreen = '/messages';
  static const String chatThreadScreen = '/messages/chat';

  /// Group thread. Both thread routes render the same parameterised
  /// `ChatThreadScreen`; they are named separately so the two are
  /// distinguishable in the navigation stack.
  static const String channelChatScreen = '/messages/channel';

  static const String articleEditorScreen = '/articles/edit';

  /// Thin dispatcher that resolves the caller to the correct role-specific
  /// dashboard. Not a screen of its own — see blueprint §2.4.
  static const String manageDashboardScreen = '/manage-dashboard';

  /// Mobile mirror of the portal's `/accept-invite` — shown when this person
  /// has a pending `builder_team_invitations` row. Reached automatically via
  /// `PendingInvitationGate`, the mirror of `TeamInviteGate.tsx`.
  static const String pendingInvitationScreen = '/pending-invitation';

  /// Mobile mirror of the portal's `/team-workspace`
  /// (`TeamMemberDashboard.tsx`). Reached two ways, matching the portal's own
  /// two routing mechanisms: `ManageDashboardDispatcher`'s `team_member` case
  /// (`ProfileDispatch.tsx`'s literal switch, for brand-new invitees) and the
  /// additive Workspace Drawer / More sheet destination gated on
  /// `AuthProvider.hasTeamMembership` (`ProfileDashboardShell.tsx`'s nav
  /// link, for existing users of any other role).
  static const String teamWorkspaceScreen = '/team-workspace';

  /// Phase 6 hubs, reached from the Workspace Drawer and the More sheet.
  static const String networkScreen = '/network';
  static const String socialScreen = '/social';
  static const String upgradeScreen = '/upgrade';

  /// Phase 7 — the read-only Subscription & Billing surface.
  static const String subscriptionBillingScreen = '/subscription-billing';

  /// Phase 8 — the Social leaf screens, reached from the Social hub.
  static const String socialAccountsScreen = '/social/accounts';
  static const String socialCampaignsScreen = '/social/campaigns';
  static const String socialLeadsScreen = '/social/leads';
  static const String socialPreferencesScreen = '/social/preferences';
  static const String socialActivityScreen = '/social/activity';
  static const String socialAnalyticsScreen = '/social/analytics';

  /// "Who viewed my profile" — the list behind the Profile Views stat tile.
  static const String profileViewsScreen = '/profile-views';

  /// Files an account-deletion request. It does not delete the account.
  static const String accountDeletionScreen = '/account-deletion';

  /// The signed-in user's Edit Profile form. The single editing experience for
  /// every role — it replaces the registration-wizard route previously used for
  /// editing (Phase 3, Option A).
  static const String editProfileScreen = '/edit-profile';

  /// Any user's public profile, pushed with `{'userId': ...}` and optionally
  /// `{'avatarHeroTag': ...}` so the tapped avatar can fly into place.
  ///
  /// Distinct from [profileScreen], which is the signed-in user's own profile tab.
  static const String publicProfileScreen = '/public-profile';

  /// Phase 9 — the Network leaf screens, reached from the Network hub.
  static const String myNetworksScreen = '/network/memberships';
  static const String myLeadsScreen = '/network/leads';
  static const String myReferralsScreen = '/network/referrals';
  static const String networkCommunicationScreen = '/network/communication';

  /// Builder-only, matching the portal's `analytics` tab on
  /// `NetworkDashboard.tsx`, which is only registered/rendered for
  /// `profile?.user_type === 'builder'`.
  static const String networkAnalyticsScreen = '/network/analytics';
  // ──────────────────────────────────────────

  // Image Placeholders
  static const String defaultImageUrl =
      'https://picsum.photos/seed/property/400/300';
  static const String avatarUrl = 'https://picsum.photos/seed/avatar/100/100';

  // Budget filter bounds (rupees) — matches Search.tsx's PriceRangeSlider
  // exactly, replacing the old arbitrary 20-500 "lakhs-ish" scale.
  static const double priceMin = 0;
  static const double priceMax = 500000000; // ₹50 Cr
  static const double priceStep = 1000000; // ₹10 L
  // Sent as the effective max whenever the slider is dragged to its ceiling.
  static const double priceUnbounded = 5000000000; // ₹500 Cr

  // Near-me radius search — hardcoded on the website (Search.tsx), ported
  // verbatim rather than made user-configurable, for parity.
  static const double nearMeRadiusKm = 15;
  static const int nearMeResultCap = 100;

  // Pagination — additive vs. the website (which fetches everything in one
  // shot); see the plan's "Deliberate deviations" section.
  static const int searchPageSize = 20;
  static const int mapResultsSafetyCap = 300;

  // Budget filtering and price sorting both need the COMPLETE DB-level
  // matching set (a single capped batch can silently drop real matches that
  // sort/land past its cap) — see PropertyProvider._fetchCompleteMatchingRows.
  // This is the page size used for each read-only `.range()` call while
  // walking that full set, not a cap on the total: the loop continues across
  // as many such pages as the exact result count requires.
  static const int priceAwareFetchBatchSize = 200;
  // Defensive circuit breaker only — not an intended limit. Any realistic
  // property catalogue is far below this; it exists purely so a backend that
  // never reports a shrinking/empty page can't spin the fetch loop forever.
  static const int priceAwareFetchSafetyCeiling = 6000;
}
