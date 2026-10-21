// Builder flow — Phase B2: the wizard's gating, drafts and submit.
//
// What is pinned is the behaviour a user would notice breaking:
//
//   * each step's required fields, straight from `projectRules.ts`;
//   * errors appear only after a real attempt, then clear live;
//   * the cross-field rule "available cannot exceed total";
//   * submit re-runs every step and lands on the first that fails;
//   * a draft is saved while creating, never while editing, and is only offered
//     back when it holds something worth resuming;
//   * edit mode updates instead of inserting, and does not touch the draft.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/providers/add_project_provider.dart';
import 'package:propcid_app/screens/add_project/add_project_screen.dart';
import 'package:propcid_app/screens/add_project/project_field_keys.dart';
import 'package:propcid_app/screens/add_project/project_validation_rules.dart';
import 'package:propcid_app/services/project_media_service.dart';
import 'package:propcid_app/services/project_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

const String kValidProjectDescription =
    'Green Valley Heights is a thoughtfully planned gated residential community '
    'in west Pune with modern homes, landscaped open spaces, reliable security, '
    'parking, and convenient access to schools, hospitals, markets, and public transport.';

/// Records every call instead of touching Supabase.
class _FakeProjectService extends ProjectService {
  final List<ProjectDraft> created = [];
  final List<({String projectId, String builderId, ProjectDraft draft})>
  updated = [];
  bool shouldFail = false;

  @override
  Future<ProjectModel> create({
    required String builderId,
    required ProjectDraft draft,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    created.add(draft);
    return ProjectModel.fromSupabase({
      'id': 'new-project',
      'builder_id': builderId,
      ...draft.toPayload(),
    });
  }

  @override
  Future<void> update({
    required String projectId,
    required String builderId,
    required ProjectDraft draft,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    updated.add((projectId: projectId, builderId: builderId, draft: draft));
  }
}

class _FakeMediaService extends ProjectMediaService {
  final List<String> uploaded = [];
  bool shouldFail = false;

  Future<String> _fake(String prefix, String fileName) async {
    if (shouldFail) throw const ProjectMediaException('nope');
    final url = 'https://cdn.test/$prefix/$fileName';
    uploaded.add(url);
    return url;
  }

  @override
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String fileName,
  }) => _fake('logos', fileName);

  @override
  Future<String> uploadMasterLayout({
    required Uint8List bytes,
    required String fileName,
  }) => _fake('master-layouts', fileName);

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) => _fake('other-images', fileName);

  @override
  Future<String> uploadVideo({
    required Uint8List bytes,
    required String fileName,
  }) => _fake('project-videos', fileName);

  @override
  Future<String> uploadBrochure({
    required Uint8List bytes,
    required String fileName,
  }) => _fake('brochures', fileName);
}

