// Public Profile — layout validation at real device sizes and text scales.
//
// WHAT THIS IS, AND WHAT IT IS NOT
// -------------------------------
// This is NOT device validation. No Android or iOS device or emulator is
// available in this environment (`flutter devices` reports only Windows, Chrome
// and Edge; `flutter emulators` reports none; `adb` is not on PATH), and reaching
// this screen through the approved Chat Thread entry point requires a signed-in
// Supabase session, which cannot be established here.
//
// What it IS: the strongest falsifiable substitute — the real widgets, rendered at
// the three widths that matter and at 130% text scale, with the project's existing
// geometry-based overflow detector asserting that nothing is laid out larger than
// its parent allows. That covers the layout risks flagged in the Stage 1 report;
// it cannot cover frame timings or gesture feel.
//
// Every item still requiring a human on hardware is listed at the bottom of
// docs/impact-reports/PHASE_1_DEVICE_VALIDATION.md.
import 'package:flutter/material.dart';
// RenderFlex / DebugCreator for the creator-aware detector below.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/builder_project_model.dart';
import 'package:propcid_app/models/profile_review.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/public_profile_provider.dart';
import 'package:propcid_app/screens/profile/public_profile_screen.dart';
import 'package:propcid_app/core/widgets/scale_tap.dart';
import 'package:propcid_app/screens/profile/widgets/public_profile_content_sections.dart';
import 'package:propcid_app/screens/profile/widgets/public_profile_cover_header.dart';
import 'package:propcid_app/screens/profile/widgets/public_profile_identity.dart';
import 'package:propcid_app/screens/profile/widgets/public_profile_info_cards.dart';
import 'package:propcid_app/screens/profile/widgets/public_profile_sticky_bar.dart';
import 'package:propcid_app/services/network_service.dart';
import 'package:propcid_app/services/profile_connection_service.dart';
import 'package:propcid_app/services/profile_content_service.dart';
import 'package:propcid_app/services/user_profile_service.dart';

import 'support/overflow_detector.dart';

/// Like [overflowingBoxes], but names the widget and source location.
///
/// The shared detector reports geometry only, and Flutter deduplicates its own
/// rendering-library dump across repeated identical errors — so when the same
/// overflow fires in several size variants, only the first one is ever described.
/// This makes every failure self-locating. Kept local to this file so the shared
/// helper other suites rely on is untouched.
List<String> overflowingWithCreators(WidgetTester tester) {
  final found = <String>[];

  void visit(RenderObject node) {
    // Bound to an explicit local: capturing `node` in the visitChildren closure
    // below defeats flow-based promotion, so `flex` carries the type instead.
    final RenderFlex? flex = node is RenderFlex ? node : null;
    if (flex != null && flex.hasSize) {
      final horizontal = flex.direction == Axis.horizontal;
      var total = 0.0;
      flex.visitChildren((c) {
        if (c is RenderBox && c.hasSize) {
          total += horizontal ? c.size.width : c.size.height;
        }
      });
      final own = horizontal ? flex.size.width : flex.size.height;
      if (total > own + 0.5) {
        final creator = flex.debugCreator;
        final where = creator is DebugCreator
            ? creator.element.debugGetCreatorChain(12)
            : '<unknown>';
        found.add('RenderFlex(${flex.direction.name}) '
            '${total.toStringAsFixed(1)} > ${own.toStringAsFixed(1)} @ $where');
      }
    }
    node.visitChildren(visit);
  }

  // `rootElement`, not the deprecated `renderViewElement` the shared helper still
  // uses — a new file must not add a new analyzer issue.
  visit(tester.binding.rootElement!.renderObject!);
  return found;
}

// ─────────────────────────────────────────────────────────────────────────────
// Device sizes. Logical pixels at DPR 1, matching how dashboard_design_parity
// and shell_overflow_probe drive their probes.
// ─────────────────────────────────────────────────────────────────────────────
const Size kSmall = Size(320, 780); // iPhone SE 1st gen — the tightest width
const Size kBaseline = Size(390, 844); // iPhone 14 / Pixel 7
const Size kLarge = Size(430, 932); // Pro Max / Ultra

