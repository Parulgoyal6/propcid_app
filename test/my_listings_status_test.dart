// Spec D — the listing card's status picker and its View action.
//
// The website reference is `BrokerContentManager.tsx`. What is pinned:
//
//   * the picker's vocabulary — `active` and `sold` only, even though the column
//     CHECK accepts four values (BrokerContentManager.tsx:340-346);
//   * the two statuses the owner never set staying read-only, which is where a
//     DropdownButton would have asserted and where the website silently renders
//     an empty Select;
//   * the write being non-optimistic — the card recolours after the write
//     returns, never before;
//   * View navigating, because it shipped as a no-op `onTap: () {}`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/constants/property_status_options.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/screens/dashboard/my_listings_section.dart';
import 'package:propcid_app/services/property_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

PropertyModel _listing({
  String id = 'l-1',
  String title = 'Sea View 3BHK',
  String? status = 'active',
}) =>
    PropertyModel.fromSupabase({
      'id': id,
      'title': title,
      'price': '95,00,000',
      'location': 'Bandra West, Mumbai',
      'category': 'residential',
      'status': status,
      'created_at': '2026-05-01T10:00:00Z',
    });

/// Records every write and can stall or fail the status update on demand.
class _FakePropertyService extends PropertyService {
  _FakePropertyService({this.rows = const []});

  final List<PropertyModel> rows;

  final List<({String id, String status})> statusWrites = [];
  final List<String> deletes = [];

  /// When set, `setPropertyStatus` blocks on this instead of returning.
  Completer<void>? gate;

  bool shouldFail = false;

  @override
  Future<List<PropertyModel>> getPropertiesByUser(String userId) async => rows;

  @override
  Future<void> setPropertyStatus(String propertyId, String status) async {
    statusWrites.add((id: propertyId, status: status));
    if (shouldFail) {
      shouldFail = false;
      throw Exception('rejected');
    }
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
  }

  @override
  Future<void> deleteProperty(String propertyId) async {
    deletes.add(propertyId);
  }
}

