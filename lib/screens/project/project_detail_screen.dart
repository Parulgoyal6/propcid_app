// screens/project/project_detail_screen.dart
//
// One builder project. The display half of the portal's `ProjectDetails.tsx`.
//
// WHAT IS PORTED, AND WHAT IS NOT
// ------------------------------
// Ported: the project read, the builder-profile read with its auth-aware column
// list, the flattened media gallery (`getAllMedia`, :637-644), every field the
// page shows, like/save (`user_likes.project_id` / `saved_projects`, via
// `ProjectsProvider` — the gallery header's heart/bookmark actions), the
// "Available units" section (`PublicProjectInventory.tsx`, via the same
// public `project-inventory-list` Edge Function — see
// `ProjectInventoryService.publicUnitsForProject`), and comments
// (`ProjectDetails.tsx`'s `CommentsPanel`, `post_comments` scoped to
// `post_type = 'project'` — the exact table/scoping the Feed's own project
// card already used for its Comment button, via the newly-shared
// `PostCommentsSheet`, see `widgets/post_comments_sheet.dart`).
//
// Both of those last two shipped late, and for the same reason: each was
// visibly working somewhere else in this app (the portal's own page for
// comments; the Feed's project CARD for its Comment button) while this
// detail page — what opening that same card actually lands you on — quietly
// had neither. Neither gap was even documented below until found.
//
// Comments here are NOT realtime, unlike the portal's own
// `CommentsPanel` (a `supabase.channel(...)` subscription on `post_comments`)
// — this reuses the Feed's existing sheet exactly as it already behaves
// there (fetch-once-per-open), rather than adding this page's first
// realtime subscription for one section. A correct read-only, fetch-on-open
// page now beats a half-wired realtime one.
//
// "Book Site Visit" (`project_visit_bookings`) is now ported too — a
// visitor-only sticky bottom bar, mirroring `property_detail_screen.dart`'s
// own "Schedule Visit" sheet, but submitting through the `book-visit` Edge
// Function (`ProjectVisitBookingService`) rather than a direct insert —
// see that service's own header comment for why.
//
// Not ported:
//   * admin approve — an `approval_status` write, admin-only
//
// OWNER VS VISITOR
// ----------------
// The owner gets Edit and Delete, and is the only one shown the pending-
// verification badge. A visitor sees the project as a buyer would. Note the
// public read policy is `USING (status = 'active')` **alone**, so an unapproved
// project is publicly visible the moment it is created — telling a visitor it is
// unreviewed would advertise exactly that, so the badge stays owner-only.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/builder_section_models.dart';
import '../../models/project_model.dart';
import '../../models/property_model.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/projects_provider.dart';
import '../../services/builder_sections_service.dart';
import '../../services/project_service.dart';
import '../../services/project_visit_booking_service.dart';
import '../../services/user_profile_service.dart';
import '../property_detail/booking_enquiry_validation.dart';
import '../property_detail/property_media_viewer_screen.dart'
    show PropertyMediaViewerScreen, isVideoMediaUrl;
import '../dashboard/widgets/my_projects_section.dart'
    show ProjectStatusPill, projectPriceRangeLabel;
import '../../widgets/post_comments_sheet.dart';
import 'widgets/share_project_sheet.dart';

