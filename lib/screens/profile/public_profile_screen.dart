// screens/profile/public_profile_screen.dart
//
// Any user's public profile.
//
// STAGE 1 SCOPE
// -------------
// The screen, its provider, its services and its route. Entry points from Search,
// Property Details, Messages, Network and Reviews are Stage 2 and are wired one
// screen at a time — so nothing outside this folder is touched here beyond the
// route registration in `app.dart` and its constant.
//
// Two actions are intentionally inert in Stage 1 and render their state rather
// than offering a dead affordance:
//   * Connect / Accept / Cancel — the write paths are Phase 6.
//   * Write a review           — the rating sheet is Phase 5.
// Edit Profile (self-view) is likewise deferred to Phase 3's edit screen, so a
// self-view shows Share alone.
//
// PROVIDER IS SCREEN-SCOPED, matching `ProfileScreen`. It is not registered in
// `main.dart`, so a second profile opened from this one gets its own state and
// nothing leaks between them.
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../config/launch_features.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/number_format.dart';
import '../../core/utils/profile_link.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/builder_project_model.dart';
import '../../models/collaboration.dart';
import '../../models/profile_review.dart';
import '../../models/property_model.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_thread_provider.dart';
import '../../providers/public_profile_provider.dart';
import '../../services/collaboration_service.dart';
import '../../services/messaging_service.dart';
// `ProfileConnectionStatus` — the four-state enum the connect control switches on.
import '../../services/profile_connection_service.dart';
import '../messaging/chat_thread_screen.dart';
import '../messaging/collab_request_sheet.dart';
import '../messaging/messages_list_screen.dart';
import 'actions/profile_qr_sheet.dart';
import 'actions/rating_sheet.dart';
import 'actions/share_profile_sheet.dart';
import 'public_profile_role.dart';
import 'widgets/public_profile_content_sections.dart';
import 'widgets/public_profile_cover_header.dart';
import 'widgets/public_profile_identity.dart';
import 'widgets/public_profile_info_cards.dart';
import 'widgets/public_profile_skeleton.dart';
import 'widgets/public_profile_stats.dart';
import 'widgets/public_profile_sticky_bar.dart';
import 'widgets/sticky_identity_bar.dart';

class PublicProfileScreen extends StatelessWidget {
  /// `profiles.user_id` of the profile being viewed.
  final String userId;

  /// Hero tag matching the avatar that was tapped, so it flies into place. Null
  /// when the caller has no avatar to fly from.
  final String? avatarHeroTag;

  /// Test seam: supplies a pre-built provider instead of constructing one.
  ///
  /// `PublicProfileProvider` already accepts injected services, but this screen
  /// creates it internally, so a test could not reach those seams. Without this,
  /// none of the layout that only exists here — the avatar's negative-offset
  /// overhang, the `SliverAppBar` collapse, the sticky bar — could be verified at
  /// all, because the real provider constructs services that require a live
  /// Supabase client.
  ///
  /// Never non-null in production: nothing passes it, and the route does not
  /// expose it.
  @visibleForTesting
  final PublicProfileProvider? providerOverride;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.avatarHeroTag,
    this.providerOverride,
  });

  @override
  Widget build(BuildContext context) {
    final override = providerOverride;

    // `.value` for an injected provider: the caller owns its lifecycle, so this
    // screen must not dispose it.
    if (override != null) {
      return ChangeNotifierProvider<PublicProfileProvider>.value(
        value: override,
        child: _PublicProfileView(userId: userId, avatarHeroTag: avatarHeroTag),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => PublicProfileProvider(),
      child: _PublicProfileView(userId: userId, avatarHeroTag: avatarHeroTag),
    );
  }
}

class _PublicProfileView extends StatefulWidget {
  final String userId;
  final String? avatarHeroTag;

  const _PublicProfileView({required this.userId, this.avatarHeroTag});

  @override
  State<_PublicProfileView> createState() => _PublicProfileViewState();
}

/// How many public profiles may stack before the chain is stopped.
///
/// Reviewer → their reviewers → theirs again is a legitimate path, but an
/// unbounded chain leaves users unable to find their way back to where they
/// started.
const int _kMaxProfileDepth = 3;

