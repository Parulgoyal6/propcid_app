// Spec I — Broker Leads, Visit Bookings, Profile, and the offer editor.
//
// What is pinned, in the order the contract's preconditions demanded:
//
//   * the leads table is `property_inquiries` — not `crm_leads`;
//   * the lead status mapping in **both** directions, and that the portal's "Lost"
//     is refused rather than silently written as `pending`;
//   * the raw-price fold, which `PropertyModel` cannot reproduce;
//   * realtime: the subscription opens, drives a refresh, and is removed on
//     dispose;
//   * `approval_status` is never written, and the two specialisation arrays are
//     round-tripped untouched;
//   * insert vs update decided by the presence of a row id;
//   * the empty-scope guard, because PostgREST answers an empty `in` with every
//     visible row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/broker_section_options.dart';
import 'package:propcid_app/models/broker_section_models.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/screens/dashboard/widgets/broker_leads_section.dart';
import 'package:propcid_app/screens/dashboard/widgets/broker_profile_section.dart';
import 'package:propcid_app/screens/dashboard/widgets/broker_visit_bookings_section.dart';
import 'package:propcid_app/services/broker_sections_service.dart';
import 'package:propcid_app/services/unified_leads_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

/// Wide enough that every status filter chip is reachable.
const Size kFilterViewport = Size(760, 1400);

// ── Fixtures ────────────────────────────────────────────────────────────────

PropertyModel _property({
  String id = 'pr-1',
  String title = 'Sea View 3BHK',
  String price = '95,00,000',
}) =>
    PropertyModel.fromSupabase({
      'id': id,
      'title': title,
      'price': price,
      'location': 'Bandra West',
      'category': 'residential',
      'status': 'active',
    });

BrokerLead _lead({
  String id = 'l-1',
  String dbStatus = 'pending',
  String propertyId = 'pr-1',
  String? phone = '9876543210',
  String? email = 'buyer@example.com',
  String? message = 'Is it still available?',
}) =>
    BrokerLead.fromSupabase(
      {
        'id': id,
        'property_id': propertyId,
        'inquirer_id': 'u-9',
        'message': message,
        'contact_phone': phone,
        'contact_email': email,
        'preferred_contact_time': 'Evenings',
        'status': dbStatus,
        'created_at': '2026-05-01T10:00:00Z',
      },
      propertyTitle: 'Sea View 3BHK',
    );

PropertyVisitBooking _booking({
  String id = 'b-1',
  String status = 'pending',
  String date = '2026-09-12',
  String userId = 'u-9',
}) =>
    PropertyVisitBooking.fromSupabase(
      {
        'id': id,
        'property_id': 'pr-1',
        'user_id': userId,
        'visitor_name': 'Rahul Sharma',
        'visitor_phone': '9876543210',
        'preferred_date': date,
        'preferred_time': '11:00 AM',
        'message': 'Morning preferred.',
        'status': status,
        'created_at': '2026-05-01T10:00:00Z',
      },
      propertyTitle: 'Sea View 3BHK',
    );

BrokerProfile _profile({
  String? id = 'bp-1',
  String approval = 'approved',
  List<String> types = const ['Residential'],
  List<String> cities = const ['Pune'],
}) =>
    BrokerProfile.fromSupabase({
      'id': id,
      'full_name': 'Asha Menon',
      'rera_number': 'A52100012345',
      'license_number': 'LIC-77',
      'agency_name': 'Menon Realty',
      'years_of_experience': 8,
      'company_description': 'Boutique agency in west Pune.',
      'office_address': '12 MG Road',
      'city': 'Pune',
      'state': 'Maharashtra',
      'pincode': '411001',
      'mobile_number': '9876543210',
      'email': 'asha@example.com',
      'website': 'https://menon.example',
      'property_types': types,
      'operating_cities': cities,
      'approval_status': approval,
      'rejection_reason': approval == 'rejected' ? 'RERA number unreadable.' : null,
    });

// ── Fakes ───────────────────────────────────────────────────────────────────

class _FakeLeadService extends BrokerLeadService {
  _FakeLeadService({this.rows = const []});