/// Height of the media header.
const double _kGalleryHeight = 260;

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.service,
    this.profileService,
    this.inventoryService,
    this.visitBookingService,
  });

  final String projectId;

  /// Injected by tests.
  @visibleForTesting
  final ProjectService? service;

  /// Injected by tests.
  @visibleForTesting
  final UserProfileService? profileService;

  /// Injected by tests.
  @visibleForTesting
  final ProjectInventoryService? inventoryService;

  /// Injected by tests.
  @visibleForTesting
  final ProjectVisitBookingService? visitBookingService;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late final ProjectService _projects = widget.service ?? ProjectService();
  late final UserProfileService _profiles =
      widget.profileService ?? UserProfileService();
  late final ProjectInventoryService _inventoryService =
      widget.inventoryService ?? ProjectInventoryService();
  late final ProjectVisitBookingService _visitBookingService =
      widget.visitBookingService ?? ProjectVisitBookingService();

  ProjectModel? _project;
  UserProfile? _builder;
  List<InventoryUnit> _inventory = const [];
  bool _loading = true;
  bool _failed = false;

  /// True when the row simply is not there — or is not visible, which for a
  /// non-owner means its status is not `active`. Both read as "not available"
  /// rather than as an error the user could retry away.
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _notFound = false;
    });

    try {
      final project = await _projects.fetchById(widget.projectId);
      if (!mounted) return;

      if (project == null) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }

      setState(() {
        _project = project;
        _loading = false;
      });

      // Second round-trip, deliberately after the project is painted: the page
      // is complete without the builder's name, and blocking on it would delay
      // everything for a byline.
      await _loadBuilder(project.builderId);
      // Third, independent round-trip — same reasoning. The inventory
      // service already fails silently to `[]` internally
      // (`ProjectInventoryService.publicUnitsForProject`), so this never
      // needs its own try/catch; an empty result just hides the section.
      await _loadInventory(project.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// The builder's name and avatar.
  ///
  /// Failure is swallowed — the page keeps working without a byline, which is
  /// what the portal does too (it only logs).
  Future<void> _loadBuilder(String builderId) async {
    if (builderId.isEmpty) return;
    try {
      final signedIn = context.read<AuthProvider>().isLoggedIn;
      final profile = await _profiles.fetchPublic(
        builderId,
        viewerSignedIn: signedIn,
      );
      if (!mounted) return;
      setState(() => _builder = profile);
    } catch (_) {
      // Intentionally silent.
    }
  }

  /// Available/sold/booked units — `PublicProjectInventory.tsx`'s section.
  /// `publicUnitsForProject` already never throws, but `setState` still needs
  /// a `mounted` guard since this runs after an await.
  Future<void> _loadInventory(String projectId) async {
    final units = await _inventoryService.publicUnitsForProject(projectId);
    if (!mounted) return;
    setState(() => _inventory = units);
  }

  bool get _isOwner {
    final project = _project;
    if (project == null) return false;
    final viewerId = context.read<AuthProvider>().userId;
    return viewerId != null && viewerId == project.builderId;
  }

  Future<void> _openLink(String url, String failureMessage) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failureMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _edit() async {
    final project = _project;
    if (project == null) return;
    final saved = await Navigator.pushNamed(
      context,
      AppConstants.addProjectScreen,
      arguments: {'project': project},
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_notFound) {
      return _Shell(
        child: Center(
          child: EmptyStateView(
            icon: Icons.apartment_outlined,
            title: 'Project not available',
            message: 'This project may have been removed or is not published.',
            actionLabel: 'Go back',
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    if (_failed || _project == null) {
      return _Shell(
        child: Center(
          child: EmptyStateView(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load this project",
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ),
      );
    }

    final project = _project!;
    final projectsProvider = context.watch<ProjectsProvider>();

    // The hero gallery is for the project's own photos (+ videos, appended
    // below) only. `galleryImages` also folds in `mapImages` (master-plan/
    // floor-plan diagrams), which already get their own dedicated "Master
    // plan" strip further down this page (see `project.mapImages.isNotEmpty`
    // below) — including them here too made a project with a single real
    // photo show "1/2" in the header, with the second "photo" actually being
    // a floor-plan image duplicated from that later section.
    //
    // Videos were previously a separate "Videos" list section lower on the
    // page, each opening its own full-screen player — moved into this same
    // hero gallery instead, swipeable alongside the photos, the way
    // `property_detail_screen.dart`'s own hero carousel already mixes
    // `media_urls` photos and videos (see `isVideoMediaUrl`/
    // `PropertyMediaViewerScreen`, reused here rather than re-invented).
    final heroMedia = [
      ...project.galleryImages.where((url) => !project.mapImages.contains(url)),
      ...project.videosUrls,
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          _GalleryHeader(
            images: heroMedia,
            onBack: () => Navigator.of(context).maybePop(),
            isLiked: projectsProvider.isLiked(project.id),
            isSaved: projectsProvider.isSaved(project.id),
            onToggleLike: () =>
                projectsProvider.toggleLike(project.id, project: project),
            onToggleSave: () =>
                projectsProvider.toggleSave(project.id, project: project),
            onComment: () => showPostCommentsSheet(
              context,
              postId: project.id,
              postType: 'project',
            ),
            onShare: () => showShareProjectSheet(
              context,
              projectId: project.id,
              title: project.title,
              description: project.description,
              location: project.location,
              priceRangeMin: project.priceRangeMin,
              currentUserId: context.read<AuthProvider>().userId,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(project: project, isOwner: _isOwner),
                  const SizedBox(height: AppConstants.spacingL),
                  _KeyFacts(project: project, inventory: _inventory),
                  if (project.description.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    const _SectionTitle('About this project'),
                    const SizedBox(height: 8),
                    Text(
                      project.description,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13.5,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (project.amenities.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    const _SectionTitle('Amenities'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final amenity in project.amenities)
                          _AmenityChip(label: amenity),
                      ],
                    ),
                  ],
                  if (project.mapImages.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    const _SectionTitle('Master plan'),
                    const SizedBox(height: 10),
                    _LayoutStrip(images: project.mapImages),
                  ],
                  if (_inventory.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    _SectionTitle('Available units in ${project.title}'),
                    const SizedBox(height: 10),
                    _InventoryGrid(units: _inventory),
                  ],
                  const SizedBox(height: AppConstants.spacingXL),
                  _ContactCard(
                    project: project,
                    builder: _builder,
                    onOpenWebsite: () => _openLink(
                      project.websiteUrl,
                      'Could not open that website.',
                    ),
                    onOpenBrochure: () => _openLink(
                      project.brochureUrl,
                      'Could not open the brochure.',
                    ),
                    onOpenBuilder: _builder == null
                        ? null
                        : () => Navigator.pushNamed(
                            context,
                            AppConstants.publicProfileScreen,
                            arguments: {'userId': project.builderId},
                          ),
                  ),
                  // Owner-only. Delete lives on the dashboard card, not here:
                  // deleting the row you are looking at would leave this screen
                  // showing a project that no longer exists.
                  if (_isOwner) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Edit Project'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.buttonRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _isOwner ? null : _buildBottomBar(context, project),
    );
  }

  // ===========================================================================
  // BOTTOM ACTION BAR — "Book Site Visit", visitor-only
  // ===========================================================================
  //
  // The gap this fix closes: unlike `property_detail_screen.dart`'s own
  // "Schedule Visit" sticky bar, this page never had one — `project_visit_
  // bookings` was explicitly deferred (see the file's own header comment).
  // Owner-only, inverted from the property screen's unconditional button:
  // a builder viewing their own project has Edit/Delete already (`_Header`),
  // and "visit your own project" is not a real action.

  Widget _buildBottomBar(BuildContext context, ProjectModel project) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 72 + bottomInset,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.textHint, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showScheduleVisitBottomSheet(context, project),
          icon: const Icon(Icons.calendar_today, size: 18),
          label: const Text('Book Site Visit'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SCHEDULE VISIT BOTTOM SHEET — `project_visit_bookings` via the `book-visit`
  // Edge Function. Same fields/validation as `property_detail_screen.dart`'s
  // own sheet (`BookVisitModal.tsx`'s shared name/phone rules), adapted in
  // two ways the function's contract requires: the submitted time is
  // converted to 24-hour `HH:MM` (the function's `TIME_RE` rejects "10:00
  // AM"), and the call goes through `ProjectVisitBookingService` rather than
  // a direct table insert.
  // ===========================================================================

  void _showScheduleVisitBottomSheet(
    BuildContext context,
    ProjectModel project,
  ) {
    final authProvider = context.read<AuthProvider>();
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book a visit.')),
      );
      return;
    }

    const List<String> timeSlots = [
      '10:00 AM',
      '11:00 AM',
      '12:00 PM',
      '01:00 PM',
      '02:00 PM',
      '03:00 PM',
      '04:00 PM',
      '05:00 PM',
      '06:00 PM',
    ];

    final nameController = TextEditingController(
      text: authProvider.userName.isNotEmpty
          ? authProvider.userName
          : (currentUser.userMetadata?['full_name']?.toString() ?? ''),
    );
    final phoneController = TextEditingController(
      text:
          currentUser.phone ??
          authProvider.profileRow?['phone']?.toString() ??
          '',
    );
    final messageController = TextEditingController();

    DateTime? selectedDate;
    String? selectedTime;
    TimeOfDay? customTime;
    String? nameError;
    String? phoneError;
    String? dateError;
    String? timeError;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            bool isSlotDisabled(String time) {
              final date = selectedDate;
              if (date == null) return false;
              return VisitFormValidation.isSlotDisabled(
                time,
                date,
                DateTime.now(),
              );
            }

            String formatCustomTime(TimeOfDay time) {
              final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
              final minute = time.minute.toString().padLeft(2, '0');
              final period = time.period == DayPeriod.am ? 'AM' : 'PM';
              return '$hour12:$minute $period';
            }

            bool isCustomTimePast(DateTime date, TimeOfDay time) {
              final now = DateTime.now();
              final isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              if (!isToday) return false;
              return (time.hour * 60 + time.minute) <=
                  (now.hour * 60 + now.minute);
            }

            Future<void> pickCustomTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: customTime ?? TimeOfDay.now(),
                builder: (BuildContext pickerContext, Widget? child) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      pickerContext,
                    ).copyWith(alwaysUse24HourFormat: false),
                    child: child!,
                  );
                },
              );
              if (picked == null) return;
              setModalState(() {
                customTime = picked;
                selectedTime = formatCustomTime(picked);
                timeError = null;
              });
            }

            Future<void> pickDate() async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate ?? today,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
              );
              if (picked != null) {
                setModalState(() {
                  selectedDate = picked;
                  dateError = null;
                  if (customTime != null) {
                    if (isCustomTimePast(picked, customTime!)) {
                      selectedTime = null;
                      customTime = null;
                    }
                  } else if (selectedTime != null &&
                      isSlotDisabled(selectedTime!)) {
                    selectedTime = null;
                  }
                });
              }
            }

            Future<void> submit() async {
              if (isSubmitting) return;
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              setModalState(() {
                nameError = VisitFormValidation.nameError(name);
                phoneError = VisitFormValidation.phoneError(phone);
                dateError = selectedDate == null ? 'Please select date' : null;
                if (selectedTime == null) {
                  timeError = 'Please select time';
                } else if (customTime != null &&
                    selectedDate != null &&
                    isCustomTimePast(selectedDate!, customTime!)) {
                  timeError = 'Please pick a time later than now';
                } else {
                  timeError = null;
                }
              });
              if (nameError != null ||
                  phoneError != null ||
                  dateError != null ||
                  timeError != null) {
                return;
              }

              setModalState(() => isSubmitting = true);
              try {
                await _visitBookingService.createBooking(
                  projectId: project.id,
                  visitorName: name,
                  visitorPhone: phone,
                  preferredDate: selectedDate!,
                  preferredTime: _to24Hour(selectedTime!),
                  message: messageController.text,
                );
                if (!mounted) return;
                Navigator.pop(sheetContext);
                _showVisitSuccessDialog(context, selectedDate!, selectedTime!);
              } catch (e) {
                if (!mounted) return;
                setModalState(() => isSubmitting = false);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_describeVisitError(e))));
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textHint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Book a Site Visit', style: AppTextStyles.heading2),
                    const SizedBox(height: 4),
                    Text(
                      project.title,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        errorText: nameError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: 'Phone *',
                        errorText: phoneError,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Select Date',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        selectedDate == null
                            ? 'Pick a date'
                            : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                      ),
                    ),
                    if (dateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          dateError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Select Time Slot',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...timeSlots.map((String time) {
                          final isSelected =
                              customTime == null && time == selectedTime;
                          final disabled = isSlotDisabled(time);
                          return ChoiceChip(
                            label: Text(time),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: disabled
                                ? AppColors.textHint.withValues(alpha: 0.15)
                                : AppColors.cardBackground,
                            side: isSelected
                                ? BorderSide.none
                                : BorderSide(
                                    color: AppColors.textHint.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                            labelStyle: AppTextStyles.chip.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : (disabled
                                        ? AppColors.textHint
                                        : AppColors.textSecondary),
                            ),
                            onSelected: disabled
                                ? null
                                : (bool selected) {
                                    if (selected) {
                                      setModalState(() {
                                        selectedTime = time;
                                        customTime = null;
                                        timeError = null;
                                      });
                                    }
                                  },
                          );
                        }),
                        ChoiceChip(
                          avatar: Icon(
                            Icons.access_time,
                            size: 16,
                            color: customTime != null
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          label: Text(
                            customTime != null ? selectedTime! : 'Custom',
                          ),
                          selected: customTime != null,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.cardBackground,
                          side: customTime != null
                              ? BorderSide.none
                              : BorderSide(
                                  color: AppColors.textHint.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                          labelStyle: AppTextStyles.chip.copyWith(
                            color: customTime != null
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          onSelected: (_) => pickCustomTime(),
                        ),
                      ],
                    ),
                    if (timeError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          timeError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Message',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Any requirements...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Confirm Schedule',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showVisitSuccessDialog(
    BuildContext context,
    DateTime date,
    String time,
  ) {
    final formattedDate = '${date.day}/${date.month}/${date.year}';
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Scheduled!'),
          ],
        ),
        content: Text(
          'Your visit is successfully scheduled for $formattedDate at $time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// The service throws the `book-visit` function's own validation message
  /// as a plain [String] on failure (e.g. "Visit date and time cannot be in
  /// the past.") — already complete, user-ready text, so it is shown as-is
  /// rather than run through a generic prefix. Anything else (a network
  /// failure) falls back to a plain retry prompt.
  String _describeVisitError(Object error) {
    if (error is String && error.isNotEmpty) return error;
    final text = error.toString();
    return text.isEmpty
        ? "Couldn't submit your visit request. Please try again."
        : "Couldn't submit your visit request: $text";
  }

  /// "10:00 AM" / "4:45 PM" → "10:00" / "16:45" — the `book-visit` function's
  /// `preferredTime` must be 24-hour `HH:MM`
  /// (`([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?`); the fixed slots and the custom
  /// time picker both produce a 12-hour AM/PM label for display.
  static String _to24Hour(String label) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    if (match == null) return label;
    var hour = int.parse(match.group(1)!);
    final minute = match.group(2)!;
    final period = match.group(3)!.toUpperCase();
    if (period == 'AM') {
      if (hour == 12) hour = 0;
    } else if (hour != 12) {
      hour += 12;
    }
    return '${hour.toString().padLeft(2, '0')}:$minute';
  }
}

