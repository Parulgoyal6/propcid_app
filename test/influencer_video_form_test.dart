// Spec E — the influencer video form.
//
// `InfluencerVideoModal.tsx` is the reference. What is pinned:
//
//   * the two pre-flight gates, and that they behave differently on create and
//     edit — a new video needs a file, an existing one does not (:112-118);
//   * that an edit which touches no file re-uploads nothing, which is the whole
//     point of `let videoUrl = editingVideo?.video_url` (:128-130);
//   * the form seeding from the row being edited, hashtags included (:29-38);
//   * that a failed upload does not write a row.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/influencer_video_model.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/influencer/influencer_video_form_screen.dart';
import 'package:propcid_app/services/influencer_media_service.dart';
import 'package:propcid_app/services/influencer_video_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

class _FakeAuth extends AuthProvider {
  _FakeAuth({this.id = 'u-1'});

  final String? id;

  @override
  String? get userId => id;

  @override
  bool get isLoggedIn => id != null;
}

class _FakeVideoService extends InfluencerVideoService {
  final List<InfluencerVideoDraft> creates = [];
  final List<({String id, InfluencerVideoDraft draft})> updates = [];

  @override
  Future<String> create(InfluencerVideoDraft draft) async {
    creates.add(draft);
    return 'new-id';
  }

  @override
  Future<void> update(String videoId, InfluencerVideoDraft draft) async {
    updates.add((id: videoId, draft: draft));
  }
}

class _FakeMediaService extends InfluencerMediaService {
  final List<String> videoUploads = [];
  final List<String> thumbnailUploads = [];

  /// When set, the next `uploadVideo` throws this instead of returning.
  InfluencerMediaException? videoFailure;

  @override
  Future<String> uploadVideo({
    required XFile file,
    required String userId,
    void Function(String stage)? onProgress,
  }) async {
    videoUploads.add(file.path);
    onProgress?.call('Compressing video…');
    final failure = videoFailure;
    if (failure != null) {
      videoFailure = null;
      throw failure;
    }
    return 'https://cdn.test/$userId/videos/uploaded.mp4';
  }

  @override
  Future<String> uploadThumbnail({
    required XFile file,
    required String userId,
  }) async {
    thumbnailUploads.add(file.path);
    return 'https://cdn.test/$userId/thumbnails/uploaded.jpg';
  }
}

/// Returns a scripted path instead of opening a gallery.
class _FakePicker extends ImagePicker {
  _FakePicker({this.videoPath, this.imagePath});

  final String? videoPath;
  final String? imagePath;

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => videoPath == null ? null : XFile(videoPath!);

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => imagePath == null ? null : XFile(imagePath!);
}

InfluencerVideoModel _existing() => InfluencerVideoModel.fromSupabase({
  'id': 'v-1',
  'user_id': 'u-1',
  'title': 'Bandra 3BHK walkthrough',
  'description': 'A quick tour.',
  'video_url': 'https://cdn.test/existing.mp4',
  'thumbnail_url': 'https://cdn.test/existing.jpg',
  'video_type': 'property_news',
  'hashtags': ['pune', '3bhk'],
  'status': 'active',
  'approval_status': 'approved',
});

/// Tall enough that the whole form is laid out at once.
///
/// The form is a `ListView`, so on a 720 dp viewport the Details card sits below
/// the fold and is never built — `enterText` cannot reach a field that does not
/// exist. Interaction tests use this; the layout group uses [kSmall], which is the
/// size that actually matters for overflow.
const Size kTall = Size(320, 2400);

