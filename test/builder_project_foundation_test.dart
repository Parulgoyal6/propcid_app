// Builder flow — Phase B1: the model, the vocabularies, the coercion layer and
// the media paths.
//
// What is pinned is what fails silently or destructively:
//
//   * every one of the 24 NOT NULL columns receives a concrete value, and the two
//     date columns stay nullable — a null anywhere else is a 23502 and the save
//     just fails;
//   * `master_layout_url` mirrors `map_images.first` and `media_urls` is the
//     flattened gallery, both derived rather than entered;
//   * the vocabularies match the CHECK constraints, so no value can reach
//     Postgres that it would reject with a 23514;
//   * `dbNum` follows JavaScript's `parseFloat`, not Dart's `double.tryParse` —
//     they disagree on inputs the form can produce;
//   * an edit round-trip does not duplicate the gallery;
//   * the storage paths match the portal's, so both apps write the same
//     structure.
//
// Reference line numbers were read from the repo at
// `c:\Users\USER\Desktop\Flutter\propcid`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/project_options.dart';
import 'package:propcid_app/core/validation/project_db_safe.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/services/project_media_service.dart';
import 'package:propcid_app/services/project_service.dart';

/// A draft with every required field filled, as the wizard would hand it over.
ProjectDraft _fullDraft() => const ProjectDraft(
  title: 'Green Valley Heights',
  description: 'A gated community in west Pune.',
  projectType: 'group_housing',
  location: 'Pune',
  totalUnits: 120,
  availableUnits: 45,
  priceRangeMin: 4500000,
  priceRangeMax: 9500000,
  areaSqftMin: 850,
  areaSqftMax: 1850,
  completionDate: '2027-06-30',
  possessionDate: '2027-09-30',
  reraNumber: 'P52100012345',
  websiteUrl: 'https://greenvalley.example',
  contactNumber: '9876543210',
  logoUrl: 'https://cdn.example/logos/1-logo.png',
  brochureUrl: 'https://cdn.example/brochures/1-brochure.pdf',
  mapImages: ['https://cdn.example/master-layouts/1.png'],
  otherImages: [
    'https://cdn.example/other-images/a.jpg',
    'https://cdn.example/other-images/b.jpg',
  ],
  videosUrls: ['https://cdn.example/project-videos/v.mp4'],
  amenities: ['Swimming Pool', 'Gymnasium'],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ProjectService / ProjectMediaService resolve Supabase.instance.client in
    // their constructors. Loopback URL, no refresh — nothing touches the network.
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

  // ── 1. The NOT NULL contract ───────────────────────────────────────────
  //
  // 20270315000000_no_null_listing_and_project_columns.sql:251-275.
  group('NOT NULL columns', () {
    /// The 24 NOT NULL columns this payload actually writes. `status`,
    /// `approval_status`, `likes` and `views` are also NOT NULL but are
    /// deliberately omitted so their column defaults apply.
    const notNullKeys = {
      'title',
      'description',
      'project_type',
      'location',
      'total_units',
      'available_units',
      'price_range_min',
      'price_range_max',
      'area_sqft_min',
      'area_sqft_max',
      'amenities',
      'rera_number',
      'map_images',
      'videos_urls',
      'other_images',
      'brochure_url',
      'website_url',
      'contact_number',
      'logo_url',
      'master_layout_url',
      'media_urls',
      'latitude',
      'longitude',
    };

    test('an entirely empty draft still sends no nulls to a NOT NULL column', () {
      // The worst case: nothing entered. Every one of these columns would reject
      // a null with a 23502, so blanks have to arrive as '' / 0 / [].
      final payload = const ProjectDraft().toPayload();

      for (final key in notNullKeys) {
        expect(payload.containsKey(key), isTrue, reason: '$key is missing');
        expect(
          payload[key],
          isNotNull,
          reason: '$key is NOT NULL and would fail with 23502',
        );
      }
    });

    test('blank text becomes an empty string, not null', () {
      final payload = const ProjectDraft().toPayload();
      expect(payload['description'], '');
      expect(payload['rera_number'], '');
      expect(payload['logo_url'], '');
      expect(payload['master_layout_url'], '');
    });

    test('absent numbers become 0, not null', () {
      final payload = const ProjectDraft().toPayload();
      expect(payload['total_units'], 0);
      expect(payload['available_units'], 0);
      expect(payload['price_range_min'], 0);
      expect(payload['area_sqft_max'], 0);
    });

    test('absent arrays become empty lists, not null', () {
      final payload = const ProjectDraft().toPayload();
      expect(payload['amenities'], isEmpty);
      expect(payload['map_images'], isEmpty);
      expect(payload['videos_urls'], isEmpty);
      expect(payload['media_urls'], isEmpty);
    });

    test('the two date columns are the only ones allowed to be null', () {
      // dbSafe.ts:60-69 — Postgres rejects '' for a `date`, and both columns are
      // nullable, so a blank is a genuine null here.
      final payload = const ProjectDraft().toPayload();
      expect(payload['completion_date'], isNull);
      expect(payload['possession_date'], isNull);

      final nulls = payload.entries
          .where((e) => e.value == null)
          .map((e) => e.key)
          .toSet();
      expect(nulls, {'completion_date', 'possession_date'});
    });

    test('a filled date is passed through as its ISO string', () {
      final payload = _fullDraft().toPayload();
      expect(payload['completion_date'], '2027-06-30');
      expect(payload['possession_date'], '2027-09-30');
    });
  });

  // ── 2. Derived fields ──────────────────────────────────────────────────
  group('derived payload fields', () {
    test('master_layout_url mirrors the first master-plan image', () {
      // BuilderProjectWizard.tsx:518.
      final payload = _fullDraft().toPayload();
      expect(
        payload['master_layout_url'],
        'https://cdn.example/master-layouts/1.png',
      );
    });

    test(
      'master_layout_url is an empty string when no layout was uploaded',
      () {
        final payload = _fullDraft().copyWith(mapImages: const []).toPayload();
        expect(payload['master_layout_url'], '');
      },
    );

    test('media_urls is the flattened gallery', () {
      // BuilderProjectWizard.tsx:520-524 — other images then master plans.
      final payload = _fullDraft().toPayload();
      expect(payload['media_urls'], [
        'https://cdn.example/other-images/a.jpg',
        'https://cdn.example/other-images/b.jpg',
        'https://cdn.example/master-layouts/1.png',
      ]);
    });

    test('latitude and longitude are sent, defaulting to 0 until a location '
        'is picked', () {
      // Supersedes decision D4/PD1: BuilderProjectWizard.tsx:877-906's
      // GoogleLocationPicker does collect both, and ProjectBasicInfoStep's map
      // picker now mirrors it — so these are no longer omitted from the
      // payload. A draft with no pin dropped still writes 0 rather than null,
      // same as every other NOT NULL numeric column.
      final empty = const ProjectDraft().toPayload();
      expect(empty['latitude'], 0);
      expect(empty['longitude'], 0);

      final located = _fullDraft()
          .copyWith(latitude: 18.5204, longitude: 73.8567)
          .toPayload();
      expect(located['latitude'], 18.5204);
      expect(located['longitude'], 73.8567);
    });

    test('status and approval_status are never sent', () {
      // Their column defaults are 'active' and 'pending'. Sending
      // approval_status from a client would let a builder self-approve.
      final payload = _fullDraft().toPayload();
      expect(payload.containsKey('status'), isFalse);
      expect(payload.containsKey('approval_status'), isFalse);
    });

    test('builder_id is not part of the draft payload', () {
      // It is added by ProjectService.create only — a project cannot change
      // owner, so update must not carry it.
      expect(_fullDraft().toPayload().containsKey('builder_id'), isFalse);
    });
  });

  // ── 3. Editing must not duplicate the gallery ──────────────────────────
  group('edit round-trip', () {
    test('re-saving an existing project does not duplicate media_urls', () {
      // The trap: media_urls is derived from the other lists on every write. If
      // the draft read it back and then re-flattened, every URL would double on
      // the second save.
      final created = ProjectModel.fromSupabase({
        'id': 'p-1',
        'builder_id': 'b-1',
        'title': 'Green Valley Heights',
        'description': 'A gated community.',
        'project_type': 'group_housing',
        'location': 'Pune',
        'status': 'active',
        'approval_status': 'pending',
        'map_images': ['m1.png'],
        'other_images': ['o1.jpg', 'o2.jpg'],
        // What the first save wrote.
        'media_urls': ['o1.jpg', 'o2.jpg', 'm1.png'],
        'videos_urls': ['v1.mp4'],
        'amenities': ['Parking'],
      });

      final payload = ProjectDraft.fromProject(created).toPayload();

      expect(payload['media_urls'], ['o1.jpg', 'o2.jpg', 'm1.png']);
      expect(
        (payload['media_urls'] as List).length,
        3,
        reason: 'a second save must not double the gallery',
      );
    });

    test('a draft seeded from a project keeps every editable field', () {
      final project = ProjectModel.fromSupabase({
        'id': 'p-1',
        'builder_id': 'b-1',
        'title': 'Title',
        'description': 'Desc',
        'project_type': 'farm_houses',
        'location': 'Nagpur',
        'total_units': 40,
        'available_units': 12,
        'price_range_min': 100,
        'price_range_max': 200,
        'area_sqft_min': 300,
        'area_sqft_max': 400,
        'completion_date': '2027-01-31',
        'possession_date': '2027-03-31',
        'rera_number': 'R-1',
        'website_url': 'https://x.example',
        'contact_number': '9999999999',
        'logo_url': 'logo.png',
        'brochure_url': 'b.pdf',
      });

      final draft = ProjectDraft.fromProject(project);

      expect(draft.title, 'Title');
      expect(draft.projectType, 'farm_houses');
      expect(draft.totalUnits, 40);
      expect(draft.availableUnits, 12);
      // Dates come back as ISO date strings, not timestamps.
      expect(draft.completionDate, '2027-01-31');
      expect(draft.possessionDate, '2027-03-31');
      expect(draft.reraNumber, 'R-1');
      expect(draft.brochureUrl, 'b.pdf');
    });
  });

  // ── 4. Vocabularies vs the CHECK constraints ───────────────────────────
  group('vocabularies', () {
    test('project types are exactly the CHECK constraint\'s eight values', () {
      // 20250905144708_cc6b51bd…sql:7.
      const allowed = {
        'plotted_development',
        'group_housing',
        'integrated_township',
        'gated_community_plots_villas',
        'farm_houses',
        'service_apartment',
        'commercial_spaces',
        'office_spaces',
      };
      expect(kProjectTypes.map((o) => o.value).toSet(), allowed);
      expect(kProjectTypes.length, 8);
    });

    test('statuses are exactly the CHECK constraint\'s four values', () {
      // Same migration, line 9.
      expect(kProjectStatuses.map((o) => o.value).toSet(), {
        'active',
        'inactive',
        'completed',
        'under_construction',
      });
    });

    test('the 19 portal amenities are present in order', () {
      // BuilderProjectWizard.tsx:67-72.
      expect(kCommonAmenities.length, 19);
      expect(kCommonAmenities.first, 'Swimming Pool');
      expect(kCommonAmenities.last, 'Restaurant');
      expect(kCommonAmenities, contains('24/7 Power Backup'));
      expect(kCommonAmenities.toSet().length, 19, reason: 'no duplicates');
    });

    test('validity checks reject anything outside the constraint', () {
      expect(isValidProjectType('group_housing'), isTrue);
      // Plausible but not legal — a listing category, not a project type.
      expect(isValidProjectType('residential'), isFalse);
      expect(isValidProjectType(''), isFalse);
      expect(isValidProjectType(null), isFalse);
      expect(isValidProjectStatus('active'), isTrue);
      expect(isValidProjectStatus('draft'), isFalse);
    });

    test('labels fall back readably for an unrecognised value', () {
      // A value from a future migration must still render, not crash a card.
      expect(projectTypeLabel('group_housing'), 'Group Housing');
      expect(projectTypeLabel('brand_new_type'), 'brand new type');
      expect(projectTypeLabel(null), '');
      expect(projectStatusLabel('under_construction'), 'Under Construction');
    });
  });

  // ── 5. dbSafe parity ───────────────────────────────────────────────────
  group('coercion helpers', () {
    test('dbNum follows JavaScript parseFloat, not double.tryParse', () {
      // The divergence that matters: after stripping to [\d.-], a mistyped
      // '12.5.7' survives. parseFloat gives 12.5; double.tryParse gives null,
      // which would silently store 0.
      expect(double.tryParse('12.5.7'), isNull);
      expect(jsParseFloat('12.5.7'), 12.5);
      expect(dbNum('12.5.7'), 12.5);
    });

    test('dbNum strips currency symbols and separators', () {
      expect(dbNum('₹45,00,000'), 4500000);
      expect(dbNum('1 234'), 1234);
    });

    test('dbNum falls back to 0 for anything unparseable', () {
      expect(dbNum(''), 0);
      expect(dbNum(null), 0);
      expect(dbNum('abc'), 0);
      expect(dbNum(double.nan), 0);
      expect(dbNum(double.infinity), 0);
    });

    test('dbInt truncates toward zero, matching Math.trunc', () {
      expect(dbInt(2.9), 2);
      expect(dbInt(-2.9), -2);
      expect(dbInt('7.99'), 7);
    });

    test('dbArray drops blanks and nulls', () {
      expect(dbArray(['a', '', null, '  ', 'b']), ['a', 'b']);
      expect(dbArray('not a list'), isEmpty);
      expect(dbArray(null), isEmpty);
    });

    test('dbDate returns null only for a genuine blank', () {
      expect(dbDate(''), isNull);
      expect(dbDate('   '), isNull);
      expect(dbDate(null), isNull);
      expect(dbDate('2027-06-30'), '2027-06-30');
    });

    test(
      'sanitizeText strips event handlers, javascript: and control chars',
      () {
        expect(sanitizeText('<div onclick="x()">Hi</div>'), '<div >Hi</div>');
        expect(sanitizeText("<div onclick='x()'>Hi</div>"), '<div >Hi</div>');
        expect(sanitizeText('javascript:alert(1)'), 'alert(1)');
        expect(sanitizeText('a b'), 'ab');
        expect(sanitizeText(null), '');
        expect(sanitizeText(''), '');
      },
    );

    test('PD8 — script CONTENT survives, exactly as on the website', () {
      // sanitize.ts:24 strips `</script>` first, which leaves the paired matcher
      // on :25 with nothing to match. Reproduced on purpose — the same column is
      // read by both apps. Pinned so nobody "fixes" one side alone, and so the
      // next reader knows this helper does not actually sanitise.
      expect(
        sanitizeText('<script>alert(1)</script>Hello'),
        '<script>alert(1)Hello',
      );
      expect(sanitizeText('<style>body{}</style>Hi'), '<style>body{}Hi');
    });

    test('PD9 — newlines become spaces, not nothing (Flutter diverges)', () {
      // The website deletes a newline before its collapse can see it, joining
      // adjacent lines with no separator. That is data corruption, not a rule,
      // so it is fixed here: \x09-\x0D become a space first. Approved as a
      // knowing, one-sided divergence - the website still mangles its own input.
      expect(sanitizeText('line one\nline two'), 'line one line two');
      expect(sanitizeText('a\tb'), 'a b');
      expect(sanitizeText('a\r\nb'), 'a b');
      // Blank lines collapse to a single space rather than several.
      expect(sanitizeText('a\n\n\nb'), 'a b');
      // Runs of real spaces still collapse.
      expect(sanitizeText('a    b'), 'a b');
      // Non-whitespace control characters are still deleted outright.
      expect(sanitizeText('a\u0000b'), 'ab');
      expect(sanitizeText('a\u001Fb'), 'ab');
    });

    test('a multi-line description survives into the payload readably', () {
      final payload = const ProjectDraft(
        description: 'Phase 1 is ready.\nPhase 2 completes in 2027.',
      ).toPayload();
      expect(
        payload['description'],
        'Phase 1 is ready. Phase 2 completes in 2027.',
      );
    });

    test('sanitizeNullable turns a blank into null', () {
      expect(sanitizeNullable('  '), isNull);
      expect(sanitizeNullable(null), isNull);
      expect(sanitizeNullable(' x '), 'x');
    });

    test('a description is sanitised on its way into the payload', () {
      final payload = const ProjectDraft(
        description: '<script>bad()</script>A calm  community.',
      ).toPayload();
      // PD8 again, seen through dbText: the opening tag survives, the double
      // space collapses.
      expect(payload['description'], '<script>bad()A calm community.');
    });
  });

  // ── 6. The model ───────────────────────────────────────────────────────
  group('project model', () {
    test('a sparse row parses without throwing and defaults sensibly', () {
      final project = ProjectModel.fromSupabase({'id': 'p-1'});

      expect(project.id, 'p-1');
      expect(project.status, 'active', reason: 'the column default');
      expect(project.approvalStatus, 'pending');
      expect(project.totalUnits, 0);
      expect(project.amenities, isEmpty);
      expect(project.completionDate, isNull);
      expect(project.coverImage, isNull);
    });

    test(
      'coverImage falls through the three gallery sources then the logo',
      () {
        ProjectModel withMedia({
          List<String> media = const [],
          List<String> others = const [],
          List<String> maps = const [],
          String logo = '',
        }) => ProjectModel.fromSupabase({
          'id': 'p',
          'media_urls': media,
          'other_images': others,
          'map_images': maps,
          'logo_url': logo,
        });

        expect(
          withMedia(media: ['m.jpg'], others: ['o.jpg']).coverImage,
          'm.jpg',
        );
        // A row written before the flattening existed has no media_urls.
        expect(withMedia(others: ['o.jpg']).coverImage, 'o.jpg');
        expect(withMedia(maps: ['x.png']).coverImage, 'x.png');
        expect(withMedia(logo: 'l.png').coverImage, 'l.png');
      },
    );

    test('galleryImages deduplicates across the three sources', () {
      final project = ProjectModel.fromSupabase({
        'id': 'p',
        'media_urls': ['a.jpg', 'b.jpg'],
        'other_images': ['a.jpg'],
        'map_images': ['m.png'],
      });
      expect(project.galleryImages, ['a.jpg', 'b.jpg', 'm.png']);
    });

    test('public visibility is status == active, ignoring approval', () {
      // The public read policy is `USING (status = 'active')` only — PD2.
      final pending = ProjectModel.fromSupabase({
        'id': 'p',
        'status': 'active',
        'approval_status': 'pending',
      });
      expect(pending.isPubliclyVisible, isTrue);
      expect(pending.isApproved, isFalse);

      final inactive = ProjectModel.fromSupabase({
        'id': 'p',
        'status': 'inactive',
        'approval_status': 'approved',
      });
      expect(inactive.isPubliclyVisible, isFalse);
    });

    test('a 0 price range reads as absent, not as free', () {
      final project = ProjectModel.fromSupabase({'id': 'p'});
      expect(project.hasPriceRange, isFalse);
      expect(project.hasAreaRange, isFalse);
    });

    test('soldUnits is clamped so a bad older row cannot go negative', () {
      // Nothing in the database enforces available <= total; the cross-field rule
      // is client-side only.
      final project = ProjectModel.fromSupabase({
        'id': 'p',
        'total_units': 10,
        'available_units': 25,
      });
      expect(project.soldUnits, 0);
    });

    test('the column list names every field the model parses', () {
      for (final column in [
        'id',
        'builder_id',
        'master_layout_url',
        'other_images',
        'videos_urls',
        'approval_status',
        'completion_date',
        'possession_date',
      ]) {
        expect(ProjectModel.columns, contains(column));
      }
      // select('*') would let a future migration change what this parses.
      expect(ProjectModel.columns, isNot(contains('*')));
    });
  });

  // ── 7. Draft persistence ───────────────────────────────────────────────
  group('draft json', () {
    test('a full draft survives a round-trip', () {
      final original = _fullDraft();
      final restored = ProjectDraft.fromJson(original.toJson());

      expect(restored.toPayload(), original.toPayload());
    });

    test('a draft written by an older build still opens', () {
      // Unknown keys ignored, missing keys defaulted — never an exception.
      final restored = ProjectDraft.fromJson({
        'title': 'Partial',
        'some_removed_field': 'whatever',
      });
      expect(restored.title, 'Partial');
      expect(restored.totalUnits, isNull);
      expect(restored.amenities, isEmpty);
    });

    test('isEmpty tells a fresh draft from a resumable one', () {
      expect(const ProjectDraft().isEmpty, isTrue);
      expect(const ProjectDraft(title: 'x').isEmpty, isFalse);
      expect(const ProjectDraft(amenities: ['Parking']).isEmpty, isFalse);
      expect(_fullDraft().isEmpty, isFalse);
    });
  });

  // ── 8. Storage paths and MIME types ────────────────────────────────────
  group('media service', () {
    test('the bucket and its 50 MB ceiling match the migrations', () {
      expect(ProjectMediaService.bucket, 'project-media');
      expect(ProjectMediaService.maxBytes, 52428800);
    });

    test('the five path prefixes are the portal\'s', () {
      expect(ProjectMediaService.logoPrefix, 'logos');
      expect(ProjectMediaService.masterLayoutPrefix, 'master-layouts');
      expect(ProjectMediaService.imagePrefix, 'other-images');
      expect(ProjectMediaService.videoPrefix, 'project-videos');
      expect(ProjectMediaService.brochurePrefix, 'brochures');
    });

    test('extensions are lowercased, with a fallback', () {
      expect(ProjectMediaService.extensionOf('a.PNG'), 'png');
      expect(ProjectMediaService.extensionOf('logo.jpeg'), 'jpeg');
      expect(ProjectMediaService.extensionOf('noext'), 'bin');
      expect(ProjectMediaService.extensionOf('trailing.'), 'bin');
    });

    test('a brochure is sent as application/pdf', () {
      // Without this the public URL downloads an octet-stream instead of opening.
      expect(ProjectMediaService.mimeFromName('x.pdf'), 'application/pdf');
      expect(ProjectMediaService.mimeFromName('x.jpg'), 'image/jpeg');
      expect(ProjectMediaService.mimeFromName('x.mp4'), 'video/mp4');
      expect(
        ProjectMediaService.mimeFromName('x.zzz'),
        'application/octet-stream',
      );
    });

    test('an empty file is refused before any network call', () async {
      final service = ProjectMediaService();
      expect(
        () => service.uploadLogo(bytes: Uint8List(0), fileName: 'a.png'),
        throwsA(isA<ProjectMediaException>()),
      );
    });

    test('an oversize file is refused with an actionable message', () async {
      final service = ProjectMediaService();
      final tooBig = Uint8List(ProjectMediaService.maxBytes + 1);

      await expectLater(
        service.uploadVideo(bytes: tooBig, fileName: 'v.mp4'),
        throwsA(
          isA<ProjectMediaException>().having(
            (e) => e.message,
            'message',
            contains('50 MB'),
          ),
        ),
      );
    });
  });
}