/// Plain scaffold with a back affordance, for the two terminal states.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
    body: child,
  );
}

class _GalleryHeader extends StatefulWidget {
  const _GalleryHeader({
    required this.images,
    required this.onBack,
    required this.isLiked,
    required this.isSaved,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onComment,
    required this.onShare,
  });

  final List<String> images;
  final VoidCallback onBack;

  /// Like — backed by `user_likes.project_id`, a separate action from Save
  /// below, mirroring the property detail screen's Like/Save split
  /// (`property_detail_screen.dart`'s `_buildTopActions`: Heart = Like,
  /// Bookmark = Save, never two hearts).
  final bool isLiked;

  /// Save/Shortlist — backed by `saved_projects`.
  final bool isSaved;

  final VoidCallback onToggleLike;
  final VoidCallback onToggleSave;

  /// Opens [showPostCommentsSheet] (`post_type = 'project'`) — the same
  /// thread the Feed's own project card already opens from its Comment
  /// button. Like `onShare` below, the page previously had no comment
  /// affordance at all, despite the Feed card for this exact project
  /// already showing one.
  final VoidCallback onComment;

  /// Opens [showShareProjectSheet] — the page previously had no share
  /// affordance at all.
  final VoidCallback onShare;

  @override
  State<_GalleryHeader> createState() => _GalleryHeaderState();
}

