// Reels screen — the full-bleed video overlay redesign (creator row, title,
// description, specs chips, price/CTA bar, comment bar, and action rail all
// floating directly on the video, replacing the old separate white card).
//
// This only guards against layout regressions (RenderFlex overflow etc.)
// for a reel carrying the richest realistic data — everything the new
// overlay renders at once. It does not assert on colors/positions/pixels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/reel_model.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/screens/reels/reels_screen.dart';

class _FakeReels extends ReelsProvider {
  _FakeReels(this._rows);

  final List<ReelModel> _rows;

  @override
  List<ReelModel> get reels => _rows;

  @override
  bool get isLoading => false;
}

ReelModel _richReel() => const ReelModel(
      id: 'r-1',
      title: 'Luxury 4BHK Villa in Noida',
      description:
          'Modern design with premium amenities, private pool, and a '
          'beautiful sunset view over the city skyline every evening.',
      videoUrl: 'https://cdn.test/reel.mp4',
      builderName: 'John Realtor',
      builderAvatarUrl: '',
      isVerified: true,
      price: '₹2.45 Cr',
      location: 'Noida, Sector 150',
      beds: 4,
      baths: 4,
      sqft: 3200,
      possessionStatus: 'Ready to Move',
      likes: 1200,
      views: 5000,
    );

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

  testWidgets(
    'a reel with title, description, specs, price, location and builder '
    'renders without overflowing',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels([_richReel()]),
          child: const MaterialApp(home: ReelsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('LUXURY 4BHK VILLA IN NOIDA'), findsOneWidget);
      expect(find.text('₹2.45 Cr'), findsOneWidget);
      expect(find.text('more'), findsOneWidget);

      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  testWidgets(
    'a reel with none of the optional data (no builder/price/specs) still '
    'renders without overflowing',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels([
            const ReelModel(
              id: 'r-2',
              title: '',
              description: '',
              videoUrl: 'https://cdn.test/reel2.mp4',
            ),
          ]),
          child: const MaterialApp(home: ReelsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);

      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  testWidgets(
    'the same reel still fits a narrow, short phone screen (320x640)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels([_richReel()]),
          child: const MaterialApp(home: ReelsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);

      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    },
  );
}
