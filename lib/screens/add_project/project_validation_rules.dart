// screens/add_project/project_validation_rules.dart
//
// The builder project wizard's required-field rules.
//
// A direct port of `propcid/src/lib/validation/projectRules.ts`, including its
// step keys, its labels and its cross-field unit check. The reference's own
// header explains why it is this strict: before those rules existed, "401 of 401
// project rows had NULL latitude/longitude and most had NULL numeric ranges".
//
// The engine is NOT re-implemented. `isBlank`, `positiveNumber` and
// `nonNegativeNumber` in `screens/post_property/listing_validators.dart` are
// already character-for-character ports of the same `requiredFields.ts` that
// `projectRules.ts` imports, and `ListingIssue` is already the `FieldIssue`
// shape. Reusing them is what keeps the two wizards gating identically on
// the same input. `validPhone` is the one exception: this wizard's contact
// number uses `validProjectContactNumber` instead, since its own field is
// digits-only (10 characters, enforced by its input formatters) rather than
// the free-text, punctuation-tolerant field `validPhone` is shared with on
// the property wizard — see that validator's own doc comment.
import '../post_property/listing_validation_rules.dart'
    show ListingIssue, RuleValidator;
import '../post_property/listing_validators.dart';
import '../../core/utils/geo_utils.dart';
import '../../services/project_service.dart';
import 'project_field_keys.dart';

/// Reads one field off a draft. The equivalent of the reference indexing a flat
/// `ProjectFormShape`.
typedef ProjectFieldReader = Object? Function(ProjectDraft draft);

/// One required-field declaration. Mirrors `FieldRule<ProjectFormShape>`.
class ProjectRule {
  const ProjectRule({
    required this.field,
    required this.label,
    required this.get,
    this.validate,
  });

  /// Field key — also the identity the step body uses to highlight an input.
  final String field;

  /// Human label shown in the error summary.
  final String label;

  /// Reads the value from the draft.
  final ProjectFieldReader get;

  /// Extra format check, run only when the value is present.
  final RuleValidator? validate;
}

/// The wizard's five steps, in order. `STEPS` in
/// `BuilderProjectWizard.tsx:251-257`.
enum ProjectStep { basic, details, media, amenities, review }

/// `STEPS[i].key` — the string the reference keys its rule table by.
String projectStepKey(ProjectStep step) => switch (step) {
  ProjectStep.basic => 'basic',
  ProjectStep.details => 'details',
  ProjectStep.media => 'media',
  ProjectStep.amenities => 'amenities',
  ProjectStep.review => 'review',
};

/// `STEPS[i].title`.
String projectStepTitle(ProjectStep step) => switch (step) {
  ProjectStep.basic => 'Basic Info',
  ProjectStep.details => 'Project Details',
  ProjectStep.media => 'Contact & Media',
  ProjectStep.amenities => 'Amenities',
  ProjectStep.review => 'Review & Submit',
};

/// The lucide glyph per step, from the reference's `icon` on each `STEPS` entry:
/// Building, MapPin, Phone, Sparkles, ShieldCheck.
String projectStepIcon(ProjectStep step) => switch (step) {
  ProjectStep.basic => 'building',
  ProjectStep.details => 'map-pin',
  ProjectStep.media => 'phone',
  ProjectStep.amenities => 'sparkles',
  ProjectStep.review => 'shield-check',
};

/// `basicRules` — projectRules.ts:44-49.
final List<ProjectRule> _basicRules = [
  ProjectRule(field: kProjectTitle, label: 'Project title', get: _readTitle),
  ProjectRule(field: kProjectType, label: 'Project type', get: _readType),
  // The reference labels `location` "City", not "Location".
  ProjectRule(field: kProjectLocation, label: 'City', get: _readLocation),
  ProjectRule(
    field: kProjectDescription,
    label: 'Description',
    get: _readDescription,
    // `minAlphaChars(20, 'Description')` — projectRules.ts:82. This WAS
    // ported as a word-count check (`minWordCount`), which isn't in the
    // reference at all; the reference's real rule counts letters, so an
    // existing web-created project with a short-but-plenty-of-characters
    // description could fail this in the app when it validates fine on
    // the portal. Fixed to match projectRules.ts exactly.
    validate: minAlphaChars(20, 'Description'),
  ),
];