/// Pumps the section, recording every named push.
Future<List<RouteSettings>> _pump(
  WidgetTester tester,
  _FakePropertyService service, {
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MyListingsSection(
            userId: 'u-1',
            serviceOverride: service,
          ),
        ),
      ),
      onGenerateRoute: (settings) {
        pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // PropertyService's constructor resolves Supabase.instance.client, and the
    // fake subclasses it. Loopback URL, no refresh — nothing touches the network.
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

  // ── 1. The vocabulary ───────────────────────────────────────────────────
  group('status vocabulary', () {
    test('the picker offers exactly what the website offers', () {
      // BrokerContentManager.tsx:342-345. The CHECK allows four values; the
      // dashboard exposes two.
      expect(
        propertyStatusOptions.map((o) => o.value).toList(),
        ['active', 'sold'],
      );
    });

    test('every CHECK value still reads correctly on a card', () {
      // `rented` used to fall through to the amber "Pending" case.
      expect(propertyStatusLabel('active'), 'Active');
      expect(propertyStatusLabel('sold'), 'Sold');
      expect(propertyStatusLabel('inactive'), 'Inactive');
      expect(propertyStatusLabel('rented'), 'Rented');
    });

    test('an unknown status reads as pending, not as blank', () {
      expect(propertyStatusLabel(null), 'Pending');
      expect(propertyStatusLabel('something_new'), 'Pending');
    });

    test('only the two settable statuses are settable', () {
      expect(isOwnerSettableStatus('active'), isTrue);
      expect(isOwnerSettableStatus('sold'), isTrue);
      expect(isOwnerSettableStatus('inactive'), isFalse);
      expect(isOwnerSettableStatus('rented'), isFalse);
      expect(isOwnerSettableStatus(null), isFalse);
    });
  });

  // ── 2. The picker ───────────────────────────────────────────────────────
  group('status picker', () {
    testWidgets('an active listing gets a picker, not a label', (tester) async {
      final service = _FakePropertyService(rows: [_listing()]);
      await _pump(tester, service);

      expect(find.text('Active'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('choosing Sold writes it and recolours the card',
        (tester) async {
      final service = _FakePropertyService(rows: [_listing()]);
      await _pump(tester, service);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      // Two menu entries, plus the closed badge still reading "Active".
      expect(find.text('Sold'), findsOneWidget);

      await tester.tap(find.text('Sold'));
      await tester.pumpAndSettle();

      expect(service.statusWrites.single.id, 'l-1');
      expect(service.statusWrites.single.status, 'sold');
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
      expect(find.text('Marked as sold.'), findsOneWidget);
    });

    testWidgets('re-picking the current status writes nothing', (tester) async {
      final service = _FakePropertyService(rows: [_listing()]);
      await _pump(tester, service);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();

      expect(service.statusWrites, isEmpty,
          reason: 'a no-op write would still bump updated_at');
    });

    testWidgets('a rejected write leaves the old status on the card',
        (tester) async {
      final service = _FakePropertyService(rows: [_listing()])
        ..shouldFail = true;
      await _pump(tester, service);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sold'));
      await tester.pumpAndSettle();

      expect(service.statusWrites, hasLength(1));
      expect(find.text('Active'), findsOneWidget,
          reason: 'the card must not claim a status the database rejected');
      expect(find.textContaining('Could not update status'), findsOneWidget);
    });

    testWidgets('the picker is inert while its write is in flight',
        (tester) async {
      final service = _FakePropertyService(rows: [_listing()]);
      final gate = Completer<void>();
      service.gate = gate;
      await _pump(tester, service);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sold'));
      await tester.pump();

      // Asserted on the button rather than by tapping it again: the menu route
      // is still animating out at this point, so its items are legitimately
      // still mounted and a findsNothing would be testing the animation.
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(service.statusWrites, hasLength(1));
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isTrue,
      );
    });

    testWidgets('an inactive listing keeps a read-only badge', (tester) async {
      // A two-item picker here would make Active the only way out of a state the
      // owner did not choose.
      final service = _FakePropertyService(
        rows: [_listing(status: 'inactive')],
      );
      await _pump(tester, service);

      expect(find.text('Inactive'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('a rented listing keeps a read-only badge', (tester) async {
      final service = _FakePropertyService(rows: [_listing(status: 'rented')]);
      await _pump(tester, service);

      expect(find.text('Rented'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('only the tapped card changes', (tester) async {
      final service = _FakePropertyService(rows: [
        _listing(id: 'l-1', title: 'First'),
        _listing(id: 'l-2', title: 'Second'),
      ]);
      await _pump(tester, service);

      expect(find.text('Active'), findsNWidgets(2));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sold'));
      await tester.pumpAndSettle();

      expect(service.statusWrites.single.id, 'l-1');
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });
  });

  // ── 3. View ─────────────────────────────────────────────────────────────
  group('view action', () {
    testWidgets('View opens the listing instead of doing nothing',
        (tester) async {
      final service = _FakePropertyService(rows: [_listing()]);
      final pushed = await _pump(tester, service);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.propertyDetailScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['propertyId'],
        'l-1',
      );
    });

    testWidgets('Delete still confirms before deleting', (tester) async {
      // The action row gained a live sibling; the destructive one must be
      // unchanged.
      final service = _FakePropertyService(rows: [_listing()]);
      await _pump(tester, service);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Property'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.deletes, isEmpty);
    });
  });

  // ── 4. Layout ───────────────────────────────────────────────────────────
  group('layout', () {
    testWidgets('the header row fits at 320 dp and 130% text', (tester) async {
      // The badge became a badge plus a caret, in a Row that already held the
      // category chip.
      final service = _FakePropertyService(
        rows: [_listing(title: 'Spacious sea-facing 3BHK with two balconies')],
      );
      await _pump(tester, service, textScale: 1.3);

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long category does not squeeze the picker out',
        (tester) async {
      final service = _FakePropertyService(
        rows: [
          PropertyModel.fromSupabase({
            'id': 'l-1',
            'title': 'Warehouse',
            'price': '2,50,00,000',
            'location': 'Bhiwandi',
            'category': 'commercial_industrial_warehouse',
            'status': 'active',
          }),
        ],
      );
      await _pump(tester, service, textScale: 1.3);

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });
  });
}