// ─────────────────────────────────────────────────────────────────────────────
// Fakes. Each subclasses the real service and overrides only what is called, so
// the production code path under test is the real one.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeProfileService extends UserProfileService {
  _FakeProfileService(this.profile);
  final UserProfile? profile;

  @override
  Future<UserProfile?> fetchOwn(String userId) async => profile;

  @override
  Future<UserProfile?> fetchPublic(
    String userId, {
    required bool viewerSignedIn,
  }) async =>
      profile;

  @override
  Future<Map<String, UserProfile>> fetchProfilesByIds(
    Iterable<String> userIds,
  ) async =>
      const {};
}

class _FakeContentService extends ProfileContentService {
  _FakeContentService({
    this.properties = const [],
    this.projects = const [],
    this.ratings = RatingBreakdown.zero,
    this.throwOnContent = false,
  });

  final List<PropertyModel> properties;
  final List<BuilderProjectModel> projects;
  final RatingBreakdown ratings;
  final bool throwOnContent;

  @override
  Future<List<PropertyModel>> fetchProperties(String userId) async {
    if (throwOnContent) throw Exception('forced failure');
    return properties;
  }

  @override
  Future<List<BuilderProjectModel>> fetchBuilderProjects(
    String builderId, {
    required bool viewerIsOwner,
  }) async {
    if (throwOnContent) throw Exception('forced failure');
    return projects;
  }

  @override
  Future<RatingBreakdown> fetchRatings(String userId) async => ratings;
}

class _FakeConnectionService extends ProfileConnectionService {
  _FakeConnectionService(this.status);
  final ProfileConnectionStatus status;

  @override
  Future<ProfileConnectionStatus> getStatus({
    required String? viewerId,
    required String profileUserId,
  }) async =>
      status;
}

class _FakeNetworkService extends NetworkService {
  _FakeNetworkService(this.count);
  final int count;