class _GalleryHeaderState extends State<_GalleryHeader> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;

    return SliverAppBar(
      expandedHeight: _kGalleryHeight,
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: widget.onBack,
      ),
      actions: [
        IconButton(
          icon: Icon(
            widget.isLiked ? Icons.favorite : Icons.favorite_border,
            color: widget.isLiked ? Colors.red : Colors.white,
          ),
          onPressed: widget.onToggleLike,
        ),
        IconButton(
          icon: Icon(
            widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: Colors.white,
          ),
          onPressed: widget.onToggleSave,
        ),
        IconButton(
          icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
          onPressed: widget.onComment,
        ),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white),
          onPressed: widget.onShare,
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroGradient),
                child: Center(
                  child: Icon(
                    Icons.apartment_rounded,
                    size: 54,
                    color: Colors.white54,
                  ),
                ),
              )
            else
              PageView.builder(
                controller: _controller,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  // `images` carries photos and videos together (see the
                  // build() caller's `heroMedia`) — a video opened in the
                  // photo-only `GalleryViewerScreen` would have no way to
                  // play, so both branches below open the same
                  // `PropertyMediaViewerScreen` (photos + videos, already
                  // used by the property detail screen) instead, letting a
                  // swipe here carry across into whichever kind the
                  // adjacent index is.
                  void openViewer() => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PropertyMediaViewerScreen(
                        media: images,
                        initialIndex: i,
                      ),
                    ),
                  );

                  if (isVideoMediaUrl(images[i])) {
                    return _ProjectVideoSlide(
                      url: images[i],
                      onTap: openViewer,
                    );
                  }
                  return GestureDetector(
                    onTap: openViewer,
                    child: CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const ColoredBox(color: AppColors.primaryLight),
                      errorWidget: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                        ),
                      ),
                    ),
                  );
                },
              ),
            // Keeps the back button and the counter legible over any photo.
            // IgnorePointer so this purely decorative layer never swallows the
            // tap meant for the carousel page beneath it (same fix
            // property_detail_screen.dart's own gradient overlay already
            // uses for this exact reason).
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Color(0x00000000)],
                    stops: [0, 0.4],
                  ),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                  child: Text(
                    '${_page + 1} / ${images.length}',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A video slide in the hero gallery: the video's first frame (muted, not
/// playing) under a play button. Tapping opens the full-screen viewer. The
/// PageView builds slides lazily, so a controller only exists while its
/// slide is on or next to the screen. Mirrors
/// `property_detail_screen.dart`'s own `_PropertyVideoSlide` exactly — kept
/// as its own small copy here rather than shared, so this page's gallery
/// stays independent of that screen's private widgets.
class _ProjectVideoSlide extends StatefulWidget {
  const _ProjectVideoSlide({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  State<_ProjectVideoSlide> createState() => _ProjectVideoSlideState();
}

class _ProjectVideoSlideState extends State<_ProjectVideoSlide> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          _controller.setVolume(0);
          setState(() => _ready = true);
        })
        .catchError((Object e) {
          debugPrint('[ProjectDetail] Video preview failed: $e');
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project, required this.isOwner});

  final ProjectModel project;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          project.title,
          style: AppTextStyles.heading1.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 14,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                project.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _TypePill(label: project.typeLabel),
            ProjectStatusPill(status: project.status),
            // See the file header: owner-only, on purpose.
            if (isOwner && project.isPendingApproval)
              const _WarnPill(label: 'Pending verification'),
          ],
        ),
        if (project.hasPriceRange) ...[
          const SizedBox(height: 12),
          Text(
            projectPriceRangeLabel(project),
            style: AppTextStyles.heading2.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Units, sizes, dates and RERA, in one card.
class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.project, required this.inventory});

  final ProjectModel project;

  /// The same live `project_inventory` rows the "Available units" section
  /// further down this page already fetched (`publicUnitsForProject`) —
  /// reused here rather than a second query. When present, these are what
  /// the units fact line shows; `project.totalUnits`/`availableUnits` (typed
  /// into the listing form, not recalculated when a unit's status changes)
  /// are the fallback only when no inventory rows exist yet — the same
  /// listing-vs-tracked-inventory distinction `_ProjectInventoryCard` in
  /// `team_inventory_tab.dart` already draws.
  final List<InventoryUnit> inventory;

  @override
  Widget build(BuildContext context) {
    String? dateLabel(DateTime? value) {
      if (value == null) return null;
      return '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}/${value.year}';
    }

    final int totalUnits = inventory.isNotEmpty
        ? inventory.length
        : project.totalUnits;
    final int availableUnits = inventory.isNotEmpty
        ? inventory.where((u) => u.status == 'available').length
        : project.availableUnits;

    final facts = <(String, String)>[
      if (totalUnits > 0)
        (
          'Units',
          // Every unit is still available: "X of X available" reads as a
          // typo, not as reassurance — a visitor only needs the one number.
          // Once anything has sold, the ratio is the useful fact.
          availableUnits == totalUnits
              ? '$availableUnits available'
              : '$availableUnits of $totalUnits available',
        ),
      if (project.hasAreaRange)
        (
          'Unit sizes',
          project.areaSqftMin == project.areaSqftMax
              ? '${project.areaSqftMax.toStringAsFixed(0)} sq ft'
              : '${project.areaSqftMin.toStringAsFixed(0)} – '
                    '${project.areaSqftMax.toStringAsFixed(0)} sq ft',
        ),
      if (dateLabel(project.completionDate) != null)
        ('Completion', dateLabel(project.completionDate)!),
      if (dateLabel(project.possessionDate) != null)
        ('Possession', dateLabel(project.possessionDate)!),
      if (project.reraNumber.isNotEmpty) ('RERA', project.reraNumber),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    facts[i].$1,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    facts[i].$2,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.project,
    required this.builder,
    required this.onOpenWebsite,
    required this.onOpenBrochure,
    required this.onOpenBuilder,
  });

  final ProjectModel project;
  final UserProfile? builder;
  final VoidCallback onOpenWebsite;
  final VoidCallback onOpenBrochure;
  final VoidCallback? onOpenBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Builder & contact'),
          const SizedBox(height: 12),
          if (builder != null)
            GestureDetector(
              onTap: onOpenBuilder,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child:
                          builder!.avatarUrl == null ||
                              builder!.avatarUrl!.isEmpty
                          ? Center(
                              child: Text(
                                builder!.initials,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: builder!.avatarUrl!,
                              fit: BoxFit.cover,
                              width: 42,
                              height: 42,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      builder!.displayTitle ?? 'Builder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          if (project.contactNumber.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.phone_outlined, value: project.contactNumber),
          ],
          if (project.websiteUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LinkRow(
              icon: Icons.language_rounded,
              label: 'Visit website',
              onTap: onOpenWebsite,
            ),
          ],
          if (project.brochureUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LinkRow(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Download brochure',
              onTap: onOpenBrochure,
            ),
          ],
        ],
      ),
    );
  }
}

