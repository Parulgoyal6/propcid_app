// providers/add_project_provider.dart
//
// State for the builder project wizard.
//
// Screen-scoped: created by `AddProjectScreen` through
// `ChangeNotifierProvider(create:)`, so it is not in the global tree and cannot
// affect any other screen. `PostPropertyProvider` is untouched — the two wizards
// share widgets and the validation engine, never state.
//
// GATING BEHAVIOUR IS THE REFERENCE'S
// -----------------------------------
// `BuilderProjectWizard.tsx:258-297`:
//   * `handleNextStep` validates the current step and refuses to advance;
//   * an `attemptedRef` flag starts false, is set once the user has tried, and is
//     cleared on every step change — so errors appear only after a real attempt,
//     then update live as fields get filled;
//   * `handleSubmit` re-runs *every* step and jumps to the first that fails.
//
// DRAFTS
// ------
// The reference saves to `localStorage['builder_project_wizard_draft']` on every
// keystroke, but only when creating (`:220`). On open it offers to restore when
// the draft has "meaningful data" — title, location, project_type, or any image
// (`:183-185`). Both are reproduced, on `shared_preferences` under the same key.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_model.dart';
import '../screens/add_project/project_validation_rules.dart';
import '../screens/post_property/listing_validation_rules.dart'
    show ListingIssue;
import '../services/project_media_service.dart';
import '../services/project_service.dart';

/// The reference's storage key, verbatim, so a draft is recognisable across both
/// products even though the stores differ.
const String kProjectDraftKey = 'builder_project_wizard_draft';

/// Which asset type an upload is for, so the UI can show progress per control
/// rather than one global spinner.
enum ProjectUploadSlot { logo, masterLayout, images, videos, brochure }

class AddProjectProvider extends ChangeNotifier {
  AddProjectProvider({
    ProjectService? projectService,
    ProjectMediaService? mediaService,
  }) : _projects = projectService ?? ProjectService(),
       _media = mediaService ?? ProjectMediaService();

  final ProjectService _projects;
  final ProjectMediaService _media;

  ProjectDraft _draft = const ProjectDraft();
  int _currentStep = 0;
  List<ListingIssue> _stepIssues = const [];

  /// False until the user has tried to advance or submit from this step. Cleared
  /// on every step change, exactly as `attemptedRef` is.
  bool _attempted = false;

  final Set<ProjectUploadSlot> _uploading = {};
  bool _submitting = false;

  /// Set when the wizard opened on an existing project.
  String? _editingProjectId;

  /// A restorable draft found on open, and null once resolved either way.
  ProjectDraft? _savedDraft;
  bool _draftChecked = false;

  // ── Reads ──────────────────────────────────────────────────────────────

  ProjectDraft get draft => _draft;
  int get currentStep => _currentStep;
  List<ProjectStep> get steps => ProjectStep.values;
  ProjectStep get currentProjectStep => ProjectStep.values[_currentStep];
  int get totalSteps => ProjectStep.values.length;
  bool get isLastStep => _currentStep == ProjectStep.values.length - 1;
  bool get isEditMode => _editingProjectId != null;
  bool get isSubmitting => _submitting;

  /// Only non-empty once [_attempted] — a step never opens covered in red.
  List<ListingIssue> get stepIssues => _stepIssues;

  bool isUploading(ProjectUploadSlot slot) => _uploading.contains(slot);
  bool get isUploadingAnything => _uploading.isNotEmpty;

  ProjectDraft? get savedDraft => _savedDraft;
  bool get hasSavedDraft => _savedDraft != null;

  /// True when [field] is one of the current step's unmet requirements.
  bool hasIssue(String field) =>
      _stepIssues.any((issue) => issue.field == field);

  // ── Field setters ──────────────────────────────────────────────────────
  //
  // Every one funnels through [_update], which re-validates when the user has
  // already attempted this step and persists the draft when creating.

  void setTitle(String v) => _update(_draft.copyWith(title: v));
  void setDescription(String v) => _update(_draft.copyWith(description: v));
  void setProjectType(String v) => _update(_draft.copyWith(projectType: v));
  void setLocation(String v) => _update(_draft.copyWith(location: v));