  @override
  Future<int> getAcceptedCount(String userId) async => count;
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

UserProfile _profileFor(
  String role, {
  String? displayName,
  bool rich = true,
}) {
  return UserProfile.fromMap(<String, dynamic>{
    'user_id': 'u-1',
    'display_name': displayName ?? 'Asha Menon',
    'username': 'ashamenon',
    'user_type': role,
    'created_at': '2019-04-02T10:00:00Z',
    if (rich) ...{
      'company_name': role == 'individual' ? null : 'Prestige Realty Partners',
      'bio': 'Fifteen years advising buyers across the western suburbs, with a '
          'focus on redevelopment and first-time purchases. Straight answers, '
          'no pressure, and a lot of patience for questions. Happy to walk '
          'through comparables before you commit to anything at all.',
      'city': 'Mumbai',
      'state': 'Maharashtra',
      'office_address': '12 MG Road, Bandra West',
      'years_experience': 15,
      'specialization': ['Luxury Properties', 'Commercial Leasing'],
      'rera_number': 'MH12345678',
      'verification_status': 'verified',
      'website': 'prestigerealty.example',
      'ig_followers_count': 12300,
      'fb_followers_count': 4200,
      'social_followers_synced_at': '2026-08-05T08:00:00Z',
      'phone': '+919876543210',
      'email': 'asha@example.com',
      'social_media': {
        'gender': 'Female',
        'dob': '1988-03-14',
        'instagram': 'https://instagram.com/asha',
        'linkedin_profile_url': 'https://linkedin.com/in/asha',
        'whatsapp_number': '919876543210',
        'broker_type': 'Independent Broker',
        'commission_details': '2% of transaction value, negotiable on exclusives',
        'price_range_min': 2500000,
        'price_range_max': 90000000,
        'languages_known': ['English', 'Hindi', 'Marathi'],
        'areas_of_expertise': ['Luxury Properties', 'Redevelopment'],
        'project_types': ['Residential', 'Mixed Use'],
        'primary_platform': 'Instagram',
        'category': 'Real Estate Influencer',
        'audience_type': 'First-time Buyers',
        'instagram_followers': 12300,
        'youtube_subscribers': 4500,
        'content_types': ['Reels', 'Property Tours'],
      },
    },
  });
}

RatingBreakdown _ratingsFixture() => RatingBreakdown.fromRatings(
      [
        {'id': '1', 'rating': 5, 'rater_id': 'a', 'review': 'Excellent service throughout.'},
        {'id': '2', 'rating': 5, 'rater_id': 'b', 'review': 'Very responsive and clear.'},
        {'id': '3', 'rating': 4, 'rater_id': 'c', 'review': 'Good, minor delays.'},
        {'id': '4', 'rating': 2, 'rater_id': 'd', 'review': null},
      ],
      raterTypes: const {'a': 'individual', 'b': 'broker', 'c': 'individual', 'd': 'individual'},
      reviews: const [
        ProfileReview(id: '1', rating: 5, raterId: 'a', raterName: 'Ravi Kumar', review: 'Excellent service throughout.'),
        ProfileReview(id: '2', rating: 5, raterId: 'b', raterName: 'Meera Shah', review: 'Very responsive and clear.'),
        ProfileReview(id: '3', rating: 4, raterId: 'c', raterName: 'Anonymous', review: 'Good, minor delays.'),
      ],
    );

PublicProfileProvider _provider({
  required UserProfile? profile,
  ProfileConnectionStatus status = ProfileConnectionStatus.none,
  List<PropertyModel> properties = const [],
  List<BuilderProjectModel> projects = const [],
  RatingBreakdown? ratings,
  int connections = 42,
  bool failContent = false,
}) =>
    PublicProfileProvider(
      profileService: _FakeProfileService(profile),
      contentService: _FakeContentService(
        properties: properties,
        projects: projects,
        ratings: ratings ?? RatingBreakdown.zero,
        throwOnContent: failContent,
      ),
      connectionService: _FakeConnectionService(status),
      networkService: _FakeNetworkService(connections),
    );

/// Pumps the real screen at [size] and [textScale], then settles.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required PublicProfileProvider provider,
  Size size = kBaseline,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: PublicProfileScreen(
          userId: 'u-1',
          providerOverride: provider,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _hostWidget(Widget child, {double textScale = 1.0}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The fakes subclass real services whose constructors resolve
    // Supabase.instance.client, so a client must exist. Loopback URL, no token
    // refresh, empty session store — nothing touches the network.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // ── 1. Cover image ──────────────────────────────────────────────────────
  group('cover', () {
    testWidgets('falls back to the brand gradient when there is no cover',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('broker')),
      );
      // No network image should be attempted for a null cover.
      expect(find.byType(Image), findsNothing);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('renders a cover when the column is populated', (tester) async {
      final profile = UserProfile.fromMap({
        'user_id': 'u-1',
        'display_name': 'Asha Menon',
        'user_type': 'broker',
        'background_image_url': 'https://example.com/cover.jpg',
      });
      await _pumpScreen(tester, provider: _provider(profile: profile));
      expect(tester.takeException(), isNull);
    });
  });

  // ── 2. Avatar overlap ───────────────────────────────────────────────────
  group('avatar overhang', () {
    testWidgets('the 88 dp avatar straddles the cover edge, unclipped',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('broker')),
      );

      final avatarFinder = find.byType(PublicProfileAvatar);
      expect(avatarFinder, findsOneWidget);

      final avatar = tester.getRect(avatarFinder);

      // Declared geometry: 88 dp square.
      expect(avatar.width, closeTo(kPublicAvatarSize, 0.5));
      expect(avatar.height, closeTo(kPublicAvatarSize, 0.5));

      // Left inset of 20, matching ProfileCoverHeader.
      expect(avatar.left, closeTo(20, 0.5));

      // THE OVERLAP: the cover's bottom edge is at kPublicCoverHeight (the test
      // view has no status-bar inset). The avatar must cross it — top above,
      // bottom below — which is what "overhangs by 42" means. If the Stack's
      // negative offset were dropped or clipped, this fails.
      const coverBottom = kPublicCoverHeight;
      expect(avatar.top, lessThan(coverBottom),
          reason: 'avatar should start above the cover edge');
      expect(avatar.bottom, greaterThan(coverBottom),
          reason: 'avatar should extend below the cover edge');
      expect(avatar.bottom - coverBottom, closeTo(kPublicAvatarOverhang, 1.0),
          reason: 'overhang should be $kPublicAvatarOverhang dp');

      // Fully on screen — not pushed off the top by the negative offset.
      expect(avatar.top, greaterThanOrEqualTo(0));

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('the avatar is painted by the header, not by the sliver below it',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('broker')),
      );

      // The regression this pins. The geometry assertions above pass either way
      // — the rect is identical whether the avatar sits in the header or in the
      // next sliver. What broke was paint order: a pinned SliverAppBar paints
      // above every later sliver, so an avatar in the following sliver offset
      // upward to straddle the cover was drawn *behind* the cover, leaving only
      // the 42 dp below the header's edge visible. `Clip.none` cannot fix that,
      // because the occlusion is the viewport's paint order, not Stack clipping.
      // The avatar must therefore be inside the header.
      expect(
        find.descendant(
          of: find.byType(PublicProfileCoverHeader),
          matching: find.byType(PublicProfileAvatar),
        ),
        findsOneWidget,
        reason: 'the avatar must be inside the header to survive pinning',
      );

      // And the header must reserve the overhang, or its own bounds clip it.
      final avatar = tester.getRect(find.byType(PublicProfileAvatar));
      expect(avatar.bottom, lessThanOrEqualTo(kPublicHeaderHeight + 0.5),
          reason: 'kPublicHeaderHeight must cover the avatar completely');
    });

    testWidgets('the identity text clears the avatar rather than sitting under it',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('broker')),
      );

      final avatar = tester.getRect(find.byType(PublicProfileAvatar));
      // Scoped to the identity block: the company name legitimately appears twice
      // — as the heading and as the "company" trust chip — so a bare text finder
      // is ambiguous.
      final name = tester.getRect(
        find.descendant(
          of: find.byType(PublicIdentityBlock),
          matching: find.text('Prestige Realty Partners'),
        ),
      );

      expect(name.top, greaterThanOrEqualTo(avatar.bottom - 1),
          reason: 'the name must begin below the avatar, not overlap it');
    });

    testWidgets('the avatar scrolls with the identity it belongs to',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(
          profile: _profileFor('broker'),
          ratings: _ratingsFixture(),
        ),
      );

      Finder nameFinder() => find.descendant(
            of: find.byType(PublicIdentityBlock),
            matching: find.text('Prestige Realty Partners'),
          );

      final gapAtRest =
          tester.getRect(nameFinder()).top - tester.getRect(find.byType(PublicProfileAvatar)).top;

      // Living in the header means the avatar is positioned against a box whose
      // top is pinned to the viewport, so it does not scroll unless the header
      // subtracts the travel itself. If that compensation is dropped, the avatar
      // hangs in place while the name slides up under it and this gap collapses.
      await tester.drag(find.byKey(const Key('publicProfileScrollView')), const Offset(0, -60));
      await tester.pumpAndSettle();

      final gapScrolled =
          tester.getRect(nameFinder()).top - tester.getRect(find.byType(PublicProfileAvatar)).top;

      expect(gapScrolled, closeTo(gapAtRest, 1.0),
          reason: 'the avatar must travel with the content, not hover');
    });
  });

  // ── 3. Sliver collapse ──────────────────────────────────────────────────
  group('sliver collapse', () {
    testWidgets('scrolling collapses the header without overflow or exception',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(
          profile: _profileFor('broker'),
          ratings: _ratingsFixture(),
        ),
      );

      final scrollable = find.byKey(const Key('publicProfileScrollView'));
      expect(scrollable, findsOneWidget);

      // Drive past the collapse range (172 - kToolbarHeight) in stages, the way
      // a finger would, checking geometry at each step.
      for (final offset in [40.0, 90.0, 140.0, 240.0, 600.0]) {
        await tester.drag(scrollable, Offset(0, -offset));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'at offset $offset');
        expect(overflowingBoxes(tester), isEmpty, reason: 'at offset $offset');
      }
    });
  });

  // ── 4. Sticky action bar ────────────────────────────────────────────────
  group('sticky action bar', () {
    for (final status in ProfileConnectionStatus.values) {
      testWidgets('renders the $status state without overflow at 320 dp',
          (tester) async {
        tester.view.physicalSize = kSmall;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _hostWidget(
            ProfileStickyActionBar(
              isSelf: false,
              viewerSignedIn: true,
              connectionStatus: status,
              statusLoading: false,
              onShare: () {},
              onMessage: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(overflowingBoxes(tester), isEmpty);
      });
    }

    testWidgets('a self view offers Share and no connect control',
        (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          ProfileStickyActionBar(
            isSelf: true,
            viewerSignedIn: true,
            connectionStatus: ProfileConnectionStatus.none,
            statusLoading: false,
            onShare: () {},
          ),
        ),
      );
      expect(find.text('Share your profile'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('a signed-out viewer is asked to sign in', (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          ProfileStickyActionBar(
            isSelf: false,
            viewerSignedIn: false,
            connectionStatus: ProfileConnectionStatus.none,
            statusLoading: false,
            onShare: () {},
            onSignIn: () {},
          ),
        ),
      );
      expect(find.text('Sign in to connect'), findsOneWidget);
    });
  });

  // ── 5. Locked contact card ──────────────────────────────────────────────
  group('locked contact card', () {
    testWidgets('locked: no phone or email string exists anywhere in the tree',
        (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          ProfileContactCard(
            profile: _profileFor('broker'),
            unlocked: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The blurred plate must be built from empty bars, never from a real value
      // that is merely visually obscured.
      expect(find.textContaining('9876543210'), findsNothing);
      expect(find.textContaining('asha@example.com'), findsNothing);
      expect(find.text('Connect to view contact details'), findsOneWidget);
      // Address stays public even while locked — portal parity.
      expect(find.textContaining('MG Road'), findsOneWidget);
    });

    testWidgets('unlocked: phone, email and address all render', (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          ProfileContactCard(
            profile: _profileFor('broker'),
            unlocked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('9876543210'), findsOneWidget);
      expect(find.textContaining('asha@example.com'), findsOneWidget);
      expect(find.textContaining('MG Road'), findsOneWidget);
    });

    testWidgets('locked card does not overflow at 320 dp', (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _hostWidget(
          ProfileContactCard(profile: _profileFor('broker'), unlocked: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 6. Long names ───────────────────────────────────────────────────────
  group('long names', () {
    testWidgets('a 70-character company name wraps without overflow at 320 dp',
        (tester) async {
      final profile = UserProfile.fromMap({
        'user_id': 'u-1',
        'display_name': 'Aishwarya Radhakrishnan Venkataraman Subramaniam',
        'company_name':
            'Prestige Radhakrishnan Venkataraman Realty Partners & Associates LLP',
        'username': 'aishwaryaradhakrishnanvenkataraman',
        'user_type': 'broker',
        'city': 'Thiruvananthapuram',
        'years_experience': 15,
        'specialization': ['Luxury Residential Redevelopment', 'Commercial Leasing'],
      });

      // Stepped rather than settled: the settled tree is clean, so anything that
      // overflows does so mid-entrance-animation, which still paints Flutter's
      // hatching for those frames.
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
          child: MaterialApp(
            home: PublicProfileScreen(
              userId: 'u-1',
              providerOverride: _provider(profile: profile),
            ),
          ),
        ),
      );

      final seen = <String>{};
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        seen.addAll(overflowingWithCreators(tester));
      }
      await tester.pumpAndSettle();
      seen.addAll(overflowingWithCreators(tester));

      expect(seen, isEmpty, reason: 'transient overflow during entrance');
    });
  });

  // ── 7. Different user roles ─────────────────────────────────────────────
  group('roles', () {
    for (final role in ['builder', 'broker', 'influencer', 'individual']) {
      for (final size in [kSmall, kBaseline, kLarge]) {
        testWidgets('$role renders at ${size.width.toInt()} dp',
            (tester) async {
          await _pumpScreen(
            tester,
            provider: _provider(
              profile: _profileFor(role),
              ratings: _ratingsFixture(),
              connections: 128,
            ),
            size: size,
          );

          expect(tester.takeException(), isNull);
          expect(overflowingBoxes(tester), isEmpty);
        });
      }
    }
  });

  // ── 8. Empty states ─────────────────────────────────────────────────────
  group('empty states', () {
    testWidgets('no listings and no reviews both show their empty state',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('broker', rich: false)),
      );

      // Scrolled before asserting — a habit kept from when this screen was a
      // lazy `CustomScrollView` (sections far below the viewport were not
      // built yet), though it is a plain eagerly-built `Column` now.
      //
      // "No reviews yet" genuinely appears twice at once in this fixture:
      // the identity zone's rating summary shows it in addition to the
      // Reviews section's own empty state, so the assertion below is scoped
      // to the latter specifically — the same disambiguation pattern this
      // file already uses elsewhere (e.g. "the identity text clears the
      // avatar" scopes into `PublicIdentityBlock`) — rather than a bare
      // `find.text`, which is ambiguous between the two.
      expect(find.text('No listings yet'), findsOneWidget);

      await tester.drag(find.byKey(const Key('publicProfileScrollView')), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ProfileReviewsSection),
          matching: find.text('No reviews yet'),
        ),
        findsOneWidget,
      );
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('a builder with no projects says projects, not listings',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(profile: _profileFor('builder', rich: false)),
      );
      expect(find.text('No projects yet'), findsOneWidget);
    });

    testWidgets('a missing profile shows Profile not available', (tester) async {
      await _pumpScreen(tester, provider: _provider(profile: null));
      expect(find.text('Profile not available'), findsOneWidget);
    });

    testWidgets('a content failure shows a retry, not an empty state',
        (tester) async {
      await _pumpScreen(
        tester,
        provider: _provider(
          profile: _profileFor('broker', rich: false),
          failContent: true,
        ),
      );
      expect(find.text('Retry'), findsWidgets);
      expect(find.text('No listings yet'), findsNothing);
    });
  });

  // ── 9. Text scale 130% ──────────────────────────────────────────────────
  group('text scale 130%', () {
    for (final role in ['broker', 'influencer']) {
      testWidgets('$role survives 1.3x at 320 dp', (tester) async {
        await _pumpScreen(
          tester,
          provider: _provider(
            profile: _profileFor(role),
            ratings: _ratingsFixture(),
          ),
          size: kSmall,
          textScale: 1.3,
        );

        expect(overflowingWithCreators(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the sticky bar survives 1.3x at 320 dp', (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _hostWidget(
          ProfileStickyActionBar(
            isSelf: false,
            viewerSignedIn: true,
            connectionStatus: ProfileConnectionStatus.pendingReceived,
            statusLoading: false,
            onShare: () {},
            onMessage: () {},
          ),
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── Stage 2B: reviewer → profile ────────────────────────────────────────
  group('Stage 2B reviewer navigation', () {
    testWidgets('a review card with a resolved author is tappable',
        (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          ReviewCard(
            review: const ProfileReview(
              id: '1',
              rating: 5,
              raterId: 'r-1',
              raterName: 'Ravi Kumar',
              review: 'Excellent throughout.',
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScaleTap), findsOneWidget);
      expect(overflowingWithCreators(tester), isEmpty);
    });

    testWidgets('a card stays inert when no handler is supplied',
        (tester) async {
      await tester.pumpWidget(
        _hostWidget(
          const ReviewCard(
            review: ProfileReview(
              id: '1',
              rating: 5,
              raterId: 'r-1',
              raterName: 'Ravi Kumar',
              review: 'Excellent throughout.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Byte-identical to the pre-Stage-2B card: no gesture is constructed.
      expect(find.byType(ScaleTap), findsNothing);
    });

    testWidgets('an unresolved author gets no tap target', (tester) async {
      // raterId empty — "Anonymous" has no profile to open.
      var tapped = false;
      await tester.pumpWidget(
        _hostWidget(
          ProfileReviewsSection(
            ratings: RatingBreakdown.fromRatings(
              [
                {'id': '1', 'rating': 5, 'rater_id': '', 'review': 'Good'},
              ],
              raterTypes: const {},
              reviews: const [
                ProfileReview(
                  id: '1',
                  rating: 5,
                  raterId: '',
                  raterName: 'Anonymous',
                  review: 'Good',
                ),
              ],
            ),
            isBuilder: false,
            displayName: 'Asha',
            isLoading: false,
            hasFailed: false,
            onRetry: () {},
            onReviewerTap: (_) => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScaleTap), findsNothing);
      expect(tapped, isFalse);
    });

    testWidgets('tapping a resolved author invokes the handler once',
        (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
        _hostWidget(
          ProfileReviewsSection(
            ratings: _ratingsFixture(),
            isBuilder: false,
            displayName: 'Asha',
            isLoading: false,
            hasFailed: false,
            onRetry: () {},
            onReviewerTap: (r) => taps.add(r.raterId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ravi Kumar'));
      await tester.pumpAndSettle();

      expect(taps, ['a']);
    });
  });

  // ── 10. Navigation back stack ───────────────────────────────────────────
  group('back stack', () {
    testWidgets('the back affordance pops exactly one route', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('origin')),
          ),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(
            userId: 'u-1',
            providerOverride: _provider(profile: _profileFor('broker')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('origin'), findsNothing);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('origin'), findsOneWidget);
    });
  });
}