Future<void> _pumpForm(
  WidgetTester tester, {
  InfluencerVideoModel? editing,
  required _FakeVideoService service,
  required _FakeMediaService media,
  _FakePicker? picker,
  String? userId = 'u-1',
  double textScale = 1.0,
  Size size = kTall,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuth(id: userId),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: InfluencerVideoFormScreen(
          editing: editing,
          videoService: service,
          mediaService: media,
          picker: picker ?? _FakePicker(),
          // No-op stubs: the real dialogs open against a live SocialService
          // (or, for the boost prompt, a real confirm dialog with nothing to
          // dismiss it) and would hang the test waiting for a tap that never
          // comes.
          publishDialogLauncher:
              (
                context, {
                required userId,
                required contentType,
                required contentId,
                required mediaUrls,
                title,
              }) async {},
          boostDialogLauncher:
              (
                context, {
                required userId,
                required contentType,
                required contentId,
                required mediaUrls,
                title,
              }) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The Location field now uses AddressAutocompleteField, whose
    // PlacesAutocompleteService reads GOOGLE_MAPS_API_KEY from dotenv at
    // construction — same requirement basic_info_step.dart's own tests
    // already have for the identical widget.
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=test');
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // ── 1. Create ───────────────────────────────────────────────────────────
  group('create mode', () {
    testWidgets('opens empty, with every video type offered', (tester) async {
      await _pumpForm(
        tester,
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      expect(find.text('Upload Video'), findsWidgets);
      expect(find.text('Property Listing Video'), findsOneWidget);
      expect(find.text('Property News'), findsOneWidget);
      expect(find.text('Property Education'), findsOneWidget);
      expect(find.text('Choose a video'), findsOneWidget);
    });

    testWidgets('submitting empty names every problem at once', (tester) async {
      // The modal raises one toast and stops; a summary is more useful on a form
      // the user can see all of.
      final service = _FakeVideoService();
      await _pumpForm(tester, service: service, media: _FakeMediaService());

      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(find.text('Please upload a video file.'), findsOneWidget);
      expect(find.text('A title is required.'), findsOneWidget);
      expect(find.text('Choose a video type.'), findsOneWidget);
      expect(service.creates, isEmpty);
    });

    testWidgets('a full submit uploads then inserts', (tester) async {
      final service = _FakeVideoService();
      final media = _FakeMediaService();
      await _pumpForm(
        tester,
        service: service,
        media: media,
        picker: _FakePicker(videoPath: '/tmp/clip.mp4'),
      );

      await tester.tap(find.text('Choose a video'));
      await tester.pumpAndSettle();
      expect(find.text('clip.mp4'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'Bandra 3BHK walkthrough',
      );
      await tester.tap(find.text('Property News'));
      await tester.pumpAndSettle();

      // The hashtags field is the third and last on the form.
      await tester.enterText(find.byType(TextField).last, '#Pune, 3BHK');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(media.videoUploads, ['/tmp/clip.mp4']);
      expect(media.thumbnailUploads, isEmpty);

      // `user_id` is no longer sent by the client at all — the edge function
      // sets it server-side from the caller's JWT (`influencer-video-save`'s
      // own header comment: "never trusted from the client").
      final created = service.creates.single;
      expect(created.title, 'Bandra 3BHK walkthrough');
      expect(created.videoType, 'property_news');
      expect(created.hashtagsText, '#Pune, 3BHK');
      expect(created.videoUrl, 'https://cdn.test/u-1/videos/uploaded.mp4');
      expect(created.thumbnailUrl, isNull);
    });

    testWidgets('a failed upload writes no row and shows the reason', (
      tester,
    ) async {
      final service = _FakeVideoService();
      final media = _FakeMediaService()
        ..videoFailure = const InfluencerMediaException(
          'Video is too large (91.4 MB). Maximum is 50.0 MB.',
        );
      await _pumpForm(
        tester,
        service: service,
        media: media,
        picker: _FakePicker(videoPath: '/tmp/huge.mp4'),
      );

      await tester.tap(find.text('Choose a video'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Too big');
      await tester.tap(find.text('Property News'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(
        service.creates,
        isEmpty,
        reason: 'a row pointing at nothing is worse than no row',
      );
      // The service's message, verbatim — not replaced with generic copy.
      expect(find.textContaining('Video is too large'), findsOneWidget);
    });

    testWidgets('a signed-out submit is refused before any upload', (
      tester,
    ) async {
      final media = _FakeMediaService();
      await _pumpForm(
        tester,
        service: _FakeVideoService(),
        media: media,
        picker: _FakePicker(videoPath: '/tmp/clip.mp4'),
        userId: null,
      );

      await tester.tap(find.text('Choose a video'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Orphan');
      await tester.tap(find.text('Property News'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(media.videoUploads, isEmpty);
      expect(find.textContaining('Sign in again'), findsOneWidget);
    });

    testWidgets('a thumbnail is uploaded when one is picked', (tester) async {
      final service = _FakeVideoService();
      final media = _FakeMediaService();
      await _pumpForm(
        tester,
        service: service,
        media: media,
        picker: _FakePicker(
          videoPath: '/tmp/clip.mp4',
          imagePath: '/tmp/thumb.jpg',
        ),
      );

      await tester.tap(find.text('Choose a video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a thumbnail'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'With a thumb');
      await tester.tap(find.text('Property News'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(media.thumbnailUploads, ['/tmp/thumb.jpg']);
      expect(
        service.creates.single.thumbnailUrl,
        'https://cdn.test/u-1/thumbnails/uploaded.jpg',
      );
    });
  });

  // ── 2. Edit ─────────────────────────────────────────────────────────────
  group('edit mode', () {
    testWidgets('seeds every field from the row', (tester) async {
      await _pumpForm(
        tester,
        editing: _existing(),
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      expect(find.text('Edit Video'), findsWidgets);
      expect(find.text('Bandra 3BHK walkthrough'), findsOneWidget);
      expect(find.text('A quick tour.'), findsOneWidget);
      // The portal's own seed: hashtags.join(', ').
      expect(find.text('pune, 3bhk'), findsOneWidget);
      // The stored video reads as present without being re-picked.
      expect(find.text('Uploaded video'), findsOneWidget);
      expect(find.text('Choose a video'), findsNothing);
    });

    testWidgets('saving without touching a file re-uploads nothing', (
      tester,
    ) async {
      final service = _FakeVideoService();
      final media = _FakeMediaService();
      await _pumpForm(
        tester,
        editing: _existing(),
        service: service,
        media: media,
      );

      await tester.enterText(find.byType(TextField).first, 'A better title');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      expect(media.videoUploads, isEmpty);
      expect(media.thumbnailUploads, isEmpty);

      final updated = service.updates.single;
      expect(updated.id, 'v-1');
      expect(updated.draft.title, 'A better title');
      // The stored URLs carried through untouched.
      expect(updated.draft.videoUrl, 'https://cdn.test/existing.mp4');
      expect(updated.draft.thumbnailUrl, 'https://cdn.test/existing.jpg');
      // Re-queueing for review now happens server-side
      // (`influencer-video-save`'s `resubmit_for_approval` call for a
      // non-admin) — the client draft no longer carries an approval_status
      // field to assert against at all.
    });

    testWidgets('an edit does not demand a new video file', (tester) async {
      // The create-mode gate must not fire here (:113).
      final service = _FakeVideoService();
      await _pumpForm(
        tester,
        editing: _existing(),
        service: service,
        media: _FakeMediaService(),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Please upload a video file.'), findsNothing);
      expect(service.updates, hasLength(1));
    });

    testWidgets('clearing the thumbnail sends null', (tester) async {
      final service = _FakeVideoService();
      await _pumpForm(
        tester,
        editing: _existing(),
        service: service,
        media: _FakeMediaService(),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a thumbnail'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      expect(service.updates.single.draft.thumbnailUrl, isNull);
    });

    testWidgets('an emptied title blocks the save', (tester) async {
      final service = _FakeVideoService();
      await _pumpForm(
        tester,
        editing: _existing(),
        service: service,
        media: _FakeMediaService(),
      );

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('A title is required.'), findsOneWidget);
      expect(service.updates, isEmpty);
    });
  });

  // ── 2b. Property Listing Video ─────────────────────────────────────────
  group('Property Listing Video', () {
    testWidgets('Property Details is hidden until that type is picked', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      expect(find.text('Property Details'), findsNothing);

      await tester.tap(find.text('Property Listing Video'));
      await tester.pumpAndSettle();

      // Required fields render as "Location *" etc (PortalLabelledField).
      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('Location *'), findsOneWidget);
      expect(find.text('Price *'), findsOneWidget);
      expect(find.text('Listing Type *'), findsOneWidget);
      expect(find.text('Property Type *'), findsOneWidget);
    });

    testWidgets('switching to another type hides it again', (tester) async {
      await _pumpForm(
        tester,
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      await tester.tap(find.text('Property Listing Video'));
      await tester.pumpAndSettle();
      expect(find.text('Property Details'), findsOneWidget);

      await tester.tap(find.text('Property News'));
      await tester.pumpAndSettle();
      expect(find.text('Property Details'), findsNothing);
    });

    testWidgets(
      'Bedrooms/Bathrooms are not offered before a category is chosen',
      (tester) async {
        // `propertyCategoryHasBedBath(null)` is false — no category picked
        // yet must not show them prematurely.
        await _pumpForm(
          tester,
          service: _FakeVideoService(),
          media: _FakeMediaService(),
        );

        await tester.tap(find.text('Property Listing Video'));
        await tester.pumpAndSettle();

        expect(find.text('Bedrooms'), findsNothing);
        expect(find.text('Bathrooms'), findsNothing);
      },
    );

    testWidgets('submitting a listing video without property fields names '
        'every problem', (tester) async {
      final service = _FakeVideoService();
      await _pumpForm(
        tester,
        service: service,
        media: _FakeMediaService(),
        picker: _FakePicker(videoPath: '/tmp/clip.mp4'),
      );

      await tester.tap(find.text('Choose a video'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'A listing');
      await tester.tap(find.text('Property Listing Video'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(ElevatedButton, 'Upload Video'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(find.text('Property location is required.'), findsOneWidget);
      expect(find.text('Property price is required.'), findsOneWidget);
      expect(
        find.text('Listing type must be sale, rent, or lease.'),
        findsOneWidget,
      );
      expect(service.creates, isEmpty);
    });

    testWidgets('edit mode pre-fills every existing property field', (
      tester,
    ) async {
      final listing = InfluencerVideoModel.fromSupabase({
        'id': 'v-2',
        'user_id': 'u-1',
        'title': 'Bandra 3BHK for sale',
        'description': 'A tour.',
        'video_url': 'https://cdn.test/existing.mp4',
        'video_type': 'property_listing',
        'hashtags': const <String>[],
        'status': 'active',
        'approval_status': 'approved',
        'property_location': 'Bandra West',
        'property_price': '8500000',
        'property_listing_type': 'sale',
        'property_category': 'residential',
        'property_bedrooms': 3,
        'property_bathrooms': 2,
        'property_area': '1200',
      });

      await _pumpForm(
        tester,
        editing: listing,
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('Bandra West'), findsOneWidget);
      expect(find.text('8500000'), findsOneWidget);
      expect(find.text('1200'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // Residential shows Bedrooms/Bathrooms.
      expect(find.text('Bedrooms'), findsOneWidget);
      expect(find.text('Bathrooms'), findsOneWidget);
    });

    testWidgets('editing a non-listing video never shows Property Details', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        editing: _existing(), // videoType: 'property_news'
        service: _FakeVideoService(),
        media: _FakeMediaService(),
      );

      expect(find.text('Property Details'), findsNothing);
    });
  });

  // ── 3. Layout ───────────────────────────────────────────────────────────
  group('layout', () {
    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pumpForm(
        tester,
        editing: _existing(),
        service: _FakeVideoService(),
        media: _FakeMediaService(),
        textScale: 1.3,
        size: kSmall,
      );

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the validation summary does not overflow either', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        service: _FakeVideoService(),
        media: _FakeMediaService(),
        textScale: 1.3,
        size: kSmall,
      );

      // The submit button sits below the fold on a real phone, so it has to be
      // scrolled to before it can be tapped — which is also what makes this the
      // realistic path for the summary to appear on.
      await tester.scrollUntilVisible(
        find.widgetWithText(ElevatedButton, 'Upload Video'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Video'));
      await tester.pumpAndSettle();

      expect(overflowingBoxes(tester), isEmpty);
    });
  });
}