class _LayoutStrip extends StatelessWidget {
  const _LayoutStrip({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: CachedNetworkImage(
            imageUrl: images[i],
            width: 190,
            height: 130,
            fit: BoxFit.cover,
            placeholder: (_, _) =>
                Container(width: 190, color: AppColors.primaryLight),
            errorWidget: (_, _, _) => Container(
              width: 190,
              color: AppColors.primaryLight,
              alignment: Alignment.center,
              child: const Icon(Icons.map_outlined, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ports `PublicProjectInventory.tsx`'s unit grid (`md:grid-cols-2
/// lg:grid-cols-3`) — a `Wrap` rather than a `GridView` since this is a short,
/// non-scrolling section embedded in the page's own `CustomScrollView`/
/// `SingleChildScrollView`, the same reason `Wrap` is already used for
/// [_AmenityChip] above.
class _InventoryGrid extends StatelessWidget {
  const _InventoryGrid({required this.units});

  final List<InventoryUnit> units;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 columns past ~420px (most phones in portrait already clear
        // this), 1 column on anything narrower — there is no desktop-width
        // breakpoint to port since this is a phone-first screen.
        final columns = constraints.maxWidth >= 420 ? 2 : 1;
        const spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final unit in units)
              SizedBox(
                width: cardWidth,
                child: _InventoryUnitCard(unit: unit),
              ),
          ],
        );
      },
    );
  }
}

class _InventoryUnitCard extends StatelessWidget {
  const _InventoryUnitCard({required this.unit});