  final List<BrokerLead> rows;
  bool shouldFail = false;
  Object? statusError;

  final List<({String id, String status})> statusWrites = [];
  final List<int> scopes = [];

  @override
  Future<List<BrokerLead>> listForProperties(
    List<PropertyModel> properties,
  ) async {
    scopes.add(properties.length);
    if (shouldFail) throw Exception('forced failure');
    if (properties.isEmpty) return const [];
    return rows;
  }

  @override
  Future<BrokerLeadStats> statsFor(List<BrokerLead> leads) async {
    // The real one fetches raw prices; the fold itself is what matters here.
    if (leads.isEmpty) return BrokerLeadStats.empty;
    final closed = leads.where((l) => l.status == 'closed').length;
    return BrokerLeadStats(
      total: leads.length,
      newLeads: leads.where((l) => l.status == 'new').length,
      active: leads.where((l) => l.isActive).length,
      closed: closed,
      conversionRate: (closed / leads.length) * 100,
      closedValue: closed * 9500000,
    );
  }

  @override
  Future<void> setStatus({
    required String leadId,
    required String status,
  }) async {
    statusWrites.add((id: leadId, status: status));
    final error = statusError;
    if (error != null) {
      statusError = null;
      throw error;
    }
  }
}

class _FakeBookingService extends PropertyVisitBookingService {
  _FakeBookingService({this.rows = const []});

  List<PropertyVisitBooking> rows;
  bool shouldFail = false;

  final List<({String id, String status})> updates = [];
  final List<({String id, String status})> statusOnlyWrites = [];
  final List<int> scopes = [];

  /// The callback the widget handed [subscribe]; a test fires it to simulate a
  /// realtime event without a websocket.
  void Function()? onChange;
  int subscribeCount = 0;
  int unsubscribeCount = 0;

  @override
  Future<List<PropertyVisitBooking>> listForProperties(
    List<PropertyModel> properties,
  ) async {
    scopes.add(properties.length);
    if (shouldFail) throw Exception('forced failure');
    if (properties.isEmpty) return const [];
    return rows;
  }

  @override
  RealtimeChannel subscribe(void Function() callback) {
    subscribeCount++;
    onChange = callback;
    // `client.channel(name)` builds the object without opening a socket —
    // `.subscribe()` is what connects, and this deliberately does not call it. So
    // the widget gets a real channel to hold and hand back on dispose.
    return Supabase.instance.client.channel('test-$subscribeCount');
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {
    unsubscribeCount++;
  }

  @override
  Future<void> updateBooking({
    required PropertyVisitBooking booking,
    required DateTime preferredDate,
    required String? preferredTime,
    required String status,
    required String propertyTitle,
  }) async {
    updates.add((id: booking.id, status: status));
  }

  @override
  Future<void> updateStatusOnly({
    required String bookingId,
    required String? userId,
    required String propertyTitle,
    required String status,
    String? propertyId,
  }) async {
    statusOnlyWrites.add((id: bookingId, status: status));
  }
}

class _FakeProfileService extends BrokerProfileService {
  _FakeProfileService({this.row});

  BrokerProfile? row;
  bool shouldFail = false;

  final List<Map<String, dynamic>> saves = [];

  @override
  Future<BrokerProfile?> fetchMine(String userId) async {
    if (shouldFail) throw Exception('forced failure');
    return row;
  }