  /// Street address, state, pincode and landmark — the four fields the
  /// migration `20270416000000_add_builder_project_location_fields.sql` added
  /// so this wizard can capture the same location detail the Property
  /// Listing wizard already does. All filled by [ProjectBasicInfoStep]'s map
  /// picker / address search, same as [setLocation] already was.
  void setAddressLine1(String v) => _update(_draft.copyWith(addressLine1: v));
  void setState(String v) => _update(_draft.copyWith(state: v));
  void setPincode(String v) => _update(_draft.copyWith(pincode: v));
  void setLandmark(String v) => _update(_draft.copyWith(landmark: v));
  void setLatitude(double v) => _update(_draft.copyWith(latitude: v));
  void setLongitude(double v) => _update(_draft.copyWith(longitude: v));

  /// Forgets a previously-resolved pin — called when the address/city text
  /// is edited by hand after a map selection, so the old coordinates can
  /// never silently outlive the location they used to describe. Relies on
  /// [ProjectDraft.copyWith]'s `unchangedNumber` sentinel to tell "clear
  /// this" apart from "leave it alone": passing a literal `null` here is
  /// the one case that must actually reach the draft as null, not be
  /// absorbed by a `?? this.latitude`.
  void clearCoordinates() =>
      _update(_draft.copyWith(latitude: null, longitude: null));

  void setTotalUnits(String v) =>
      _update(_draft.copyWith(totalUnits: _intOrNull(v)));
  void setAvailableUnits(String v) =>
      _update(_draft.copyWith(availableUnits: _intOrNull(v)));
  void setPriceMin(String v) =>
      _update(_draft.copyWith(priceRangeMin: _numOrNull(v)));
  void setPriceMax(String v) =>
      _update(_draft.copyWith(priceRangeMax: _numOrNull(v)));
  void setAreaMin(String v) =>
      _update(_draft.copyWith(areaSqftMin: _numOrNull(v)));
  void setAreaMax(String v) =>
      _update(_draft.copyWith(areaSqftMax: _numOrNull(v)));

  void setCompletionDate(String iso) =>
      _update(_draft.copyWith(completionDate: iso));
  void setPossessionDate(String iso) =>
      _update(_draft.copyWith(possessionDate: iso));
  void setReraNumber(String v) => _update(_draft.copyWith(reraNumber: v));

  void setWebsiteUrl(String v) => _update(_draft.copyWith(websiteUrl: v));
  void setContactNumber(String v) => _update(_draft.copyWith(contactNumber: v));

  /// Amenities are a free `text[]`: the 19 suggestions are chips, and anything
  /// the user types is accepted too.
  void toggleAmenity(String amenity) {
    final next = List<String>.of(_draft.amenities);
    next.contains(amenity) ? next.remove(amenity) : next.add(amenity);
    _update(_draft.copyWith(amenities: next));
  }

  /// Adds a free-text amenity. Ignores blanks and exact duplicates, matching
  /// `handleAmenityAdd` (`:232-236`).
  void addAmenity(String amenity) {
    final value = amenity.trim();
    if (value.isEmpty || _draft.amenities.contains(value)) return;
    _update(_draft.copyWith(amenities: [..._draft.amenities, value]));
  }

  void removeAmenity(String amenity) {
    final next = List<String>.of(_draft.amenities)..remove(amenity);
    _update(_draft.copyWith(amenities: next));
  }

  /// Drops one uploaded asset. `removeImage` (`:453-456`).
  void removeMapImage(int index) =>
      _update(_draft.copyWith(mapImages: _without(_draft.mapImages, index)));

  void removeOtherImage(int index) => _update(
    _draft.copyWith(otherImages: _without(_draft.otherImages, index)),
  );

  void removeVideo(int index) =>
      _update(_draft.copyWith(videosUrls: _without(_draft.videosUrls, index)));

  void clearLogo() => _update(_draft.copyWith(logoUrl: ''));

  void clearBrochure() => _update(_draft.copyWith(brochureUrl: ''));

  // ── Uploads ────────────────────────────────────────────────────────────