  final InventoryUnit unit;

  /// Only while available — `PublicProjectInventory.tsx`'s own gate
  /// (`item.floor_plan_url && item.status === 'available'`).
  bool get _showFloorPlanButton =>
      unit.status == 'available' && (unit.floorPlanUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.unitType,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (unit.unitNumber != null)
                      Text(
                        'Unit ${unit.unitNumber}',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              _UnitStatusBadge(status: unit.status),
            ],
          ),
          const SizedBox(height: 8),
          if (unit.floorNumber != null)
            Text(
              'Floor ${unit.floorNumber}',
              style: AppTextStyles.caption.copyWith(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            '${unit.areaSqft.toStringAsFixed(0)} sq.ft.',
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            PropertyModel.formatIndianPrice(unit.price),
            style: AppTextStyles.body.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (unit.facingDirection != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Facing ${unit.facingDirection}',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (_showFloorPlanButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/gallery-viewer',
                  arguments: {
                    'images': [unit.floorPlanUrl!],
                    'index': 0,
                  },
                ),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text(
                  'View Floor Plan',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryLight),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors `PublicProjectInventory.tsx`'s `getStatusBadge` — green/red/yellow
/// for available/sold/booked, a neutral pill for anything else (the schema's
/// CHECK constraint also allows `blocked`, which the portal's own switch
/// falls through to a bare, untinted badge for too).
class _UnitStatusBadge extends StatelessWidget {
  const _UnitStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'available' => ('Available', AppColors.success),
      'sold' => ('Sold out', AppColors.error),
      'booked' => ('Booked', AppColors.warning),
      _ => (status, AppColors.textHint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTextStyles.heading3.copyWith(fontSize: 15));
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
    ),
    child: Text(
      label,
      style: AppTextStyles.chip.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );
}

class _WarnPill extends StatelessWidget {
  const _WarnPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
    ),
    child: Text(
      label,
      style: AppTextStyles.chip.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AppColors.warning,
      ),
    ),
  );
}

class _AmenityChip extends StatelessWidget {
  const _AmenityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Text(
      label,
      style: AppTextStyles.caption.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: AppColors.textHint),
      const SizedBox(width: 8),
      Expanded(
        child: Text(value, style: AppTextStyles.body.copyWith(fontSize: 13)),
      ),
    ],
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
        const Icon(
          Icons.open_in_new_rounded,
          size: 13,
          color: AppColors.primary,
        ),
      ],
    ),
  );
}