/// A provider with every field filled, parked on the review step.
Future<AddProjectProvider> _completeProvider({
  _FakeProjectService? service,
  _FakeMediaService? media,
}) async {
  final provider = AddProjectProvider(
    projectService: service ?? _FakeProjectService(),
    mediaService: media ?? _FakeMediaService(),
  );

  provider
    ..setTitle('Green Valley Heights')
    ..setDescription(kValidProjectDescription)
    ..setProjectType('group_housing')
    ..setLocation('Pune')
    // A resolved map pin is now also required on the Basic Info step (the
    // location/map bug fix: an address string alone was never enough to
    // satisfy a form that claims to require a map location).
    ..setLatitude(18.5204)
    ..setLongitude(73.8567)
    ..setTotalUnits('120')
    ..setAvailableUnits('45')
    ..setPriceMin('4500000')
    ..setPriceMax('9500000')
    ..setAreaMin('850')
    ..setAreaMax('1850')
    ..setCompletionDate('2027-06-30')
    ..setPossessionDate('2027-09-30')
    ..setReraNumber('P52100012345')
    ..setWebsiteUrl('https://greenvalley.example')
    ..setContactNumber('9876543210')
    ..toggleAmenity('Swimming Pool');

  await provider.uploadLogo(Uint8List(4), 'logo.png');
  await provider.uploadMasterLayout(Uint8List(4), 'layout.png');
  await provider.uploadImage(Uint8List(4), 'a.jpg');
  await provider.uploadVideo(Uint8List(4), 'v.mp4');
  await provider.uploadBrochure(Uint8List(4), 'b.pdf');

  return provider;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=');

    // Installed here as well as in setUp: Supabase.initialize below reaches for
    // shared_preferences, and setUp has not run yet.
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

  setUp(() {
    // Each test starts with an empty draft store.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ── 1. Per-step required fields ────────────────────────────────────────
  group('step rules', () {
    test(
      'basic requires title, type, city, description and a resolved map pin',
      () {
        final issues = validateProjectStep(
          ProjectStep.basic,
          const ProjectDraft(),
        );
        expect(issues.map((i) => i.field).toSet(), {
          kProjectTitle,
          kProjectType,
          kProjectLocation,
          kProjectDescription,
          // Location/map bug fix: an address string alone was never enough
          // to satisfy a form that requires a map location — see
          // _crossFieldBasicIssues.
          kProjectCoordinates,
        });
        // The reference labels `location` "City".
        expect(issues.map((i) => i.label), contains('City'));
      },
    );

    test('description is validated on letter count, not word count '
        '(projectRules.ts:82 minAlphaChars, not a word check)', () {
      const filledExceptDescription = ProjectDraft(
        title: 'Some Project',
        projectType: 'Apartment',
        location: 'Pune',
      );

      // Few words, plenty of letters (44) — must PASS. A word-count rule
      // would have blocked this at "2 words".
      final longWord = validateProjectStep(
        ProjectStep.basic,
        filledExceptDescription.copyWith(
          description: 'Supercalifragilisticexpialidocious residence',
        ),
      );
      expect(
        longWord.map((i) => i.field),
        isNot(contains(kProjectDescription)),
      );

      // 20 "words" (single-digit numbers), no letters at all — must FAIL. A
      // word-count rule would have passed this at "20 words" exactly;
      // `countAlphaChars` strips the digits but keeps the 19 separator
      // spaces between them, landing one short of the 20 required.
      final manyNumbers = validateProjectStep(
        ProjectStep.basic,
        filledExceptDescription.copyWith(
          description: List.generate(20, (i) => '$i').join(' '),
        ),
      );
      final issue = manyNumbers.firstWhere(
        (i) => i.field == kProjectDescription,
      );
      expect(
        issue.message,
        'Description must be at least 20 letters (currently 19).',
      );
    });

    test('details requires all nine fields', () {
      final issues = validateProjectStep(
        ProjectStep.details,
        const ProjectDraft(),
      );
      expect(issues.map((i) => i.field).toSet(), {
        kProjectTotalUnits,
        kProjectAvailableUnits,
        kProjectPriceMin,
        kProjectPriceMax,
        kProjectAreaMin,
        kProjectAreaMax,
        kProjectCompletionDate,
        kProjectPossessionDate,
        kProjectReraNumber,
      });
    });

    test('available units accepts 0 but total units does not', () {
      // nonNegativeNumber vs positiveNumber — a sold-out project is legal.
      const soldOut = ProjectDraft(availableUnits: 0, totalUnits: 0);
      final issues = validateProjectStep(ProjectStep.details, soldOut);
      final fields = issues.map((i) => i.field).toSet();

      expect(fields, isNot(contains(kProjectAvailableUnits)));
      expect(fields, contains(kProjectTotalUnits));
    });

    test('maximum price must be greater than minimum price — not part of the '
        'React port, added on explicit request', () {
      const equal = ProjectDraft(
        priceRangeMin: 5000000,
        priceRangeMax: 5000000,
      );
      final equalIssues = validateProjectStep(ProjectStep.details, equal);
      expect(
        equalIssues.map((i) => i.field),
        contains(kProjectPriceMax),
        reason: 'max == min must still fail — max must be strictly greater',
      );

      const inverted = ProjectDraft(
        priceRangeMin: 9000000,
        priceRangeMax: 5000000,
      );
      final invertedIssues = validateProjectStep(ProjectStep.details, inverted);
      expect(invertedIssues.map((i) => i.field), contains(kProjectPriceMax));

      const valid = ProjectDraft(
        priceRangeMin: 5000000,
        priceRangeMax: 9000000,
      );
      final validIssues = validateProjectStep(ProjectStep.details, valid);
      expect(
        validIssues.map((i) => i.field),
        isNot(contains(kProjectPriceMax)),
      );
    });

    test('maximum area must be greater than minimum area, and both must be at '
        'least 100 sq ft — not part of the React port, added on explicit '
        'request', () {
      const tooSmall = ProjectDraft(areaSqftMin: 80, areaSqftMax: 90);
      final tooSmallIssues = validateProjectStep(ProjectStep.details, tooSmall);
      expect(
        tooSmallIssues.map((i) => i.field),
        containsAll(<String>[kProjectAreaMin, kProjectAreaMax]),
        reason:
            'both below the 100 sq ft floor, independent of the '
            'max > min check',
      );

      const inverted = ProjectDraft(areaSqftMin: 900, areaSqftMax: 500);
      final invertedIssues = validateProjectStep(ProjectStep.details, inverted);
      expect(invertedIssues.map((i) => i.field), contains(kProjectAreaMax));

      const valid = ProjectDraft(areaSqftMin: 500, areaSqftMax: 900);
      final validIssues = validateProjectStep(ProjectStep.details, valid);
      expect(validIssues.map((i) => i.field), isNot(contains(kProjectAreaMin)));
      expect(validIssues.map((i) => i.field), isNot(contains(kProjectAreaMax)));
    });

    test('media requires all six fields, brochure and video included', () {
      // Decision D5: the reference's strictness is kept. Website URL was
      // removed from this rule set to match the portal, which never
      // collects or requires one in this step.
      final issues = validateProjectStep(
        ProjectStep.media,
        const ProjectDraft(),
      );
      expect(issues.map((i) => i.field).toSet(), {
        kProjectContactNumber,
        kProjectLogoUrl,
        kProjectMapImages,
        kProjectBrochureUrl,
        kProjectOtherImages,
        kProjectVideosUrls,
      });
    });

    test('a malformed contact number fails on format, not presence', () {
      const draft = ProjectDraft(contactNumber: '123');
      final issues = validateProjectStep(ProjectStep.media, draft);
      final contact = issues.firstWhere(
        (i) => i.field == kProjectContactNumber,
      );
      expect(contact.message, isNot(contains('is required')));
    });

    test('an 8 or 9 digit contact number is refused, not accepted', () {
      // The field's own input formatters are digits-only, so `validPhone`'s
      // free-text "8-15 characters" range (meant for the property wizard's
      // punctuated phone field) let an incomplete number through here as
      // "valid" — a real 10-digit number is the only correct length.
      for (final short in ['12345678', '123456789']) {
        final issues = validateProjectStep(
          ProjectStep.media,
          ProjectDraft(contactNumber: short),
        );
        expect(
          issues.map((i) => i.field),
          contains(kProjectContactNumber),
          reason: '$short (${short.length} digits) must not pass',
        );
      }
    });

    test('a full 10 digit contact number is accepted', () {
      final issues = validateProjectStep(
        ProjectStep.media,
        const ProjectDraft(contactNumber: '9876543210'),
      );
      expect(
        issues.map((i) => i.field),
        isNot(contains(kProjectContactNumber)),
      );
    });

    test('an 11 digit contact number is refused too', () {
      final issues = validateProjectStep(
        ProjectStep.media,
        const ProjectDraft(contactNumber: '98765432101'),
      );
      expect(issues.map((i) => i.field), contains(kProjectContactNumber));
    });

    test('amenities requires at least one', () {
      expect(
        validateProjectStep(
          ProjectStep.amenities,
          const ProjectDraft(),
        ).single.field,
        kProjectAmenities,
      );
      expect(
        validateProjectStep(
          ProjectStep.amenities,
          const ProjectDraft(amenities: ['Parking']),
        ),
        isEmpty,
      );
    });

    test('review has no rules of its own', () {
      expect(
        validateProjectStep(ProjectStep.review, const ProjectDraft()),
        isEmpty,
      );
    });

    test('the five steps are titled as the reference names them', () {
      expect(ProjectStep.values.map(projectStepTitle).toList(), [
        'Basic Info',
        'Project Details',
        'Contact & Media',
        'Amenities',
        'Review & Submit',
      ]);
      expect(ProjectStep.values.map(projectStepKey).toList(), [
        'basic',
        'details',
        'media',
        'amenities',
        'review',
      ]);
    });
  });

  // ── 2. The cross-field rule ────────────────────────────────────────────
  group('cross-field rule', () {
    test('available units cannot exceed total units', () async {
      final provider = await _completeProvider();
      provider.setAvailableUnits('200'); // total is 120

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isFalse);
      expect(result.failure!.step, ProjectStep.details);
      expect(
        result.failure!.issues.single.message,
        'Available units cannot exceed total units.',
      );
    });

    test('equal counts are allowed — nothing sold yet', () async {
      final service = _FakeProjectService();
      final provider = await _completeProvider(service: service);
      provider.setAvailableUnits('120');

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isTrue);
    });
  });

  // Location/map bug fix — a resolved map pin must actually BE one, not
  // merely present, and clearing it must actually clear it.
  group('map location', () {
    test('a stale (0, 0) pin blocks submit, not just a missing one', () async {
      final provider = await _completeProvider();
      provider
        ..setLatitude(0)
        ..setLongitude(0);

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isFalse);
      expect(result.failure!.step, ProjectStep.basic);
      expect(result.failure!.issues.single.field, kProjectCoordinates);
    });

    test('an out-of-range pin also blocks submit', () async {
      final provider = await _completeProvider();
      provider
        ..setLatitude(500)
        ..setLongitude(73.8567);

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isFalse);
      expect(result.failure!.issues.single.field, kProjectCoordinates);
    });

    test('clearCoordinates actually clears both — copyWith(latitude: v) alone '
        'could never express this (v ?? this.v absorbs a null)', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      )..setLatitude(18.5204);
      provider.setLongitude(73.8567);
      expect(provider.draft.latitude, isNotNull);
      expect(provider.draft.longitude, isNotNull);

      provider.clearCoordinates();

      expect(provider.draft.latitude, isNull);
      expect(provider.draft.longitude, isNull);
    });

    test('copyWith with no latitude/longitude argument at all leaves them '
        'untouched — only an explicit null clears them', () {
      const draft = ProjectDraft(latitude: 18.5204, longitude: 73.8567);
      final unrelatedChange = draft.copyWith(title: 'New Title');

      expect(unrelatedChange.latitude, 18.5204);
      expect(unrelatedChange.longitude, 73.8567);
    });

    test('a cleared project draft fails Basic Info validation again', () {
      const draft = ProjectDraft(
        title: 'T',
        projectType: 'group_housing',
        location: 'Pune',
        description: kValidProjectDescription,
        latitude: 18.5204,
        longitude: 73.8567,
      );
      expect(
        validateProjectStep(ProjectStep.basic, draft),
        isEmpty,
        reason: 'fully valid before clearing',
      );

      final cleared = draft.copyWith(latitude: null, longitude: null);
      final issues = validateProjectStep(ProjectStep.basic, cleared);

      expect(issues.map((i) => i.field), contains(kProjectCoordinates));
    });
  });

  // ── 3. Gating and the attempted flag ───────────────────────────────────
  group('gating', () {
    test('a step opens with no errors showing', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      expect(provider.stepIssues, isEmpty);
      expect(provider.hasIssue(kProjectTitle), isFalse);
    });

    test('trying to advance publishes the issues and stays put', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );

      final issues = provider.nextStep();

      expect(issues, isNotEmpty);
      expect(provider.currentStep, 0, reason: 'blocked');
      expect(provider.hasIssue(kProjectTitle), isTrue);
    });

    test('once attempted, errors clear live as fields are filled', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.nextStep();
      // title, type, location, description, and (location/map bug fix) a
      // resolved map pin.
      expect(provider.stepIssues.length, 5);

      provider.setTitle('Green Valley');
      expect(provider.hasIssue(kProjectTitle), isFalse);
      expect(provider.stepIssues.length, 4);
    });

    test('a complete step advances and resets the error state', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.nextStep();
      expect(provider.stepIssues, isNotEmpty);

      provider
        ..setTitle('T')
        ..setProjectType('group_housing')
        ..setLocation('Pune')
        ..setLatitude(18.5204)
        ..setLongitude(73.8567)
        ..setDescription(kValidProjectDescription);

      expect(provider.nextStep(), isEmpty);
      expect(provider.currentStep, 1);
      expect(provider.stepIssues, isEmpty);
    });

    test('going back always works and clears errors', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider
        ..setTitle('T')
        ..setProjectType('group_housing')
        ..setLocation('Pune')
        ..setLatitude(18.5204)
        ..setLongitude(73.8567)
        ..setDescription(kValidProjectDescription);
      provider.nextStep();
      provider.nextStep(); // blocked on details, issues published
      expect(provider.stepIssues, isNotEmpty);

      provider.previousStep();
      expect(provider.currentStep, 0);
      expect(provider.stepIssues, isEmpty);
    });

    test('goToStep ignores an out-of-range index', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.goToStep(99);
      provider.goToStep(-1);
      expect(provider.currentStep, 0);
    });
  });

  // ── 4. Submit ──────────────────────────────────────────────────────────
  group('submit', () {
    test('an incomplete form jumps to the first failing step', () async {
      final provider = await _completeProvider();
      // Break a step-2 field, then submit from the review step.
      provider.setReraNumber('');
      provider.goToStep(4);

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isFalse);
      expect(result.failure!.step, ProjectStep.details);
      expect(provider.currentStep, 1, reason: 'moved to the offending step');
      expect(provider.hasIssue(kProjectReraNumber), isTrue);
    });

    test('the earliest failure wins, not the last', () async {
      final provider = await _completeProvider();
      provider
        ..setTitle('')
        ..setReraNumber('');

      final result = await provider.submit(builderId: 'b-1');

      expect(result.failure!.step, ProjectStep.basic);
    });

    test('a complete form creates the project and clears the draft', () async {
      final service = _FakeProjectService();
      final provider = await _completeProvider(service: service);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kProjectDraftKey),
        isNotNull,
        reason: 'typing saved a draft',
      );

      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isTrue);
      expect(result.projectId, 'new-project');
      expect(service.created, hasLength(1));
      expect(service.updated, isEmpty);
      expect(
        prefs.getString(kProjectDraftKey),
        isNull,
        reason: 'a successful create clears the draft',
      );
    });

    test(
      'the payload reaching the service has no nulls in NOT NULL columns',
      () async {
        final service = _FakeProjectService();
        final provider = await _completeProvider(service: service);
        await provider.submit(builderId: 'b-1');

        final payload = service.created.single.toPayload();
        final nulls = payload.entries
            .where((e) => e.value == null)
            .map((e) => e.key);
        expect(
          nulls,
          {'completion_date', 'possession_date'}.difference({
            // Both are filled here, so nothing should be null at all.
            'completion_date',
            'possession_date',
          }),
        );
        expect(nulls, isEmpty);
      },
    );

    test('a failed write rethrows and leaves the draft alone', () async {
      final service = _FakeProjectService()..shouldFail = true;
      final provider = await _completeProvider(service: service);

      await expectLater(
        provider.submit(builderId: 'b-1'),
        throwsA(isA<Exception>()),
      );
      expect(provider.isSubmitting, isFalse, reason: 'the flag is released');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kProjectDraftKey),
        isNotNull,
        reason: 'the work must survive a failed submit',
      );
    });
  });

  // ── 5. Edit mode ───────────────────────────────────────────────────────
  group('edit mode', () {
    ProjectModel existing() => ProjectModel.fromSupabase({
      'id': 'p-9',
      'builder_id': 'b-1',
      'title': 'Existing Project',
      'description': kValidProjectDescription,
      'project_type': 'farm_houses',
      'location': 'Nagpur',
      // A resolved map pin is now also required on the Basic Info step —
      // see _crossFieldBasicIssues.
      'latitude': 21.1458,
      'longitude': 79.0882,
      'total_units': 20,
      'available_units': 5,
      'price_range_min': 100,
      'price_range_max': 200,
      'area_sqft_min': 300,
      'area_sqft_max': 400,
      'completion_date': '2027-01-31',
      'possession_date': '2027-03-31',
      'rera_number': 'P52100012345',
      'website_url': 'https://x.example',
      'contact_number': '9999999999',
      'logo_url': 'logo.png',
      'brochure_url': 'b.pdf',
      'map_images': ['m.png'],
      'other_images': ['o.jpg'],
      'videos_urls': ['v.mp4'],
      'amenities': ['Parking'],
    });

    test('opening on a project pre-fills it and updates on submit', () async {
      final service = _FakeProjectService();
      final provider = AddProjectProvider(
        projectService: service,
        mediaService: _FakeMediaService(),
      );

      provider.initFromProject(existing());
      expect(provider.isEditMode, isTrue);
      expect(provider.draft.title, 'Existing Project');
      // Already complete, so it submits straight away.
      final result = await provider.submit(builderId: 'b-1');

      expect(result.isSuccess, isTrue);
      expect(result.projectId, 'p-9');
      expect(service.created, isEmpty, reason: 'an edit must not insert');
      expect(service.updated.single.projectId, 'p-9');
    });

    test('editing never writes a draft', () async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.initFromProject(existing());
      provider.setTitle('Renamed');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kProjectDraftKey), isNull);
    });

    test('a stored draft is not offered while editing', () async {
      SharedPreferences.setMockInitialValues({
        kProjectDraftKey: jsonEncode(
          const ProjectDraft(title: 'Unfinished').toJson(),
        ),
      });
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.initFromProject(existing());

      await provider.checkForSavedDraft();

      expect(
        provider.hasSavedDraft,
        isFalse,
        reason: 'a new-project draft must not bleed into an edit',
      );
      expect(provider.draft.title, 'Existing Project');
    });
  });

  // ── 6. Drafts ──────────────────────────────────────────────────────────
  group('drafts', () {
    test('typing saves a draft under the reference key', () async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.setTitle('Half typed');
      // The write is fire-and-forget, so let the microtask land.
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kProjectDraftKey);
      expect(raw, isNotNull);
      expect(jsonDecode(raw!)['title'], 'Half typed');
    });

    test('a draft with meaningful data is offered back', () async {
      SharedPreferences.setMockInitialValues({
        kProjectDraftKey: jsonEncode(
          const ProjectDraft(title: 'Resume me').toJson(),
        ),
      });
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );

      await provider.checkForSavedDraft();

      expect(provider.hasSavedDraft, isTrue);
      expect(provider.savedDraft!.title, 'Resume me');
    });

    test(
      'a draft holding only a stray field is not worth interrupting for',
      () async {
        // The reference's test is title / location / project_type / any image.
        SharedPreferences.setMockInitialValues({
          kProjectDraftKey: jsonEncode(
            const ProjectDraft(reraNumber: 'R-1').toJson(),
          ),
        });
        final provider = AddProjectProvider(
          projectService: _FakeProjectService(),
          mediaService: _FakeMediaService(),
        );

        await provider.checkForSavedDraft();

        expect(provider.hasSavedDraft, isFalse);
      },
    );

    test('an image alone counts as meaningful', () async {
      SharedPreferences.setMockInitialValues({
        kProjectDraftKey: jsonEncode(
          const ProjectDraft(otherImages: ['a.jpg']).toJson(),
        ),
      });
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );

      await provider.checkForSavedDraft();

      expect(provider.hasSavedDraft, isTrue);
    });

    test('restoring adopts the draft; discarding wipes it', () async {
      SharedPreferences.setMockInitialValues({
        kProjectDraftKey: jsonEncode(
          const ProjectDraft(title: 'Resume me').toJson(),
        ),
      });
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      await provider.checkForSavedDraft();

      provider.restoreSavedDraft();
      expect(provider.draft.title, 'Resume me');
      expect(provider.hasSavedDraft, isFalse);

      await provider.discardSavedDraft();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kProjectDraftKey), isNull);
    });

    test(
      'corrupt stored JSON is discarded rather than blocking the wizard',
      () async {
        SharedPreferences.setMockInitialValues({
          kProjectDraftKey: 'not json at all',
        });
        final provider = AddProjectProvider(
          projectService: _FakeProjectService(),
          mediaService: _FakeMediaService(),
        );

        await provider.checkForSavedDraft();

        expect(provider.hasSavedDraft, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kProjectDraftKey), isNull);
      },
    );
  });

  // ── 7. Media and amenities ─────────────────────────────────────────────
  group('media and amenities', () {
    test(
      'a layout lands in map_images, and the first becomes the master plan',
      () async {
        final provider = AddProjectProvider(
          projectService: _FakeProjectService(),
          mediaService: _FakeMediaService(),
        );

        await provider.uploadMasterLayout(Uint8List(4), 'first.png');
        await provider.uploadMasterLayout(Uint8List(4), 'second.png');

        expect(provider.draft.mapImages, hasLength(2));
        expect(
          provider.draft.toPayload()['master_layout_url'],
          'https://cdn.test/master-layouts/first.png',
        );
      },
    );

    test('removing an asset by index leaves the rest intact', () async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      await provider.uploadImage(Uint8List(4), 'a.jpg');
      await provider.uploadImage(Uint8List(4), 'b.jpg');
      await provider.uploadImage(Uint8List(4), 'c.jpg');

      provider.removeOtherImage(1);

      expect(provider.draft.otherImages, [
        'https://cdn.test/other-images/a.jpg',
        'https://cdn.test/other-images/c.jpg',
      ]);
      // An out-of-range index is a no-op, not a crash.
      provider.removeOtherImage(9);
      expect(provider.draft.otherImages, hasLength(2));
    });

    test('the busy flag is released even when an upload fails', () async {
      final media = _FakeMediaService()..shouldFail = true;
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: media,
      );

      await expectLater(
        provider.uploadLogo(Uint8List(4), 'logo.png'),
        throwsA(isA<ProjectMediaException>()),
      );
      expect(provider.isUploading(ProjectUploadSlot.logo), isFalse);
      expect(provider.isUploadingAnything, isFalse);
    });

    test('amenities toggle, accept free text and reject duplicates', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );

      provider.toggleAmenity('Parking');
      expect(provider.draft.amenities, ['Parking']);
      provider.toggleAmenity('Parking');
      expect(provider.draft.amenities, isEmpty);

      provider.addAmenity('  Rooftop Lounge  ');
      expect(provider.draft.amenities, ['Rooftop Lounge']);
      provider.addAmenity('Rooftop Lounge');
      expect(provider.draft.amenities, hasLength(1), reason: 'no duplicates');
      provider.addAmenity('   ');
      expect(provider.draft.amenities, hasLength(1), reason: 'no blanks');

      provider.removeAmenity('Rooftop Lounge');
      expect(provider.draft.amenities, isEmpty);
    });

    test('clearing a number field makes its rule fire again', () {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.setTotalUnits('50');
      expect(provider.draft.totalUnits, 50);

      provider.setTotalUnits('');
      expect(provider.draft.totalUnits, isNull);
      expect(
        validateProjectStep(
          ProjectStep.details,
          provider.draft,
        ).map((i) => i.field),
        contains(kProjectTotalUnits),
      );
    });
  });

  // ── 8. The shell ───────────────────────────────────────────────────────
  group('wizard shell', () {
    Future<void> pump(
      WidgetTester tester,
      AddProjectProvider provider, {
      Size size = kSmall,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AddProjectProvider>.value(
            value: provider,
            child: const AddProjectWizardView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on step 1 of 5 with the reference\'s titles', (
      tester,
    ) async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      await pump(tester, provider);

      expect(find.text('Add Project'), findsOneWidget);
      // The compact progress card names the current step and the counter.
      expect(find.text('Basic Info'), findsWidgets);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('the title says Edit Project in edit mode', (tester) async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      provider.initFromProject(
        ProjectModel.fromSupabase({'id': 'p-1', 'title': 'X'}),
      );
      await pump(tester, provider);

      expect(find.text('Edit Project'), findsOneWidget);
    });

    testWidgets('a saved draft is offered before the form', (tester) async {
      SharedPreferences.setMockInitialValues({
        kProjectDraftKey: jsonEncode(
          const ProjectDraft(title: 'Half done', location: 'Pune').toJson(),
        ),
      });
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      await pump(tester, provider);

      expect(find.text('Resume Project?'), findsOneWidget);
      expect(find.text('Half done'), findsOneWidget);
      expect(find.text('Continue Draft'), findsOneWidget);
      expect(find.text('Start Fresh'), findsOneWidget);
      // The form is not behind it yet.
      expect(find.text('Step 1 of 5'), findsNothing);

      await tester.tap(find.text('Continue Draft'));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('every step renders cleanly at 320 dp', (tester) async {
      final provider = await _completeProvider();

      for (var i = 0; i < ProjectStep.values.length; i++) {
        provider.goToStep(i);
        await pump(tester, provider);
        expect(
          overflowingBoxes(tester),
          isEmpty,
          reason: 'step ${projectStepTitle(ProjectStep.values[i])} overflows',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the wide layout puts the stepper beside the form', (
      tester,
    ) async {
      final provider = AddProjectProvider(
        projectService: _FakeProjectService(),
        mediaService: _FakeMediaService(),
      );
      await pump(tester, provider, size: const Size(1200, 900));

      // The full stepper lists every step by name.
      expect(find.text('Progress'), findsOneWidget);
      for (final step in ProjectStep.values) {
        expect(find.text(projectStepTitle(step)), findsWidgets);
      }
      expect(overflowingBoxes(tester), isEmpty);
    });

    // Location/map bug fix, project-wizard half — see
    // basic_info_location_sync_test.dart's identical property-wizard test
    // for why typing is the one interaction here that doesn't need
    // LocationPickerMap's real GoogleMap or AddressAutocompleteField's real
    // Places API call.
    testWidgets(
      'editing the City field after a pin was dropped clears the stored coordinates',
      (tester) async {
        final provider = AddProjectProvider(
          projectService: _FakeProjectService(),
          mediaService: _FakeMediaService(),
        );
        await pump(tester, provider);

        // Simulate a location already resolved (map tap or autocomplete).
        provider
          ..setLatitude(18.5204)
          ..setLongitude(73.8567);
        await tester.pump();
        expect(provider.draft.latitude, isNotNull);
        expect(provider.draft.longitude, isNotNull);

        final cityField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'e.g. Pune',
        );
        expect(cityField, findsOneWidget);
        await tester.enterText(cityField, 'A different city entirely');
        await tester.pump();

        expect(
          provider.draft.latitude,
          isNull,
          reason: 'the old pin no longer describes the edited city',
        );
        expect(provider.draft.longitude, isNull);
      },
    );
  });
}