/// `detailRules` — projectRules.ts:51-61.
final List<ProjectRule> _detailRules = [
  ProjectRule(
    field: kProjectTotalUnits,
    label: 'Total units',
    get: _readTotalUnits,
    validate: positiveNumber('Total units'),
  ),
  // Non-negative, not positive: a sold-out project has 0 available.
  ProjectRule(
    field: kProjectAvailableUnits,
    label: 'Available units',
    get: _readAvailableUnits,
    validate: nonNegativeNumber('Available units'),
  ),
  ProjectRule(
    field: kProjectPriceMin,
    label: 'Price range (min)',
    get: _readPriceMin,
    validate: positiveNumber('Price range (min)'),
  ),
  ProjectRule(
    field: kProjectPriceMax,
    label: 'Price range (max)',
    get: _readPriceMax,
    validate: positiveNumber('Price range (max)'),
  ),
  ProjectRule(
    field: kProjectAreaMin,
    label: 'Area (min)',
    get: _readAreaMin,
    // Not part of the React port — added on explicit request so a minimum
    // area can't be listed at a couple of square feet.
    validate: minNumber(100, 'Area (min)'),
  ),
  ProjectRule(
    field: kProjectAreaMax,
    label: 'Area (max)',
    get: _readAreaMax,
    // Same 100 sq ft floor as Area (min) above, added on the same explicit
    // request — not part of the React port.
    validate: minNumber(100, 'Area (max)'),
  ),
  const ProjectRule(
    field: kProjectCompletionDate,
    label: 'Completion date',
    get: _readCompletionDate,
  ),
  const ProjectRule(
    field: kProjectPossessionDate,
    label: 'Possession date',
    get: _readPossessionDate,
  ),
  const ProjectRule(
    field: kProjectReraNumber,
    label: 'RERA number',
    get: _readRera,
    validate: validRera,
  ),
];

/// `mediaRules` — projectRules.ts:63-71.
///
/// Every one of these is required, including the brochure PDF and at least one
/// video. That is the reference's rule, kept as decision D5.
///
/// Website URL was removed from this list by request, to match the portal's
/// `BuilderProjectWizard.tsx` — its "Contact & Media" step never collects a
/// website at all, and its own current `projectRules.ts` no longer lists one
/// either (confirmed against current portal source; this file's prior
/// citation of it was stale). The `website_url` column, model field and
/// submit payload are untouched — only this step's required-input went away.
final List<ProjectRule> _mediaRules = [
  ProjectRule(
    field: kProjectContactNumber,
    label: 'Contact number',
    get: _readContact,
    // Not `validPhone`: this field is digits-only (its own input
    // formatters cap it at 10 characters), unlike the free-text property
    // phone field `validPhone` is shared with — see
    // `validProjectContactNumber`'s own doc comment.
    validate: validProjectContactNumber,
  ),
  const ProjectRule(
    field: kProjectLogoUrl,
    label: 'Project logo',
    get: _readLogo,
  ),
  // The reference names `map_images` "Master plan layout".
  const ProjectRule(
    field: kProjectMapImages,
    label: 'Master plan layout',
    get: _readMapImages,
  ),
  const ProjectRule(
    field: kProjectBrochureUrl,
    label: 'Project brochure (PDF)',
    get: _readBrochure,
  ),
  const ProjectRule(
    field: kProjectOtherImages,
    label: 'Project images',
    get: _readOtherImages,
  ),
  const ProjectRule(
    field: kProjectVideosUrls,
    label: 'Project videos',
    get: _readVideos,
  ),
];

/// `amenityRules` — projectRules.ts:73.
const List<ProjectRule> _amenityRules = [
  ProjectRule(
    field: kProjectAmenities,
    label: 'At least one amenity',
    get: _readAmenities,
  ),
];

/// `PROJECT_STEP_RULES` — projectRules.ts:76-82. Review has no rules of its own;
/// it re-runs every earlier step.
Map<ProjectStep, List<ProjectRule>> get projectStepRules => {
  ProjectStep.basic: _basicRules,
  ProjectStep.details: _detailRules,
  ProjectStep.media: _mediaRules,
  ProjectStep.amenities: _amenityRules,
  ProjectStep.review: const [],
};

/// "Pick a location on the map" for the Basic Info step — no single
/// [ProjectRule] can express a two-field (lat + lng) check, same reasoning
/// as [_crossFieldDetailIssues] below. An address/city string alone has
/// never been enough to satisfy this: `location` already has its own
/// required rule in [_basicRules], and this fires independently of whether
/// that one has.
///
/// Reuses [isValidCoordinatePair] so a null pair (nothing picked yet) and an
/// invalid one (corrupted, out of range, or the `(0, 0)` "Null Island"
/// default a stale-coordinate bug produces) are refused the same way — the
/// project wizard previously only existed to find out it had never actually
/// required a resolved map pin at all.
List<ListingIssue> _crossFieldBasicIssues(ProjectDraft draft) {
  if (isValidCoordinatePair(draft.latitude, draft.longitude)) return const [];
  return const [
    ListingIssue(
      kProjectCoordinates,
      'Project location',
      'Pick the project\'s location on the map or from an address search.',
    ),
  ];
}