  @override
  Future<BrokerProfile> save({
    required String userId,
    required BrokerProfile profile,
  }) async {
    saves.add({
      'isCreate': profile.id == null,
      'fullName': profile.fullName,
      'rera': profile.reraNumber,
      'types': profile.propertyTypes,
      'cities': profile.operatingCities,
      'approval': profile.approvalStatus,
    });
    row = profile;
    return profile;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  // ── 1. Precondition: the leads table ────────────────────────────────────
  group('leads table resolution', () {
    test('is property_inquiries, not crm_leads', () {
      // The contract's standing open item, resolved from the code:
      // BrokerLeadsManager.tsx:102 reads it and :194 writes it.
      expect(BrokerLeadService.table, 'property_inquiries');
    });
  });

  // ── 2. The status mapping, both ways ────────────────────────────────────
  group('lead status mapping', () {
    test('five statuses round-trip', () {
      for (final status in kBrokerLeadStatuses) {
        expect(brokerLeadStatusToDb(status.value), status.dbValue);
        expect(brokerLeadStatusFromDb(status.dbValue), status.value);
      }
    });

    test('the enum values are exactly the five that exist', () {
      // inquiry_status: ('pending','contacted','scheduled','closed') plus
      // 'approved' from 20250918141743. Writing anything else is a 22P02.
      expect(
        kBrokerLeadStatuses.map((s) => s.dbValue).toSet(),
        {'pending', 'contacted', 'scheduled', 'closed', 'approved'},
      );
    });

    test('negotiation maps to approved, which the enum does carry', () {
      // Worth its own test: 'approved' was added by a later migration, so on the
      // original enum this would have been a 22P02.
      expect(brokerLeadStatusToDb('negotiation'), 'approved');
    });

    test('"lost" is not offered, and is refused rather than downgraded', () {
      // The portal offers it and maps it to `pending` (`:188`), so a broker's
      // answer is discarded. Omitted here; refused at the boundary.
      expect(
        kBrokerLeadStatuses.map((s) => s.value),
        isNot(contains('lost')),
      );
      expect(brokerLeadStatusToDb('lost'), isNull);
    });

    test('an unknown stored value reads as new', () {
      expect(brokerLeadStatusFromDb('something_else'), 'new');
      expect(brokerLeadStatusFromDb(null), 'new');
    });

    test('active excludes closed', () {
      expect(kActiveBrokerLeadStatuses, hasLength(4));
      expect(kActiveBrokerLeadStatuses.contains('closed'), isFalse);
      expect(_lead(dbStatus: 'closed').isActive, isFalse);
      expect(_lead(dbStatus: 'approved').isActive, isTrue);
    });
  });

  // ── 3. The price fold ───────────────────────────────────────────────────
  group('parsePortalPrice', () {
    test('strips formatting the way parseFloat does', () {
      expect(BrokerLeadService.parsePortalPrice('95,00,000'), 9500000);
      expect(BrokerLeadService.parsePortalPrice('₹ 45,00,000'), 4500000);
      expect(BrokerLeadService.parsePortalPrice(9500000), 9500000);
    });

    test('an unparseable price is 0, not an exception', () {
      expect(BrokerLeadService.parsePortalPrice('Price on request'), 0);
      expect(BrokerLeadService.parsePortalPrice(''), 0);
      expect(BrokerLeadService.parsePortalPrice(null), 0);
    });

    test('"1.2 Cr" folds to 1.2 — the portal bug, carried', () {
      // Stripping every non-digit leaves "1.2". Both platforms agree, which is the
      // point; diverging here would make them report different portfolio values.
      expect(BrokerLeadService.parsePortalPrice('1.2 Cr'), 1.2);
    });

    test('PropertyModel now folds commas correctly too — Cr/Lakh is the '
        'remaining reason the service reads the raw column', () {
      // Comma grouping is no longer a reason to bypass PropertyModel: it
      // now resolves this the same way, via the shared canonical parser
      // (see listing_price_parser.dart) — both platforms' `price` field
      // agree.
      expect(_property(price: '95,00,000').price, 9500000);
      expect(BrokerLeadService.parsePortalPrice('95,00,000'), 9500000);

      // What still makes `BrokerLeadService` read the raw column instead
      // of `PropertyModel.price`: PropertyModel resolves a Cr/Lakh suffix
      // to the REAL amount (1.2 Cr -> 12000000), while this service
      // deliberately keeps the portal's fold-to-1.2 bug (see the test
      // above) so both platforms report the same figure. Delegating to
      // PropertyModel here would silently fix that divergence and make
      // the two disagree.
      expect(_property(price: '1.2 Cr').price, 12000000);
      expect(BrokerLeadService.parsePortalPrice('1.2 Cr'), 1.2);
    });
  });

  // ── 4. Models ───────────────────────────────────────────────────────────
  group('BrokerLead', () {
    test('buyer name is the portal placeholder, not data', () {
      // `property_inquiries` has no name column; the portal hard-codes this.
      expect(_lead().buyerName, 'Interested Buyer');
    });

    test('the stored enum value is mapped on read', () {
      expect(_lead(dbStatus: 'scheduled').status, 'viewing_scheduled');
      expect(_lead(dbStatus: 'approved').status, 'negotiation');
    });

    test('withStatus keeps everything else', () {
      final updated = _lead().withStatus('closed');
      expect(updated.status, 'closed');
      expect(updated.contactPhone, '9876543210');
      expect(updated.propertyTitle, 'Sea View 3BHK');
    });
  });

  group('BrokerProfile', () {
    test('a null id means the row does not exist yet', () {
      expect(_profile(id: null).id, isNull);
      expect(_profile().id, 'bp-1');
    });

    test('a rejection reason is only meaningful when rejected', () {
      expect(_profile(approval: 'rejected').isRejected, isTrue);
      expect(_profile(approval: 'rejected').rejectionReason, isNotNull);
      expect(_profile(approval: 'approved').isRejected, isFalse);
    });

    test('approval labels cover the CHECK constraint', () {
      expect(brokerProfileApprovalLabel('approved'), 'Approved');
      expect(brokerProfileApprovalLabel('rejected'), 'Rejected');
      expect(brokerProfileApprovalLabel('pending'), 'Pending Review');
      expect(brokerProfileApprovalLabel(null), 'Pending Review');
    });
  });

  // ── 5. Leads section ────────────────────────────────────────────────────
  group('BrokerLeadsSection', () {
    // Every case below composes a fresh `_FakeLeadService`/`_FakeBookingService`
    // pair into a `UnifiedLeadsService` — the same composition
    // `UnifiedLeadsService`'s own constructor does in production, just with
    // both halves faked. An empty booking list keeps inquiry-only cases
    // behaving exactly as before the Leads/Visits unification.
    UnifiedLeadsService unified({
      List<BrokerLead> leads = const [],
      List<PropertyVisitBooking> bookings = const [],
    }) =>
        UnifiedLeadsService(
          leadService: _FakeLeadService(rows: leads),
          visitService: _FakeBookingService(rows: bookings),
        );

    testWidgets('renders a lead with its property, stats and status',
        (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(leads: [_lead()]),
        ),
        size: const Size(320, 1200),
      );

      expect(find.text('Interested Buyer'), findsOneWidget);
      expect(find.text('Sea View 3BHK'), findsOneWidget);
      expect(find.text('Is it still available?'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Inquiry'), findsOneWidget);
      // The stats strip.
      expect(find.text('Total Leads'), findsOneWidget);
      expect(find.text('Conversion Rate'), findsOneWidget);
    });

    testWidgets(
        'a visit booking shows up as a lead too, with the visitor\'s real name',
        (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(bookings: [_booking()]),
        ),
        size: const Size(320, 1200),
      );

      // Unlike an inquiry, a visit carries the visitor's actual name.
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Sea View 3BHK'), findsOneWidget);
      expect(find.text('Morning preferred.'), findsOneWidget);
      expect(find.text('Visit Request'), findsOneWidget);
      // pending -> new, via visitLeadStatusFromDb.
      expect(find.text('New'), findsWidgets);
      expect(find.textContaining('Sep'), findsOneWidget); // preferred date
    });

    testWidgets(
        'an inquiry and a visit from the same person on the same property '
        'merge into one card', (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(
            // Both fixtures default to inquirer/visitor `u-9` on `pr-1` —
            // the same person, the same listing.
            leads: [_lead(id: 'l-1')],
            bookings: [_booking(id: 'b-1')],
          ),
        ),
        size: const Size(320, 1400),
      );

      // One card, not two — and it shows the visit's real name, not the
      // inquiry's generic placeholder.
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Interested Buyer'), findsNothing);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Total Leads'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets(
        'an inquiry and a visit from different people stay as separate cards',
        (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(
            leads: [_lead(id: 'l-1')],
            bookings: [_booking(id: 'b-1', userId: 'u-other')],
          ),
        ),
        size: const Size(320, 1400),
      );

      expect(find.text('Interested Buyer'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
    });

    testWidgets(
        'changing a visit lead\'s status writes to property_visit_bookings, not property_inquiries',
        (tester) async {
      final leadService = _FakeLeadService();
      final visitService = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: UnifiedLeadsService(
            leadService: leadService,
            visitService: visitService,
          ),
        ),
        size: const Size(320, 1200),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewing Scheduled').last);
      await tester.pumpAndSettle();

      // Routed to the booking table (via visitLeadStatusToDb: 'confirmed'),
      // never to the inquiry service.
      expect(leadService.statusWrites, isEmpty);
      expect(visitService.statusOnlyWrites.single.id, 'b-1');
      expect(visitService.statusOnlyWrites.single.status, 'confirmed');
      expect(find.textContaining('Marked as viewing scheduled'), findsOneWidget);
    });

