// Home upgrade — the four new sections' rules and math.
//
// What is pinned here is what silently breaks without being obvious on screen:
//
//   * the area and stamp-duty tables, which must equal the portal's to the last
//     digit or the two products quote different numbers for the same input;
//   * the UPID / address exclusivity, which writes a wrong row rather than
//     failing loudly if it drifts;
//   * the OTP submit gate, which is a hard business rule from the web version;
//   * `NewsSection` rendering *nothing* when there is no news, so the Home feed
//     does not grow a hole.
//
// Every reference line number below was read from the reference repo at
// `c:\Users\USER\Desktop\Flutter\propcid`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/news_item_model.dart';
import 'package:propcid_app/screens/home/widgets/news_section.dart';
import 'package:propcid_app/screens/home/widgets/smart_tools_section.dart';
import 'package:propcid_app/services/news_service.dart';
import 'package:propcid_app/services/property_verification_service.dart';
import 'package:propcid_app/services/requirement_service.dart';
import 'package:propcid_app/widgets/area_converter_sheet.dart';
import 'package:propcid_app/widgets/property_verification_sheet.dart'
    show canSubmitVerification, PropertyVerificationSheet;
import 'package:propcid_app/widgets/stamp_duty_calculator_sheet.dart';

import 'support/overflow_detector.dart';

/// The narrowest phone the app supports, where the new rails are tightest.
const Size kSmall = Size(320, 720);

/// Replays a scripted result without touching Supabase.
class _FakeNewsService extends NewsService {
  _FakeNewsService({
    this.items = const [],
    this.shouldFail = false,
    this.gate,
  });

  final List<NewsItemModel> items;
  final bool shouldFail;

  /// When supplied, `listActive` blocks on this instead of returning — the only
  /// way to observe the frame before the fetch resolves.
  final Completer<List<NewsItemModel>>? gate;

  int calls = 0;

  @override
  Future<List<NewsItemModel>> listActive() {
    calls++;
    if (shouldFail) return Future.error(Exception('forced failure'));
    final pending = gate;
    if (pending != null) return pending.future;
    return Future.value(items);
  }
}