  /// Uploads a logo and stores its URL. Throws [ProjectMediaException] for a
  /// refusal the user can act on; the caller surfaces the message.
  Future<void> uploadLogo(Uint8List bytes, String fileName) =>
      _withUpload(ProjectUploadSlot.logo, () async {
        final url = await _media.uploadLogo(bytes: bytes, fileName: fileName);
        _update(_draft.copyWith(logoUrl: url));
      });

  /// Uploads a master-plan layout and appends it to `map_images`.
  ///
  /// `master_layout_url` is derived from the first entry at write time, so the
  /// order of this list matters.
  Future<void> uploadMasterLayout(Uint8List bytes, String fileName) =>
      _withUpload(ProjectUploadSlot.masterLayout, () async {
        final url = await _media.uploadMasterLayout(
          bytes: bytes,
          fileName: fileName,
        );
        _update(_draft.copyWith(mapImages: [..._draft.mapImages, url]));
      });

  Future<void> uploadImage(Uint8List bytes, String fileName) =>
      _withUpload(ProjectUploadSlot.images, () async {
        final url = await _media.uploadImage(bytes: bytes, fileName: fileName);
        _update(_draft.copyWith(otherImages: [..._draft.otherImages, url]));
      });

  Future<void> uploadVideo(Uint8List bytes, String fileName) =>
      _withUpload(ProjectUploadSlot.videos, () async {
        final url = await _media.uploadVideo(bytes: bytes, fileName: fileName);
        _update(_draft.copyWith(videosUrls: [..._draft.videosUrls, url]));
      });

  Future<void> uploadBrochure(Uint8List bytes, String fileName) => _withUpload(
    ProjectUploadSlot.brochure,
    () async {
      final url = await _media.uploadBrochure(bytes: bytes, fileName: fileName);
      _update(_draft.copyWith(brochureUrl: url));
    },
  );