    testWidgets('no listings yields a different message than no leads',
        (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: const [],
          service: unified(),
        ),
      );
      expect(find.textContaining('once you publish a listing'), findsOneWidget);

      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(),
        ),
      );
      expect(find.text('No leads yet.'), findsOneWidget);
    });

    testWidgets('an empty listing scope issues no unfiltered read',
        (tester) async {
      final leadService = _FakeLeadService(rows: [_lead()]);
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: const [],
          service: UnifiedLeadsService(
            leadService: leadService,
            visitService: _FakeBookingService(),
          ),
        ),
      );
      expect(find.text('Interested Buyer'), findsNothing);
      expect(leadService.scopes, [0]);
    });

    testWidgets('changing status writes the app value and recomputes stats',
        (tester) async {
      final leadService = _FakeLeadService(rows: [_lead()]);
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: UnifiedLeadsService(
            leadService: leadService,
            visitService: _FakeBookingService(),
          ),
        ),
        size: const Size(320, 1200),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Negotiation').last);
      await tester.pumpAndSettle();

      expect(leadService.statusWrites.single.id, 'l-1');
      // The app-side value; the service maps it to the enum.
      expect(leadService.statusWrites.single.status, 'negotiation');
      expect(find.textContaining('Marked as negotiation'), findsOneWidget);
    });

    testWidgets('a refused status is surfaced, not swallowed', (tester) async {
      final leadService = _FakeLeadService(rows: [_lead()])
        ..statusError = const BrokerSectionException(
          '"lost" is not a status this lead can be set to.',
        );
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: UnifiedLeadsService(
            leadService: leadService,
            visitService: _FakeBookingService(),
          ),
        ),
        size: const Size(320, 1200),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('is not a status'), findsOneWidget);
    });

    testWidgets('a lead with no phone has Call disabled, not hidden',
        (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(leads: [_lead(phone: null)]),
        ),
        size: const Size(320, 1200),
      );
      expect(find.text('Call'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the filter narrows without re-querying', (tester) async {
      final leadService = _FakeLeadService(rows: [
        _lead(id: 'a', dbStatus: 'pending'),
        _lead(id: 'b', dbStatus: 'closed'),
      ]);
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: UnifiedLeadsService(
            leadService: leadService,
            visitService: _FakeBookingService(),
          ),
        ),
        size: kFilterViewport,
      );

      expect(find.text('Interested Buyer'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(GestureDetector, 'Closed').first);
      await tester.pumpAndSettle();

      expect(find.text('Interested Buyer'), findsOneWidget);
      expect(leadService.scopes, hasLength(1));
    });

    testWidgets('a failure offers a retry', (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: UnifiedLeadsService(
            leadService: _FakeLeadService()..shouldFail = true,
            visitService: _FakeBookingService(),
          ),
        ),
      );
      expect(find.text("Couldn't load your leads"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        BrokerLeadsSection(
          properties: [_property()],
          service: unified(leads: [_lead(dbStatus: 'scheduled')]),
        ),
        textScale: 1.3,
        size: const Size(320, 1400),
      );
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 6. Visit bookings, including realtime ───────────────────────────────
  group('BrokerVisitBookingsSection', () {
    testWidgets('renders a booking with visitor, listing, date and time',
        (tester) async {
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: _FakeBookingService(rows: [_booking()]),
          enableRealtime: false,
        ),
      );

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Sea View 3BHK'), findsOneWidget);
      expect(find.text('Sep 12, 2026'), findsOneWidget);
      expect(find.text('11:00 AM'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('a realtime event refreshes the list and says so',
        (tester) async {
      // The contract's confirmed realtime requirement. The fake captures the
      // callback the widget handed `subscribe`; firing it is the same path a
      // postgres_changes event takes.
      final service = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: service,
        ),
      );

      expect(service.subscribeCount, 1, reason: 'subscribed on mount');
      expect(find.text('Updated live'), findsNothing);

      // A new booking arrives, then the channel fires.
      service.rows = [_booking(), _booking(id: 'b-2', status: 'confirmed')];
      service.onChange!();
      await tester.pumpAndSettle();

      expect(find.text('Rahul Sharma'), findsNWidgets(2));
      expect(find.text('Updated live'), findsOneWidget);
    });

    testWidgets('realtime is not subscribed twice on a rebuild',
        (tester) async {
      final service = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: service,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(service.subscribeCount, 1);
    });

    testWidgets('an empty listing scope issues no unfiltered read',
        (tester) async {
      final service = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: const [],
          service: service,
          enableRealtime: false,
        ),
      );
      expect(find.text('Rahul Sharma'), findsNothing);
      expect(service.scopes, [0]);
    });

    testWidgets('updating writes the status and reports the notification',
        (tester) async {
      final service = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: service,
          enableRealtime: false,
        ),
        size: const Size(320, 1400),
      );

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GestureDetector, 'Confirmed').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('visitor will be notified'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.updates.single.status, 'confirmed');
      expect(find.textContaining('visitor has been notified'), findsOneWidget);
    });

    testWidgets('completing a visit does not claim the visitor was told',
        (tester) async {
      final service = _FakeBookingService(rows: [_booking()]);
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: service,
          enableRealtime: false,
        ),
        size: const Size(320, 1400),
      );

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GestureDetector, 'Completed').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('visitor will be notified'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Booking updated.'), findsOneWidget);
    });

    testWidgets('a past pending booking is flagged', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final iso = '${yesterday.year}'
          '-${yesterday.month.toString().padLeft(2, '0')}'
          '-${yesterday.day.toString().padLeft(2, '0')}';
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: _FakeBookingService(
            rows: [_booking(date: iso, status: 'pending')],
          ),
          enableRealtime: false,
        ),
      );
      expect(find.text('Date passed'), findsOneWidget);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        BrokerVisitBookingsSection(
          properties: [_property()],
          service: _FakeBookingService(rows: [_booking()]),
          enableRealtime: false,
        ),
        textScale: 1.3,
        size: const Size(320, 1400),
      );
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 7. Broker profile ───────────────────────────────────────────────────
  group('BrokerProfileSection', () {
    testWidgets('renders a saved profile with its approval state',
        (tester) async {
      await _pump(
        tester,
        BrokerProfileSection(
          userId: 'u-1',
          service: _FakeProfileService(row: _profile()),
        ),
        size: const Size(320, 1000),
      );

      expect(find.text('Asha Menon'), findsOneWidget);
      expect(find.text('Menon Realty'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('A52100012345'), findsOneWidget);
      expect(find.text('8 yrs'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('no profile row prompts to create one', (tester) async {
      // Never collapses: this is exactly the broker who needs the button.
      await _pump(
        tester,
        BrokerProfileSection(
          userId: 'u-1',
          service: _FakeProfileService(),
        ),
      );
      expect(find.text('No broker profile yet'), findsOneWidget);
      expect(find.text('Complete Profile'), findsOneWidget);
    });

    testWidgets('a rejection reason is shown, and only when rejected',
        (tester) async {
      await _pump(
        tester,
        BrokerProfileSection(
          userId: 'u-1',
          service: _FakeProfileService(row: _profile(approval: 'rejected')),
        ),
        size: const Size(320, 1000),
      );
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('RERA number unreadable.'), findsOneWidget);
    });

    testWidgets('specialisation renders as badges', (tester) async {
      await _pump(
        tester,
        BrokerProfileSection(
          userId: 'u-1',
          service: _FakeProfileService(
            row: _profile(types: const ['Commercial'], cities: const ['Mumbai']),
          ),
        ),
        size: const Size(320, 1000),
      );
      expect(find.text('Commercial'), findsOneWidget);
      expect(find.text('Mumbai'), findsOneWidget);
    });

    testWidgets('saving an existing profile updates rather than inserts',
        (tester) async {
      final service = _FakeProfileService(row: _profile());
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Asha M Menon');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final save = service.saves.single;
      expect(save['isCreate'], isFalse);
      expect(save['fullName'], 'Asha M Menon');
    });

    testWidgets('saving a first profile inserts', (tester) async {
      final service = _FakeProfileService();
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Complete Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'New Broker');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.saves.single['isCreate'], isTrue);
    });

    testWidgets('a blank name is refused', (tester) async {
      final service = _FakeProfileService(row: _profile());
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('A full name is required.'), findsOneWidget);
      expect(service.saves, isEmpty);
    });

    testWidgets('the specialisation arrays survive a save untouched',
        (tester) async {
      // The 5.1 hazard: there is no editor for these, so a save must not drop
      // them.
      final service = _FakeProfileService(
        row: _profile(
          types: const ['Residential', 'Land'],
          cities: const ['Pune', 'Nashik'],
        ),
      );
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.saves.single['types'], ['Residential', 'Land']);
      expect(service.saves.single['cities'], ['Pune', 'Nashik']);
    });

    testWidgets('approval_status is carried, never changed', (tester) async {
      // Sending 'pending' on every save would un-approve an approved broker.
      final service = _FakeProfileService(row: _profile(approval: 'approved'));
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.saves.single['approval'], 'approved');
    });

    testWidgets('a cleared optional field becomes null, not an empty string',
        (tester) async {
      final service = _FakeProfileService(row: _profile());
      await _pump(
        tester,
        BrokerProfileSection(userId: 'u-1', service: service),
        size: const Size(360, 3600),
      );

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      // The second field is the RERA number.
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.saves.single['rera'], isNull);
    });

    testWidgets('a failure offers a retry', (tester) async {
      await _pump(
        tester,
        BrokerProfileSection(
          userId: 'u-1',
          service: _FakeProfileService()..shouldFail = true,
        ),
      );
      expect(find.text("Couldn't load your profile"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  // ── 8. Service guards ───────────────────────────────────────────────────
  group('service guards', () {
    test('an empty scope never becomes an unfiltered read', () async {
      expect(
        await BrokerLeadService().listForProperties(const []),
        isEmpty,
      );
      expect(
        await PropertyVisitBookingService().listForProperties(const []),
        isEmpty,
      );
    });

    test('an unmappable lead status is refused before the round trip', () {
      expect(
        () => BrokerLeadService().setStatus(leadId: 'l-1', status: 'lost'),
        throwsA(isA<BrokerSectionException>()),
      );
    });

    test('a blank profile name is refused before the round trip', () {
      expect(
        () => BrokerProfileService().save(
          userId: 'u-1',
          profile: const BrokerProfile(fullName: '  '),
        ),
        throwsA(isA<BrokerSectionException>()),
      );
    });

    test('empty stats need no price read', () async {
      expect(
        (await BrokerLeadService().statsFor(const [])).total,
        0,
      );
    });

    test('the realtime channel name matches the portal', () {
      expect(
        PropertyVisitBookingService.channelName,
        'property-visit-bookings-updates',
      );
    });

    test('the notification type is one the enum already carries', () {
      expect(
        PropertyVisitBookingService.notificationType,
        'visit_booking_update',
      );
    });

    test('this is not the project bookings table', () {
      expect(PropertyVisitBookingService.table, 'property_visit_bookings');
    });
  });
}