NewsItemModel _news({
  String id = 'n-1',
  String title = 'Housing prices climb in Pune',
  String? summary,
  String? imageUrl,
  String? videoUrl,
  String? linkUrl,
  String? source,
}) {
  return NewsItemModel.fromSupabase(<String, dynamic>{
    'id': id,
    'title': title,
    'summary': summary,
    'image_url': imageUrl,
    'video_url': videoUrl,
    'link_url': linkUrl,
    'source': source,
    'display_order': 0,
    'published_at': '2026-08-01T10:00:00Z',
  });
}

Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Pumps a widget whose only job is to open [open] when tapped, then opens it.
Future<void> _pumpSheet(
  WidgetTester tester,
  Future<void> Function(BuildContext) open, {
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // `_FakeNewsService` subclasses a real service whose constructor resolves
    // `Supabase.instance.client`, so a client must exist. Loopback URL, no token
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

  // ── 1. Area conversion table ───────────────────────────────────────────
  group('area conversions', () {
    test('every unit converts to itself as exactly 1', () {
      for (final unit in kAreaUnitLabels.keys) {
        expect(kAreaConversions[unit]![unit], 1,
            reason: '$unit → $unit must be identity');
      }
    });

    test('the table is complete — 5 units, every pair present', () {
      expect(kAreaUnitLabels.length, 5);
      for (final from in kAreaUnitLabels.keys) {
        for (final to in kAreaUnitLabels.keys) {
          expect(kAreaConversions[from]?[to], isNotNull,
              reason: 'missing $from → $to');
        }
      }
    });

    test('factors are the portal\'s, digit for digit', () {
      // UnitConverter.tsx:10-14. Deliberately the portal's rounded values, not
      // the exact definitions — 1/9 is 0.111111… and the reference truncates.
      expect(kAreaConversions['sq_ft']!['sq_mtr'], 0.092903);
      expect(kAreaConversions['sq_ft']!['sq_yards'], 0.111111);
      expect(kAreaConversions['sq_ft']!['acres'], 0.000022957);
      expect(kAreaConversions['sq_ft']!['hectares'], 0.0000092903);
      expect(kAreaConversions['sq_mtr']!['sq_ft'], 10.7639);
      expect(kAreaConversions['sq_yards']!['sq_ft'], 9);
      expect(kAreaConversions['acres']!['sq_ft'], 43560);
      expect(kAreaConversions['acres']!['sq_yards'], 4840);
      expect(kAreaConversions['hectares']!['sq_mtr'], 10000);
      expect(kAreaConversions['hectares']!['acres'], 2.47105);
    });

    test('100 sq ft is 9.2903 sq m at the portal\'s 4 decimal places', () {
      final result =
          (100 * kAreaConversions['sq_ft']!['sq_mtr']!).toStringAsFixed(4);
      expect(result, '9.2903');
    });

    test('1 acre is 43560.0000 sq ft', () {
      expect((1 * kAreaConversions['acres']!['sq_ft']!).toStringAsFixed(4),
          '43560.0000');
    });
  });

  // ── 2. Stamp duty table ────────────────────────────────────────────────
  group('stamp duty', () {
    test('all ten states carry both rates', () {
      // StampDutyCalculator.tsx:8-19.
      expect(kStampDutyRates.length, 10);
      expect(kStampDutyStateLabels.length, 10);
      for (final state in kStampDutyRates.keys) {
        expect(kStampDutyRates[state]!['male'], isNotNull);
        expect(kStampDutyRates[state]!['female'], isNotNull);
        expect(kStampDutyStateLabels[state], isNotNull,
            reason: '$state has no label');
      }
    });

    test('rates are the portal\'s', () {
      expect(kStampDutyRates['maharashtra'], {'male': 6.0, 'female': 5.0});
      expect(kStampDutyRates['delhi'], {'male': 6.0, 'female': 4.0});
      expect(kStampDutyRates['karnataka'], {'male': 5.6, 'female': 5.6});
      expect(kStampDutyRates['tamil_nadu'], {'male': 7.0, 'female': 7.0});
      expect(kStampDutyRates['gujarat'], {'male': 4.9, 'female': 4.9});
      expect(kStampDutyRates['uttar_pradesh'], {'male': 7.0, 'female': 6.0});
    });

    test('registration is a flat 1%', () {
      // StampDutyCalculator.tsx:51 — `value * 0.01`.
      expect(kRegistrationRate, 0.01);
      expect(5000000 * kRegistrationRate, 50000);
    });

    test('several states charge women less, which changes the total', () {
      // The whole point of the buyer toggle. Maharashtra: 6% vs 5%.
      final male = 5000000 * kStampDutyRates['maharashtra']!['male']! / 100;
      final female = 5000000 * kStampDutyRates['maharashtra']!['female']! / 100;
      expect(male, 300000);
      expect(female, 250000);
    });
  });

  // ── 3. Stamp duty sheet — live recalculation ───────────────────────────
  group('stamp duty sheet', () {
    testWidgets('opens on the portal\'s defaults and shows the total',
        (tester) async {
      await _pumpSheet(tester, showStampDutyCalculatorSheet);

      // ₹50,00,000 in Maharashtra for a male buyer: 6% = 3,00,000 duty plus
      // 1% = 50,000 registration → 3,50,000, written in lakhs.
      expect(find.text('₹3.50 L'), findsOneWidget);
      expect(find.text('Stamp Duty (6%)'), findsOneWidget);
      expect(find.text('Registration (1%)'), findsOneWidget);
      expect(find.text('₹3.00 L'), findsOneWidget);
      expect(find.text('₹50000'), findsOneWidget);
    });

    testWidgets('switching the buyer recalculates live, with no submit button',
        (tester) async {
      await _pumpSheet(tester, showStampDutyCalculatorSheet);

      await tester.tap(find.text('Female'));
      await tester.pumpAndSettle();

      // 5% + 1% of 50,00,000 = 3,00,000.
      expect(find.text('₹3.00 L'), findsOneWidget);
      expect(find.text('Stamp Duty (5%)'), findsOneWidget);
    });

    testWidgets('a fractional rate keeps its decimal in the label',
        (tester) async {
      await _pumpSheet(tester, showStampDutyCalculatorSheet);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Karnataka').last);
      await tester.pumpAndSettle();

      expect(find.text('Stamp Duty (5.6%)'), findsOneWidget);
    });

    testWidgets('an empty value zeroes the figures rather than erroring',
        (tester) async {
      await _pumpSheet(tester, showStampDutyCalculatorSheet);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('₹0'), findsWidgets);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pumpSheet(tester, showStampDutyCalculatorSheet, textScale: 1.3);
      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 4. Area converter sheet ────────────────────────────────────────────
  group('area converter sheet', () {
    testWidgets('shows no result until a value is entered', (tester) async {
      await _pumpSheet(tester, showAreaConverterSheet);

      expect(find.text('—'), findsOneWidget);
      // The formula line is conditional on a value, like the portal's.
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('converts at the portal\'s 4 decimal places', (tester) async {
      await _pumpSheet(tester, showAreaConverterSheet);

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pumpAndSettle();

      expect(find.text('9.2903'), findsOneWidget);
      expect(find.textContaining('Square Feet'), findsWidgets);
    });

    testWidgets('the swap button exchanges the two units', (tester) async {
      await _pumpSheet(tester, showAreaConverterSheet);

      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pumpAndSettle();
      // 1 sq ft → 0.0929 sq m.
      expect(find.text('0.0929'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.pumpAndSettle();

      // Now 1 sq m → 10.7639 sq ft.
      expect(find.text('10.7639'), findsOneWidget);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pumpSheet(tester, showAreaConverterSheet, textScale: 1.3);
      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 5. The OTP gate ───────────────────────────────────────────────────
  group('verification submit gate', () {
    test('an unverified phone blocks submission however complete the form is',
        () {
      // PropertyVerificationModal.tsx:231-238. This is the hard rule.
      expect(
        canSubmitVerification(
          otpVerified: false,
          name: 'Rahul Sharma',
          useUpid: false,
          upid: '',
          propertyAddress: '12 MG Road, Pune',
        ),
        isFalse,
      );
    });

    test('a verified phone alone is not enough — the name is required', () {
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: '   ',
          useUpid: false,
          upid: '',
          propertyAddress: '12 MG Road, Pune',
        ),
        isFalse,
      );
    });

    test('the UPID path requires a UPID and ignores the address', () {
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul',
          useUpid: true,
          upid: '',
          propertyAddress: '12 MG Road, Pune',
        ),
        isFalse,
      );
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul',
          useUpid: true,
          upid: 'UP-123',
          propertyAddress: '',
        ),
        isTrue,
      );
    });

    test('the address path requires an address and ignores the UPID', () {
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul',
          useUpid: false,
          upid: 'UP-123',
          propertyAddress: '',
        ),
        isFalse,
      );
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul',
          useUpid: false,
          upid: '',
          propertyAddress: '12 MG Road',
        ),
        isTrue,
      );
    });

    test('a name with digits or symbols blocks submission, otherwise complete',
        () {
      // PropertyVerificationModal.tsx:267-274's regex, mirrored here.
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul123',
          useUpid: false,
          upid: '',
          propertyAddress: '12 MG Road, Pune',
        ),
        isFalse,
      );
      expect(
        canSubmitVerification(
          otpVerified: true,
          name: 'Rahul Sharma',
          useUpid: false,
          upid: '',
          propertyAddress: '12 MG Road, Pune',
        ),
        isTrue,
      );
    });
  });

  // ── 5b. The form itself is live before OTP ─────────────────────────────
  //
  // The regression these pin. An earlier revision dimmed the whole property
  // block until the phone was verified, so the form rendered as interactive and
  // answered no taps. The portal gates only the Submit button
  // (PropertyVerificationModal.tsx:617); every field is editable on open.
  group('verification form', () {
    Future<void> pumpForm(WidgetTester tester, {double textScale = 1.0}) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: PropertyVerificationSheet()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the portal\'s field order and copy', (tester) async {
      await pumpForm(tester);

      expect(find.text('Property Verification Request'), findsOneWidget);
      expect(find.text('Choose Verification Method'), findsOneWidget);
      expect(find.text('Use UPID'), findsOneWidget);
      expect(find.text('Enter Property Details'), findsOneWidget);
      expect(find.text('Submit Verification Request'), findsOneWidget);
      // Invented copy from the broken revision must be gone.
      expect(find.text('I have a UPID'), findsNothing);
      expect(find.text('No UPID'), findsNothing);
      expect(find.text('Your details'), findsNothing);
      expect(find.text('Property details'), findsNothing);
    });

    testWidgets('the property address is editable before any OTP',
        (tester) async {
      await pumpForm(tester);

      final address = find.widgetWithText(TextField, 'Property Address*');
      expect(address, findsNothing, reason: 'label is separate from the hint');

      // Typing into the address field must actually take.
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Enter complete property address',
        ),
        '12 MG Road, Pune',
      );
      await tester.pumpAndSettle();

      expect(find.text('12 MG Road, Pune'), findsOneWidget);
    });

    testWidgets('all twelve address-path fields are visible, none hidden',
        (tester) async {
      await pumpForm(tester);

      // The portal hides none of these behind a disclosure.
      for (final label in [
        'Property Address',
        'Seller Name',
        'Registered in the Name',
        'Plot No/Flat No',
        'Property Type',
        'Colony Name',
        'Khasra No',
        'Mauja',
        'Tehsil',
        'District',
        'State',
        'Country',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      expect(find.textContaining('Add more details'), findsNothing);
    });

    testWidgets(
        'name/place fields strip digits and symbols as they are typed',
        (tester) async {
      await pumpForm(tester);

      Future<void> expectLettersOnly(String hint, String typed, String expected) async {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == hint,
        );
        await tester.enterText(field, typed);
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget, reason: hint);
      }

      await expectLettersOnly('Enter your full name', 'Rahul123!', 'Rahul');
      await expectLettersOnly('Enter seller name', 'Amit@2026', 'Amit');
      await expectLettersOnly('Enter district', 'Pune#1', 'Pune');
    });

    testWidgets(
        'Plot No/Flat No and Khasra No allow digits, letters, "-" and "/" only',
        (tester) async {
      await pumpForm(tester);

      final plotField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Enter plot or flat number',
      );
      await tester.enterText(plotField, '12-A/B#!');
      await tester.pumpAndSettle();
      expect(find.text('12-A/B'), findsOneWidget);

      final khasraField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Enter khasra number',
      );
      await tester.enterText(khasraField, '67/2*&');
      await tester.pumpAndSettle();
      expect(find.text('67/2'), findsOneWidget);
    });

    testWidgets('the method toggle swaps the path and is live before OTP',
        (tester) async {
      await pumpForm(tester);

      expect(find.text('Property Address'), findsOneWidget);
      expect(find.text('UPID'), findsNothing);

      await tester.tap(find.text('Use UPID'));
      await tester.pumpAndSettle();

      expect(find.text('UPID'), findsOneWidget);
      expect(find.text('Property Address'), findsNothing);
      expect(
        find.textContaining('UPID can be found on the property details page'),
        findsOneWidget,
      );
    });

    testWidgets('Country is seeded with India', (tester) async {
      await pumpForm(tester);
      expect(find.text('India'), findsOneWidget);
    });

    testWidgets('the OTP block only appears after a code is sent',
        (tester) async {
      await pumpForm(tester);
      expect(find.text('Enter OTP'), findsNothing);
      expect(
        find.textContaining('We\'ll contact you on this number'),
        findsOneWidget,
      );
    });

    testWidgets('submitting without a verified phone names the reason',
        (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('Submit Verification Request'));
      await tester.pump();

      // The button is live so the guard can speak, rather than being a dead
      // control that explains nothing.
      expect(
        find.text('Please verify your phone number before submitting'),
        findsOneWidget,
      );
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await pumpForm(tester, textScale: 1.3);
      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 6. The UPID / address exclusivity in the written row ───────────────
  group('verification payload', () {
    test('the UPID path nulls every address column', () {
      final payload = PropertyVerificationService.buildPayload(
        requesterName: 'Rahul Sharma',
        contactNumber: '9876543210',
        useUpid: true,
        upid: 'UP-123',
        // Deliberately populated: a user may fill the address fields, then
        // switch to the UPID tab. None of this may reach the row.
        propertyAddress: '12 MG Road',
        sellerName: 'Seller',
        registeredInName: 'Registered',
        plotFlatNo: '4B',
        propertyType: 'Flat',
        colonyName: 'Colony',
        khasraNo: 'K-9',
        mauja: 'Mauja',
        tehsil: 'Tehsil',
        district: 'Pune',
        state: 'Maharashtra',
        country: 'India',
      );

      expect(payload['upid'], 'UP-123');
      for (final key in [
        'property_address',
        'seller_name',
        'registered_in_name',
        'plot_flat_no',
        'property_type',
        'colony_name',
        'khasra_no',
        'mauja',
        'tehsil',
        'district',
        'state',
        'country',
      ]) {
        expect(payload[key], isNull, reason: '$key must be null on the UPID path');
      }
    });

    test('the address path nulls the UPID', () {
      final payload = PropertyVerificationService.buildPayload(
        requesterName: 'Rahul',
        contactNumber: '9876543210',
        useUpid: false,
        upid: 'UP-123',
        propertyAddress: '12 MG Road',
      );

      expect(payload['upid'], isNull);
      expect(payload['property_address'], '12 MG Road');
    });

    test('country falls back to India on the address path', () {
      final payload = PropertyVerificationService.buildPayload(
        requesterName: 'Rahul',
        contactNumber: '9876543210',
        useUpid: false,
        propertyAddress: '12 MG Road',
        country: '   ',
      );
      expect(payload['country'], 'India');
    });

    test('the phone is stored as typed, not as E.164', () {
      // PropertyVerificationModal.tsx:290 sends the raw input; every existing
      // row in this column is in that shape.
      final payload = PropertyVerificationService.buildPayload(
        requesterName: 'Rahul',
        contactNumber: ' 9876543210 ',
        useUpid: true,
        upid: 'UP-1',
      );
      expect(payload['contact_number'], '9876543210');
    });

    test('every key is a column the migrations actually added', () {
      // Verified against 20250822171804 (base CREATE), 20251214112234
      // (requester_name) and 20260326000002 (the ADD COLUMN list).
      const columns = {
        'user_id',
        'requester_name',
        'contact_number',
        'upid',
        'property_address',
        'seller_name',
        'registered_in_name',
        'plot_flat_no',
        'property_type',
        'colony_name',
        'khasra_no',
        'mauja',
        'tehsil',
        'district',
        'state',
        'country',
        'inquiry_details',
      };
      final payload = PropertyVerificationService.buildPayload(
        requesterName: 'x',
        contactNumber: '9876543210',
        useUpid: true,
      );
      expect(payload.keys.toSet(), columns);
    });
  });

  // ── 7. The requirement payload ────────────────────────────────────────
  group('requirement payload', () {
    test('blank optionals are null, never empty strings', () {
      final payload = RequirementService.buildPayload(
        name: ' Rahul ',
        phone: ' 9876543210 ',
        budget: 'under-50l',
        propertyType: null,
        location: '   ',
        requirements: '',
      );

      expect(payload['name'], 'Rahul');
      expect(payload['phone'], '9876543210');
      expect(payload['property_type'], isNull);
      expect(payload['location'], isNull);
      expect(payload['requirements'], isNull);
    });

    test('status is sent explicitly as pending', () {
      // One of the four values the CHECK constraint allows.
      final payload = RequirementService.buildPayload(
        name: 'Rahul',
        phone: '9876543210',
        budget: 'under-50l',
      );
      expect(payload['status'], 'pending');
      expect(payload['user_id'], isNull, reason: 'guest submission');
    });

    test('every key is a real column', () {
      // 20251204171138 (base) + 20251204171842 (phone).
      final payload = RequirementService.buildPayload(
        name: 'Rahul',
        phone: '9876543210',
        budget: 'under-50l',
      );
      expect(payload.keys.toSet(), {
        'name',
        'phone',
        'budget',
        'property_type',
        'location',
        'requirements',
        'user_id',
        'status',
      });
    });
  });

  // ── 8. News section visibility ────────────────────────────────────────
  group('news section', () {
    testWidgets('renders nothing — not even a header — when there is no news',
        (tester) async {
      // The portal's `if (!news?.length) return null`. A header with an empty
      // rail would leave a hole in the Home feed.
      final service = _FakeNewsService(items: const []);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Latest News'), findsNothing);
      expect(service.calls, 1);
      expect(tester.getSize(find.byType(NewsSection)).height, 0);
    });

    testWidgets('renders nothing while the fetch is still in flight',
        (tester) async {
      final gate = Completer<List<NewsItemModel>>();
      final service = _FakeNewsService(gate: gate);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pump();

      expect(find.text('Latest News'), findsNothing,
          reason: 'a header that appears then vanishes would shift the feed');
      expect(tester.getSize(find.byType(NewsSection)).height, 0);

      // Released so the test does not end on a pending future.
      gate.complete([_news()]);
      await tester.pumpAndSettle();
      expect(find.text('Latest News'), findsOneWidget);
    });

    testWidgets('renders nothing when the fetch fails', (tester) async {
      final service = _FakeNewsService(shouldFail: true);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Latest News'), findsNothing);
      expect(tester.getSize(find.byType(NewsSection)).height, 0);
    });

    testWidgets('shows the header and a card once there is news',
        (tester) async {
      final service = _FakeNewsService(items: [
        _news(title: 'Metro line approved', source: 'Economic Times'),
      ]);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Latest News'), findsOneWidget);
      expect(find.text('Metro line approved'), findsOneWidget);
      expect(find.text('Economic Times'), findsOneWidget);
    });

    testWidgets('hides the summary and source rows when absent',
        (tester) async {
      final service = _FakeNewsService(items: [_news()]);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.newspaper_rounded), findsOneWidget,
          reason: 'only the thumbnail placeholder, no source row');
    });

    testWidgets('a video item gets a play badge', (tester) async {
      final service = _FakeNewsService(items: [
        _news(videoUrl: 'https://example.com/clip.mp4'),
      ]);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('the fetch runs once, not on every rebuild', (tester) async {
      // A Future created inside build would re-fire whenever a sibling
      // section's animation ticks.
      final service = _FakeNewsService(items: [_news()]);
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(NewsSection(service: service)));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
    });
  });

  // ── 9. Model parsing ──────────────────────────────────────────────────
  group('news model', () {
    test('blank optional text collapses to null', () {
      final item = NewsItemModel.fromSupabase(<String, dynamic>{
        'id': 'n-1',
        'title': 'Title',
        'summary': '   ',
        'source': '',
        'link_url': '',
        'display_order': 3,
        'published_at': '2026-08-01T10:00:00Z',
      });

      expect(item.summary, isNull);
      expect(item.source, isNull);
      expect(item.hasLink, isFalse);
      expect(item.hasVideo, isFalse);
      expect(item.displayOrder, 3);
    });

    test('a malformed timestamp falls back rather than throwing', () {
      final item = NewsItemModel.fromSupabase(<String, dynamic>{
        'id': 'n-1',
        'title': 'Title',
        'published_at': 'not-a-date',
      });
      expect(item.publishedAt, isA<DateTime>());
      expect(item.displayOrder, 0);
    });
  });

  // ── 10. Smart Tools layout ────────────────────────────────────────────
  group('smart tools', () {
    testWidgets('all three tools render without clipping at 320 dp',
        (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const SmartToolsSection()));
      await tester.pumpAndSettle();

      expect(find.text('Smart Tools'), findsOneWidget);
      expect(find.text('Area Converter'), findsOneWidget);
      expect(find.text('EMI Calculator'), findsOneWidget);
      // The third card is off-screen in the rail, so scroll to it.
      await tester.drag(find.byType(ListView), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Stamp Calculator'), findsOneWidget);

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('survives 130% text scale at 320 dp', (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(const SmartToolsSection(), textScale: 1.3),
      );
      await tester.pumpAndSettle();

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