  Future<void> _withUpload(
    ProjectUploadSlot slot,
    Future<void> Function() body,
  ) async {
    _uploading.add(slot);
    notifyListeners();
    try {
      await body();
    } finally {
      _uploading.remove(slot);
      notifyListeners();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  /// Advances when the current step is complete.
  ///
  /// Returns the unmet requirements when it refuses, so the caller can raise the
  /// reference's "N fields still needed" toast, and an empty list when it moved.
  List<ListingIssue> nextStep() {
    final issues = validateProjectStep(currentProjectStep, _draft);

    if (issues.isNotEmpty) {
      _attempted = true;
      _stepIssues = issues;
      notifyListeners();
      return issues;
    }

    _attempted = false;
    _stepIssues = const [];
    if (_currentStep < ProjectStep.values.length - 1) _currentStep++;
    notifyListeners();
    return const [];
  }

  /// `handlePrevStep` — always allowed, and clears the error state.
  void previousStep() {
    if (_currentStep == 0) return;
    _attempted = false;
    _stepIssues = const [];
    _currentStep--;
    notifyListeners();
  }

  /// Jumps to an already-visited step. The progress card only offers these.
  void goToStep(int index) {
    if (index < 0 || index >= ProjectStep.values.length) return;
    if (index == _currentStep) return;
    _attempted = false;
    _stepIssues = const [];
    _currentStep = index;
    notifyListeners();
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  /// Validates every step, then writes the project.
  ///
  /// On a validation failure it moves to the offending step, publishes its issues
  /// and returns the failure — the caller shows
  /// `Incomplete: {step title}`, which is the reference's toast (`:469`).
  ///
  /// On success returns the project id: the new row's for a create, the edited
  /// one's for an update.
  Future<ProjectSubmitResult> submit({required String builderId}) async {
    final failure = validateAllProjectSteps(_draft);
    if (failure != null) {
      _currentStep = failure.stepIndex;
      _attempted = true;
      _stepIssues = failure.issues;
      notifyListeners();
      return ProjectSubmitResult.invalid(failure);
    }

    _submitting = true;
    notifyListeners();

    try {
      final editingId = _editingProjectId;
      if (editingId != null) {
        await _projects.update(
          projectId: editingId,
          builderId: builderId,
          draft: _draft,
        );
        return ProjectSubmitResult.success(editingId);
      }

      final created = await _projects.create(
        builderId: builderId,
        draft: _draft,
      );
      // Only a create clears the draft — an edit never wrote one.
      await clearDraft();
      return ProjectSubmitResult.success(created.id);
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  // ── Edit mode ──────────────────────────────────────────────────────────

  /// Seeds the wizard from an existing project.
  ///
  /// Suppresses the draft prompt: a saved draft belongs to an unfinished *new*
  /// project and must never bleed into an edit.
  void initFromProject(ProjectModel project) {
    _editingProjectId = project.id;
    _draft = ProjectDraft.fromProject(project);
    _savedDraft = null;
    _draftChecked = true;
    _currentStep = 0;
    _attempted = false;
    _stepIssues = const [];
    notifyListeners();
  }

  // ── Draft persistence ──────────────────────────────────────────────────

  /// Looks for a restorable draft. Call once, on open, and only when creating.
  ///
  /// "Meaningful data" is the reference's test (`:183-185`): a title, a location,
  /// a project type, or any uploaded image. A draft holding only, say, a RERA
  /// number is not worth interrupting the user for.
  Future<void> checkForSavedDraft() async {
    if (_draftChecked || isEditMode) return;
    _draftChecked = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kProjectDraftKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final candidate = ProjectDraft.fromJson(decoded);
      final meaningful =
          candidate.title.trim().isNotEmpty ||
          candidate.location.trim().isNotEmpty ||
          candidate.projectType.isNotEmpty ||
          candidate.mapImages.isNotEmpty ||
          candidate.otherImages.isNotEmpty;

      if (!meaningful) return;

      _savedDraft = candidate;
      notifyListeners();
    } catch (e) {
      // A draft written by an incompatible build must not block the wizard.
      debugPrint('AddProjectProvider.checkForSavedDraft failed: $e');
      await clearDraft();
    }
  }

  /// Adopts the offered draft.
  void restoreSavedDraft() {
    final saved = _savedDraft;
    if (saved == null) return;
    _draft = saved;
    _savedDraft = null;
    _currentStep = 0;
    _attempted = false;
    _stepIssues = const [];
    notifyListeners();
  }

  /// Starts fresh, discarding what was stored.
  Future<void> discardSavedDraft() async {
    _savedDraft = null;
    notifyListeners();
    await clearDraft();
  }

  /// Removes the stored draft. Called on a successful create and on discard.
  Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kProjectDraftKey);
    } catch (e) {
      debugPrint('AddProjectProvider.clearDraft failed: $e');
    }
  }

  /// Persists the draft. Fire-and-forget: a failed write must never interrupt
  /// typing, which is why nothing awaits this.
  Future<void> _saveDraft() async {
    if (isEditMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kProjectDraftKey, jsonEncode(_draft.toJson()));
    } catch (e) {
      debugPrint('AddProjectProvider._saveDraft failed: $e');
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// The single write path: swap the draft, re-validate if the user has already
  /// attempted this step, persist, notify.
  void _update(ProjectDraft next) {
    _draft = next;
    if (_attempted) {
      _stepIssues = validateProjectStep(currentProjectStep, _draft);
    }
    _saveDraft();
    notifyListeners();
  }

  static List<String> _without(List<String> source, int index) {
    if (index < 0 || index >= source.length) return source;
    return List<String>.of(source)..removeAt(index);
  }

  /// Blank clears the field back to null, so a required-number rule fires again
  /// rather than the last value sticking.
  static int? _intOrNull(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t.replaceAll(RegExp(r'[^\d-]'), ''));
  }

  static double? _numOrNull(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(RegExp(r'[^\d.-]'), ''));
  }
}

/// The outcome of [AddProjectProvider.submit].
@immutable
class ProjectSubmitResult {
  const ProjectSubmitResult._({this.projectId, this.failure});

  factory ProjectSubmitResult.success(String projectId) =>
      ProjectSubmitResult._(projectId: projectId);

  factory ProjectSubmitResult.invalid(ProjectValidationFailure failure) =>
      ProjectSubmitResult._(failure: failure);

  /// Set on success.
  final String? projectId;

  /// Set when validation refused the submit.
  final ProjectValidationFailure? failure;

  bool get isSuccess => projectId != null;
}