class _PublicProfileViewState extends State<_PublicProfileView> {
  // Same role as `ProfileScreen`'s own scroll view: this screen has no
  // collapsing-header mechanism to drive any more (see
  // `public_profile_cover_header.dart`'s doc comment) — `_scroll` now only
  // backs `_animate`'s "already scrolled, skip the entrance fade" check
  // below, same as before.
  final ScrollController _scroll = ScrollController();

  /// Tracks the real, in-flow identity block so `StickyIdentityOverlay` knows
  /// exactly when it has scrolled out of view — see that widget's doc comment.
  final GlobalKey _identityKey = GlobalKey();

  bool _messaging = false;
  String? _loadedFor;

  final _collabService = CollaborationService();

  /// A `requested`-status collaboration already between the viewer and this
  /// profile, if any — `UserProfile.tsx`'s duplicate-request guard. Drives
  /// the sticky bar's "Requested" state instead of letting a second request
  /// be sent for the same pair.
  Collaboration? _existingCollabRequest;

  /// `UserProfile.tsx`'s `canCollaborate`: viewer authenticated, not self,
  /// and exactly one of {viewer, viewed profile} is an influencer. The
  /// viewer's own `user_type` is already cached on `AuthProvider` — no extra
  /// query needed the way the portal's separate `viewerUserType` fetch is.
  bool _canCollaborate(UserProfile profile) {
    if (!LaunchFeatures.paidCollaborations) return false;
    final auth = context.read<AuthProvider>();
    return isCollabEligible(
      viewerId: auth.userId,
      viewedUserId: profile.userId,
      viewedIsInfluencer: profile.isInfluencer,
      viewerIsInfluencer: (auth.userType?.toLowerCase()) == 'influencer',
    );
  }