/// Cross-field checks on the Details step that no single [ProjectRule] can
/// express, since each needs two fields at once. Both are only evaluated once
/// their inputs are present — an incomplete pair is already caught by the
/// per-field required checks above.
///
/// - "You cannot have more units available than exist" was previously only
///   checked in [validateAllProjectSteps], so leaving the Details step with
///   Available > Total was silently accepted until the final submit. Folding
///   it into [validateProjectStep] means it now blocks Continue immediately,
///   same as every other Details field.
/// - Possession before Completion is a new check, not part of the React
///   port, added on explicit request.
/// - Price (max) > Price (min) and Area (max) > Area (min) are new checks,
///   not part of the React port, added on explicit request.
List<ListingIssue> _crossFieldDetailIssues(ProjectDraft draft) {
  final issues = <ListingIssue>[];

  final total = draft.totalUnits;
  final available = draft.availableUnits;
  if (total != null && available != null && available > total) {
    issues.add(
      const ListingIssue(
        kProjectAvailableUnits,
        'Available units',
        'Available units cannot exceed total units.',
      ),
    );
  }

  final priceMin = draft.priceRangeMin;
  final priceMax = draft.priceRangeMax;
  if (priceMin != null && priceMax != null && priceMax <= priceMin) {
    issues.add(
      const ListingIssue(
        kProjectPriceMax,
        'Price range (max)',
        'Maximum price must be greater than minimum price.',
      ),
    );
  }

  final areaMin = draft.areaSqftMin;
  final areaMax = draft.areaSqftMax;
  if (areaMin != null && areaMax != null && areaMax <= areaMin) {
    issues.add(
      const ListingIssue(
        kProjectAreaMax,
        'Area (max)',
        'Maximum area must be greater than minimum area.',
      ),
    );
  }

  final completion = DateTime.tryParse(draft.completionDate);
  final possession = DateTime.tryParse(draft.possessionDate);
  if (completion != null &&
      possession != null &&
      possession.isBefore(completion)) {
    issues.add(
      const ListingIssue(
        kProjectPossessionDate,
        'Possession date',
        'Possession date cannot be earlier than the completion date.',
      ),
    );
  }

  return issues;
}

/// Unmet requirements for one step. `validateProjectStep` — projectRules.ts:84.
///
/// A rule fires when the value [isBlank]; a present value is then handed to
/// [ProjectRule.validate] if it has one. Same order as `collectIssues`, plus
/// [_crossFieldBasicIssues] on the Basic Info step and
/// [_crossFieldDetailIssues] on the Details step.
List<ListingIssue> validateProjectStep(ProjectStep step, ProjectDraft draft) {
  final issues = <ListingIssue>[];

  for (final rule in projectStepRules[step] ?? const <ProjectRule>[]) {
    final value = rule.get(draft);

    if (isBlank(value)) {
      issues.add(
        ListingIssue(rule.field, rule.label, '${rule.label} is required.'),
      );
      continue;
    }

    final message = rule.validate?.call(value);
    if (message != null) {
      issues.add(ListingIssue(rule.field, rule.label, message));
    }
  }

  if (step == ProjectStep.basic) {
    issues.addAll(_crossFieldBasicIssues(draft));
  }
  if (step == ProjectStep.details) {
    issues.addAll(_crossFieldDetailIssues(draft));
  }

  return issues;
}

/// The first step that fails, or null when the whole form is valid.
///
/// `validateAllProjectSteps` — projectRules.ts:87-107. The cross-field checks
/// are folded into [validateProjectStep] itself now, so this loop alone is
/// enough to surface them.
ProjectValidationFailure? validateAllProjectSteps(ProjectDraft draft) {
  const order = ProjectStep.values;

  for (var i = 0; i < order.length; i++) {
    final issues = validateProjectStep(order[i], draft);
    if (issues.isNotEmpty) {
      return ProjectValidationFailure(
        step: order[i],
        stepIndex: i,
        issues: issues,
      );
    }
  }

  return null;
}

/// Which step failed, where it sits, and why.
class ProjectValidationFailure {
  const ProjectValidationFailure({
    required this.step,
    required this.stepIndex,
    required this.issues,
  });

  final ProjectStep step;
  final int stepIndex;
  final List<ListingIssue> issues;
}

// ── Field readers ─────────────────────────────────────────────────────────
//
// Top-level functions rather than closures so the rule tables can stay `const`
// where nothing else in them is computed.

Object? _readTitle(ProjectDraft d) => d.title;
Object? _readType(ProjectDraft d) => d.projectType;
Object? _readLocation(ProjectDraft d) => d.location;
Object? _readDescription(ProjectDraft d) => d.description;
Object? _readTotalUnits(ProjectDraft d) => d.totalUnits;
Object? _readAvailableUnits(ProjectDraft d) => d.availableUnits;
Object? _readPriceMin(ProjectDraft d) => d.priceRangeMin;
Object? _readPriceMax(ProjectDraft d) => d.priceRangeMax;
Object? _readAreaMin(ProjectDraft d) => d.areaSqftMin;
Object? _readAreaMax(ProjectDraft d) => d.areaSqftMax;
Object? _readCompletionDate(ProjectDraft d) => d.completionDate;
Object? _readPossessionDate(ProjectDraft d) => d.possessionDate;
Object? _readRera(ProjectDraft d) => d.reraNumber;
Object? _readContact(ProjectDraft d) => d.contactNumber;
Object? _readLogo(ProjectDraft d) => d.logoUrl;
Object? _readMapImages(ProjectDraft d) => d.mapImages;
Object? _readBrochure(ProjectDraft d) => d.brochureUrl;
Object? _readOtherImages(ProjectDraft d) => d.otherImages;
Object? _readVideos(ProjectDraft d) => d.videosUrls;
Object? _readAmenities(ProjectDraft d) => d.amenities;