  Future<void> _collaborate(UserProfile profile) async {
    // A request already exists for this pair — "Collab Requested" opens/
    // focuses it in the Collabs tab rather than letting a second request
    // be sent for the same pair.
    if (_existingCollabRequest != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MessagesListScreen(initialTab: 2),
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final viewerIsInfluencer = (auth.userType?.toLowerCase()) == 'influencer';
    final sent = await showCollabRequestSheet(
      context,
      counterpartyId: profile.userId,
      counterpartyName: profile.displayTitle ?? 'this user',
      viewerIsInfluencer: viewerIsInfluencer,
    );
    if (sent == true && mounted) {
      // Navigate to/focus the created request rather than only telling the
      // user where to go look for it.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MessagesListScreen(initialTab: 2),
        ),
      );
      if (mounted) {
        final viewerId = auth.userId;
        if (viewerId != null) _checkExistingCollabRequest(viewerId);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Deferred to the end of the frame for the reason `ProfileScreen` documents:
    // the provider raises its loading flags and notifies synchronously, which
    // would mark this element dirty while it is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted) return;
    if (_loadedFor == widget.userId) return;
    _loadedFor = widget.userId;

    final viewerId = context.read<AuthProvider>().userId;
    final provider = context.read<PublicProfileProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId: widget.userId, viewerId: viewerId);
    });

    if (LaunchFeatures.paidCollaborations &&
        viewerId != null &&
        viewerId != widget.userId) {
      _checkExistingCollabRequest(viewerId);
    }
  }

  Future<void> _checkExistingCollabRequest(String viewerId) async {
    final existing = await _collabService.findExistingRequest(
      viewerId: viewerId,
      counterpartyId: widget.userId,
    );
    if (!mounted || _loadedFor != widget.userId) return;
    setState(() => _existingCollabRequest = existing);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _share(UserProfile profile) {
    showShareProfileSheet(
      context,
      userId: profile.userId,
      name: profile.displayTitle ?? '',
      userType: profile.userType,
      city: profile.effectiveCity,
      rating: context.read<PublicProfileProvider>().displayRating.average,
      reviewsCount: context.read<PublicProfileProvider>().displayRating.count,
    );
  }

  void _showMoreSheet(UserProfile profile) {
    // Same builder the share and QR sheets use, so all three agree on the URL.
    final shareUrl = profileShareUrl(
      userId: profile.userId,
      name: profile.displayTitle,
      role: profile.userType,
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              ListTile(
                leading: const Icon(
                  Icons.link_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'Copy profile link',
                  style: AppTextStyles.body.copyWith(fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  copyProfileLink(context, shareUrl);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'Show QR code',
                  style: AppTextStyles.body.copyWith(fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showProfileQrSheet(
                    context,
                    userId: profile.userId,
                    name: profile.displayTitle ?? '',
                    userType: profile.userType,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens (or reuses) the conversation and pushes the existing thread screen.
  ///
  /// Uses `MessagingService.startConversation`, which wraps the same
  /// `start_conversation` RPC the web app calls and which
  /// `messages_list_screen.dart` already uses for its "new chat" flow. Nothing in
  /// the messaging module is modified — this is the same call in the same order.
  Future<void> _message(UserProfile profile) async {
    if (_messaging) return;
    setState(() => _messaging = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Messaging someone from their public profile carries no property/lead
      // context either — gated the same as a cold "New Chat" pick.
      final conversationId = await MessagingService().startConversation(
        profile.userId,
        skipRequestGate: false,
      );

      if (!mounted) return;

      await navigator.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: AppConstants.chatThreadScreen),
          builder: (_) => ChatThreadScreen(
            kind: ChatThreadKind.conversation,
            threadId: conversationId,
            title: profile.displayTitle ?? 'Chat',
            avatarUrl: profile.avatarUrl,
            initials: profile.initials,
          ),
        ),
      );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't start the conversation.")),
        );
    } finally {
      if (mounted) setState(() => _messaging = false);
    }
  }

  void _openConnections(PublicProfileProvider provider) {
    // Approved decision D3: a self-view reuses the existing My Networks screen.
    // Another user's connection list is not a surface this app exposes, so the
    // tile is inert there.
    if (!provider.isSelf) return;
    Navigator.pushNamed(context, AppConstants.myNetworksScreen);
  }

  /// Stage 2B: opens a review author's profile from this profile.
  ///
  /// Two guards. The author is never the profile being viewed — `user_ratings` is
  /// unique on (rated, rater) and the DB forbids self-rating — but the check costs
  /// nothing and prevents pushing a duplicate of the current screen if that ever
  /// changes. And the profile→profile chain is capped, so a user cannot walk an
  /// unbounded stack of reviewer-of-reviewer screens and lose their way back.
  void _openReviewerProfile(ProfileReview review, UserProfile current) {
    if (review.raterId.isEmpty || review.raterId == current.userId) return;

    final depth = _profileDepth();
    if (depth >= _kMaxProfileDepth) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Go back to keep browsing profiles.')),
        );
      return;
    }

    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': review.raterId, 'depth': depth + 1},
    );
  }

  /// How deep this screen sits in a chain of profiles.
  ///
  /// Carried in the route arguments rather than measured from the navigator:
  /// Flutter exposes no way to enumerate the stack (`popUntil` only inspects the
  /// topmost route, so counting with it silently returns 1). The value rides
  /// through `app.dart`'s existing `settings: settings` forwarding, so no change
  /// to the route registration is needed — a screen pushed without it simply
  /// starts at 0.
  int _profileDepth() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['depth'] is int) return args['depth'] as int;
    return 0;
  }

  /// Phase 6 — connect, cancel or accept, depending on the current state.
  ///
  /// Cancelling asks first: it is the one destructive transition, and an
  /// accidental tap on "Requested" would silently withdraw a request the other
  /// party may already have seen.
  Future<void> _connect(PublicProfileProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);

    if (provider.connectionStatus == ProfileConnectionStatus.pendingSent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel request?'),
          content: const Text('Your connection request will be withdrawn.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel request'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final error = await provider.actOnConnection();
    if (!mounted) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(error ?? _connectionSuccessMessage(provider))),
      );
  }

  /// Worded from the state the action produced, read back from the database.
  String _connectionSuccessMessage(PublicProfileProvider provider) {
    switch (provider.connectionStatus) {
      case ProfileConnectionStatus.connected:
        return 'Connected';
      case ProfileConnectionStatus.pendingSent:
        return 'Request sent';
      case ProfileConnectionStatus.pendingReceived:
      case ProfileConnectionStatus.none:
        return 'Request cancelled';
    }
  }

  /// Phase 5 — opens the rating sheet and submits the result.
  Future<void> _rate(
    PublicProfileProvider provider,
    UserProfile profile,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    final submission = await showRatingSheet(
      context,
      userName: profile.displayTitle ?? 'this user',
      existing: provider.myRating,
    );
    if (submission == null || !mounted) return;

    final error = await provider.submitRating(
      rating: submission.rating,
      review: submission.review,
    );
    if (!mounted) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ??
                (provider.myRating == null
                    ? 'Thanks for your feedback'
                    : 'Your review has been updated'),
          ),
        ),
      );
  }

  void _openProperty(PropertyModel property) {
    Navigator.pushNamed(
      context,
      AppConstants.propertyDetailScreen,
      arguments: {'propertyId': property.id},
    );
  }

  void _openProject(BuilderProjectModel project) {
    // Previously a snackbar: no project-detail route existed, so pushing one
    // would have fallen through to Home. That route exists now, so the row
    // navigates like every other tappable row on this screen.
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': project.id},
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PublicProfileProvider>();
    final profile = provider.profile;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: provider.refresh,
        // Same scroll architecture as `ProfileScreen`: a plain
        // `SingleChildScrollView` over a `Column`, so the cover header
        // below scrolls away with everything else exactly like
        // `ProfileCoverHeader` does there — no `CustomScrollView`, no
        // sliver, no pinned/collapsing header. The sticky avatar+name bar
        // is a `Positioned` overlay on top (see `StickyIdentityOverlay`),
        // not part of this scrolling list, so it never renders alongside
        // the real avatar/name further down.
        child: Stack(
          children: [
            SingleChildScrollView(
              // Same key as before, so it stays disambiguated from
              // `TrustChipStrip`'s unrelated horizontal chip scroller
              // further down the tree in tests.
              key: const Key('publicProfileScrollView'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: Column(
                children: [
                  PublicProfileCoverHeader(
                    coverImageUrl: profile?.backgroundImageUrl,
                    onBack: () => Navigator.of(context).maybePop(),
                    onShare: profile == null ? () {} : () => _share(profile),
                    onMore: profile == null
                        ? () {}
                        : () => _showMoreSheet(profile),
                    // Null on the error states, where there is no identity
                    // to show at all.
                    avatarOverlay: profile != null
                        ? PublicProfileAvatar(
                            avatarUrl: profile.avatarUrl,
                            initials: profile.initials,
                            isVerified: profile.isVerified,
                            heroTag: widget.avatarHeroTag,
                          )
                        : provider.isInitialLoad
                        ? const PublicProfileAvatarSkeleton()
                        : null,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildBody(provider, profile),
                  ),
                ],
              ),
            ),
            if (profile != null)
              StickyIdentityOverlay(
                scrollController: _scroll,
                identityKey: _identityKey,
                avatarUrl: profile.avatarUrl,
                initials: profile.initials,
                name: profile.displayTitle ?? '',
              ),
          ],
        ),
      ),
      bottomNavigationBar: profile == null
          ? null
          : ProfileStickyActionBar(
                  isSelf: provider.isSelf,
                  viewerSignedIn: provider.viewerSignedIn,
                  connectionStatus: provider.connectionStatus,
                  statusLoading:
                      provider.connectionLoading || provider.connectionBusy,
                  onShare: () => _share(profile),
                  onConnect: provider.canActOnConnection
                      ? () => _connect(provider)
                      : null,
                  onMessage: _messaging ? null : () => _message(profile),
                  onCollaborate: _canCollaborate(profile)
                      ? () => _collaborate(profile)
                      : null,
                  collabRequested: _existingCollabRequest != null,
                  onSignIn: () => Navigator.pushNamed(context, '/auth'),
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
    );
  }

  List<Widget> _buildBody(
    PublicProfileProvider provider,
    UserProfile? profile,
  ) {
    // First load: a full-layout skeleton, announced as one thing.
    if (provider.isInitialLoad) {
      // Not const: `Semantics` has no const constructor.
      return [
        Semantics(
          label: 'Loading profile',
          child: const ExcludeSemantics(child: PublicProfileSkeleton()),
        ),
      ];
    }

    if (provider.profileNotFound) {
      // No `SliverFillRemaining` any more (this is a plain `Column` now,
      // not a `CustomScrollView`) — a fixed minimum height keeps this
      // centred nicely below the header without needing viewport-fill
      // sliver machinery for what is only ever a short message + button.
      return [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Center(
            child: EmptyStateView(
              icon: Icons.person_off_outlined,
              title: 'Profile not available',
              message: 'This profile may have been removed.',
              actionLabel: 'Go back',
              onAction: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ];
    }

    if (profile == null) {
      return [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Center(
            child: EmptyStateView(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load this profile",
              message: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: provider.refresh,
            ),
          ),
        ),
      ];
    }

    final name = profile.displayTitle ?? 'This user';
    final gutter = const EdgeInsets.symmetric(
      horizontal: AppConstants.spacingL,
    );

    final detailGroups = _buildDetailGroups(profile);

    return [
      // ── Identity ─────────────────────────────────────────────────────────
      _animate(
        delayMs: 100,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppConstants.spacingL,
            right: AppConstants.spacingL,
            top: AppConstants.spacingM,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PublicIdentityBlock(
                key: _identityKey,
                profile: profile,
                isSelf: provider.isSelf,
                viewerSignedIn: provider.viewerSignedIn,
                connectionStatus: provider.connectionStatus,
                statusLoading:
                    provider.connectionLoading || provider.connectionBusy,
                // Same handlers `ProfileStickyActionBar` below is wired to —
                // this only gives the Follow/Share pair a second, higher-up
                // home, it does not change what either action does.
                onConnect: provider.canActOnConnection
                    ? () => _connect(provider)
                    : null,
                onShare: () => _share(profile),
              ),
              const SizedBox(height: AppConstants.spacingM),
              RatingInlineRow(
                rating: provider.displayRating,
                isLoading: provider.ratingsLoading,
              ),
              const SizedBox(height: AppConstants.spacingM),
              IdentityMetaStrip(profile: profile),
            ],
          ),
        ),
      ),

      // ── Trust chips (own horizontal padding, so they can scroll edge to edge)
      _animate(
        delayMs: 150,
        child: Padding(
          padding: const EdgeInsets.only(top: AppConstants.spacingXL),
          child: TrustChipStrip(profile: profile),
        ),
      ),

      // ── Stats ────────────────────────────────────────────────────────────
      _animate(
        delayMs: 200,
        child: Padding(
          padding: gutter.copyWith(top: AppConstants.spacingL),
          child: StatTripletCard(
            isLoading: provider.contentLoading || provider.connectionLoading,
            hasFailed: provider.contentFailed,
            tiles: [
              ProfileStatTile(
                label: contentLabel(profile.userType, plural: true),
                value: formatCompactCount(provider.contentCount),
              ),
              // Hidden for individuals — the portal's rule.
              if (!profile.isIndividual)
                ProfileStatTile(
                  label: 'Connections',
                  value: formatCompactCount(provider.connectionsCount),
                  onTap: provider.isSelf
                      ? () => _openConnections(provider)
                      : null,
                ),
              ProfileStatTile(
                label: 'Rating',
                value: formatRating(provider.displayRating.average),
              ),
            ],
          ),
        ),
      ),

      // ── About ────────────────────────────────────────────────────────────
      if (profile.effectiveBio != null)
        _animate(
          delayMs: 250,
          child: Padding(
            padding: gutter.copyWith(top: AppConstants.spacingL),
            child: ProfileAboutCard(bio: profile.effectiveBio!),
          ),
        ),

      // ── Contact ──────────────────────────────────────────────────────────
      _animate(
        delayMs: 300,
        child: Padding(
          padding: gutter.copyWith(top: AppConstants.spacingL),
          child: ProfileContactCard(
            profile: profile,
            unlocked: provider.canSeeContactDetails,
            // Phase 6 wires this; until then the locked card explains the gate
            // without offering a button that does nothing.
            onConnect: null,
          ),
        ),
      ),

      // ── Details ──────────────────────────────────────────────────────────
      if (ProfileDetailsCard.hasContent(detailGroups))
        _animate(
          delayMs: 350,
          child: Padding(
            padding: gutter.copyWith(top: AppConstants.spacingL),
            child: ProfileDetailsCard(groups: detailGroups),
          ),
        ),

      // ── Social links ─────────────────────────────────────────────────────
      if (ProfileSocialLinksRow.hasContent(profile))
        _animate(
          delayMs: 400,
          child: Padding(
            padding: gutter.copyWith(top: AppConstants.spacingL),
            child: ProfileSocialLinksRow(profile: profile),
          ),
        ),

      // ── Social reach ─────────────────────────────────────────────────────
      if (SocialReachCard.hasData(profile))
        _animate(
          delayMs: 400,
          child: Padding(
            padding: gutter.copyWith(top: AppConstants.spacingXXL),
            child: SocialReachCard(profile: profile),
          ),
        ),

      // ── Listings ─────────────────────────────────────────────────────────
      _animate(
        delayMs: 400,
        child: Padding(
          padding: const EdgeInsets.only(top: AppConstants.spacingM),
          child: ProfileListingsSection(
            userType: profile.userType,
            displayName: name,
            properties: provider.properties,
            projects: provider.projects,
            isLoading: provider.contentLoading,
            hasFailed: provider.contentFailed,
            onRetry: provider.retryContent,
            onPropertyTap: _openProperty,
            onProjectTap: _openProject,
            // Stage 2 introduces the dedicated list screen; until then the
            // footer button is hidden rather than pointing nowhere.
            onViewAll: null,
          ),
        ),
      ),

      // ── Reviews ──────────────────────────────────────────────────────────
      _animate(
        delayMs: 400,
        child: Padding(
          padding: const EdgeInsets.only(top: AppConstants.spacingM),
          child: ProfileReviewsSection(
            ratings: provider.ratings,
            isBuilder: profile.isBuilder,
            displayName: name,
            isLoading: provider.ratingsLoading,
            hasFailed: provider.ratingsFailed,
            onRetry: provider.retryRatings,
            onViewAll: null,
            // Phase 5. Null when the viewer cannot rate — signed out, or
            // looking at their own profile.
            onWriteReview: provider.canRate
                ? () => _rate(provider, profile)
                : null,
            writeReviewLabel: provider.myRating == null
                ? 'Write a review'
                : 'Update your review',
            onReviewerTap: (review) => _openReviewerProfile(review, profile),
          ),
        ),
      ),

      // Clearance for the sticky bar.
      const SizedBox(height: kProfileStickyBarHeight + AppConstants.spacingXXL),
    ];
  }

  /// Entrance animation, honouring the platform's reduce-motion setting.
  ///
  /// Delays step by 50 ms and cap at 400, the convention `profile_screen.dart`
  /// established (fadeIn 400 ms, delays 100–300).
  ///
  /// Skipped once the user has already scrolled away from the top. These
  /// sections do not exist while `provider.isInitialLoad` is true — only the
  /// skeleton does — so on a slow connection they are first built whenever
  /// the profile finishes loading, which can land well after the user has
  /// started scrolling. Animating them in at that point restarts a fade from
  /// fully invisible right under the user's finger: everything between the
  /// header and the bottom bar goes blank for several hundred milliseconds
  /// before fading back, which reads as the screen suddenly turning white
  /// mid-scroll. Skipping the fade once `_scroll.offset > 0` keeps the
  /// intended effect for the common case (data arrives before any scrolling)
  /// while preventing it from replaying under the user's own gesture.
  Widget _animate({required int delayMs, required Widget child}) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    if (_scroll.hasClients && _scroll.offset > 0) return child;
    return child
        .animate()
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: delayMs),
        )
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }

  /// The portal's five sidebar cards, regrouped for one card.
  ///
  /// Field selection and conditions follow pages/UserProfile.tsx exactly —
  /// Business Details for non-individuals (1264), Personal Details for
  /// non-builders (1335), Influencer Stats (1369), Builder Details (1440),
  /// Broker Insights (1474).
  List<ProfileDetailGroup> _buildDetailGroups(UserProfile profile) {
    final sm = profile.socialMedia;
    final groups = <ProfileDetailGroup>[];

    if (!profile.isIndividual) {
      groups.add(
        ProfileDetailGroup(
          title: 'Business',
          rows: [
            ProfileDetailRow(
              label: 'Experience',
              value: profile.hasExperienceField
                  ? '${profile.effectiveExperience ?? 0} yrs'
                  : null,
            ),
            ProfileDetailRow(
              label: 'Specialisation',
              chips: profile.specialization,
            ),
            ProfileDetailRow(
              label: 'Areas of operation',
              value: profile.effectiveCity,
            ),
            ProfileDetailRow(label: 'RERA', value: profile.effectiveRera),
            ProfileDetailRow(
              label: 'Website',
              value: profile.effectiveWebsite == null ? null : 'Visit site',
              linkUrl: profile.effectiveWebsite,
            ),
          ],
        ),
      );
    }

    if (profile.isBuilder) {
      groups.add(
        ProfileDetailGroup(
          title: 'Builder profile',
          rows: [
            ProfileDetailRow(label: 'Project types', chips: sm.projectTypes),
            ProfileDetailRow(
              label: 'Areas of expertise',
              chips: sm.areasOfExpertise,
            ),
            ProfileDetailRow(label: 'Company type', value: sm.companyType),
          ],
        ),
      );
    }

    if (profile.isBroker) {
      groups.add(
        ProfileDetailGroup(
          title: 'Broker insights',
          rows: [
            ProfileDetailRow(label: 'Type', value: sm.brokerType),
            ProfileDetailRow(label: 'Commission', value: sm.commissionDetails),
            ProfileDetailRow(label: 'Price range', value: _priceRange(profile)),
            ProfileDetailRow(label: 'Languages', chips: sm.languagesKnown),
          ],
        ),
      );
    }

    if (profile.isInfluencer) {
      groups.add(
        ProfileDetailGroup(
          title: 'Influencer',
          rows: [
            ProfileDetailRow(label: 'Platform', value: sm.primaryPlatform),
            ProfileDetailRow(label: 'Category', value: sm.category),
            ProfileDetailRow(label: 'Audience', value: sm.audienceType),
            ProfileDetailRow(
              label: 'Instagram',
              value: sm.instagramFollowers == null
                  ? null
                  : formatCompactCount(sm.instagramFollowers!),
            ),
            ProfileDetailRow(
              label: 'YouTube',
              value: sm.youtubeSubscribers == null
                  ? null
                  : formatCompactCount(sm.youtubeSubscribers!),
            ),
            ProfileDetailRow(
              label: 'Shoutout from',
              value: sm.basePricingShoutout == null
                  ? null
                  : '₹${sm.basePricingShoutout}',
            ),
            ProfileDetailRow(
              label: 'Video from',
              value: sm.basePricingVideo == null
                  ? null
                  : '₹${sm.basePricingVideo}',
            ),
            ProfileDetailRow(label: 'Content', chips: sm.contentTypes),
            ProfileDetailRow(label: 'Languages', chips: sm.languagesKnown),
          ],
        ),
      );
    }

    // The portal shows Personal Details for everyone except builders.
    if (!profile.isBuilder) {
      groups.add(
        ProfileDetailGroup(
          title: 'Personal',
          rows: [
            ProfileDetailRow(label: 'Gender', value: sm.gender),
            ProfileDetailRow(label: 'Date of birth', value: _formatDob(sm.dob)),
          ],
        ),
      );
    }

    return groups;
  }

  String? _priceRange(UserProfile profile) {
    final sm = profile.socialMedia;
    final min = sm.priceRangeMin;
    final max = sm.priceRangeMax;
    if (min == null && max == null) return null;
    return '₹${min ?? 0} – ${max == null ? 'Any' : '₹$max'}';
  }

  /// `yyyy-MM-dd` as stored by the portal's date input, rendered long-form as the
  /// portal does (UserProfile.tsx:1356 uses `toLocaleDateString` with
  /// year/month/day). Falls back to the raw value if it will not parse.
  String? _formatDob(String? raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }
}
