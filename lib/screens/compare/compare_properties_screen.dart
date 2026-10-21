import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../models/amenity_model.dart';
import '../../models/property_model.dart';
import '../../providers/compare_provider.dart';

/// Shared sizing for the header strip + comparison matrix, computed once per
/// layout pass from the available width (see [computeCompareLayoutMetrics])
/// rather than off fixed, screen-specific constants. Both the property-card
/// row and the matrix's label column/value columns read the exact same
/// instance, which is what keeps a card's left edge lined up with its value
/// column below it at any device width.
@visibleForTesting
class CompareLayoutMetrics {
  const CompareLayoutMetrics({
    required this.labelWidth,
    required this.columnWidth,
  });

  /// Width of the fixed left-hand panel — the new property-count/"Swipe"
  /// summary above, and the attribute-label column below. Required to be
  /// identical for both (requirement: "the summary panel must use exactly
  /// the same width as the fixed field-label column").
  final double labelWidth;

  /// Width of one property column — reused for every header card, every
  /// matrix value column, and the trailing "Add" placeholder.
  final double columnWidth;

  /// Horizontal gap between the fixed left panel and the scrollable
  /// columns, and between consecutive columns themselves.
  static const double gap = 8.0;
}

/// Derives [CompareLayoutMetrics] from the width available to the compare
/// area (i.e. the screen width already minus the screen's own 16+16 side
/// padding) — a [LayoutBuilder] in [ComparePropertiesScreen] supplies this,
/// so nothing here is tied to a specific device size.
///
/// `labelWidth` is a bounded fraction of the available width: proportional
/// enough to stay sensible from a small phone up to a tablet-width split
/// view, but clamped so it never shrinks below what "Swipe →" needs to stay
/// on one line, nor grows large enough to crowd the property columns.
///
/// `columnWidth` is sized so one property column fills most of what is left
/// after the label panel — comfortably showing a card's image, title, price
/// and both actions without clipping — while still leaving a small, fixed
/// sliver of the next column visible as a swipe affordance, per the
/// approved design (not a second fully-visible column).
@visibleForTesting
CompareLayoutMetrics computeCompareLayoutMetrics(double availableWidth) {
  final labelWidth = (availableWidth * 0.26).clamp(84.0, 112.0);
  final remaining = availableWidth - labelWidth - CompareLayoutMetrics.gap;
  const peek = 32.0;
  final columnWidth = (remaining - peek - CompareLayoutMetrics.gap).clamp(
    150.0,
    220.0,
  );
  return CompareLayoutMetrics(labelWidth: labelWidth, columnWidth: columnWidth);
}

/// Compare Properties — global-state, portal-parity rewrite.
///
/// Reads its selection from [CompareProvider] (the same store every property
/// card's compare toggle writes to) rather than owning two local slots, so
/// adding/removing a property anywhere in the app is reflected here and vice
/// versa. `widget.propertyIds` is kept only for the voice agent / a future
/// deep link that names properties explicitly — if the global selection is
/// still empty when this screen opens, those ids seed it once; the two
/// in-app entry points (Home quick action, header dropdown) always pass an
/// empty list today, so this path is inert for them.
class ComparePropertiesScreen extends StatefulWidget {
  final List<String> propertyIds;

  /// Overrides the `properties-by-ids` Edge Function call. Null in every
  /// production call site (the real [ComparePropertiesScreen.
  /// _fetchCompareRows] is used); layout tests inject a fake here so the
  /// new header/matrix sizing can be exercised with real rendered property
  /// cards instead of only the loading/error/empty states, without hitting
  /// Supabase.
  @visibleForTesting
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> body)?
  fetchRowsOverride;

  const ComparePropertiesScreen({
    super.key,
    required this.propertyIds,
    this.fetchRowsOverride,
  });

  @override
  State<ComparePropertiesScreen> createState() =>
      _ComparePropertiesScreenState();
}

class _ComparePropertiesScreenState extends State<ComparePropertiesScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  bool _isLoading = true;
  bool _hasError = false;
  bool _showDiffsOnly = false;
  List<PropertyModel> _properties = [];

  /// Collapsed section titles — purely local presentation state (which rows
  /// are currently visible), mirroring the reference design's expandable
  /// section headers. Never affects what's compared or fetched.
  final Set<String> _collapsedSections = {};

  void _toggleSection(String title) {
    setState(() {
      if (_collapsedSections.contains(title)) {
        _collapsedSections.remove(title);
      } else {
        _collapsedSections.add(title);
      }
    });
  }

  /// Two separate scrollables — the property header strip has no reserved
  /// left column (so Property A starts at normal screen padding), while the
  /// comparison matrix below it keeps a fixed attribute-label column to its
  /// left. Because their viewports start at different x-offsets they can't
  /// share one `ScrollController` (Flutter only allows a controller to
  /// attach to one active `Scrollable`), so they're linked manually: each
  /// mirrors its raw scroll offset onto the other, guarded by
  /// [_isSyncingScroll] to avoid a feedback loop.
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _matrixScrollController = ScrollController();
  bool _isSyncingScroll = false;

  /// How many persisted/requested ids silently failed to resolve (deleted,
  /// deactivated or unapproved since they were added) — surfaced once as an
  /// info banner rather than a crash or a substituted property.
  int _unavailableCount = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _headerScrollController.addListener(
      () => _mirrorScroll(
        from: _headerScrollController,
        to: _matrixScrollController,
      ),
    );
    _matrixScrollController.addListener(
      () => _mirrorScroll(
        from: _matrixScrollController,
        to: _headerScrollController,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProperties());
  }

  @override
  void dispose() {
    _animController.dispose();
    _headerScrollController.dispose();
    _matrixScrollController.dispose();
    super.dispose();
  }

  /// Mirrors [from]'s raw pixel offset onto [to], clamped to [to]'s own
  /// scroll range (the two regions can have slightly different content
  /// widths — the header strip includes the "Add" tile, the matrix
  /// doesn't — so their max extents aren't always identical).
  void _mirrorScroll({
    required ScrollController from,
    required ScrollController to,
  }) {
    if (_isSyncingScroll || !to.hasClients || !from.hasClients) return;
    final clamped = from.offset.clamp(0.0, to.position.maxScrollExtent);
    if (clamped == to.offset) return;
    _isSyncingScroll = true;
    to.jumpTo(clamped);
    _isSyncingScroll = false;
  }

  // ─── Data loading / resolution ──────────────────────────────

  /// [widget.fetchRowsOverride] when a test supplied one, else the real
  /// Edge Function call — the single seam every row-fetching call site below
  /// goes through, so nothing else has to know a test double exists.
  Future<List<Map<String, dynamic>>> _fetchRows(Map<String, dynamic> body) =>
      (widget.fetchRowsOverride ?? _fetchCompareRows)(body);

  /// Portal parity (CompareProperties.tsx / PropertySearchModal.tsx): both
  /// the by-ids load and the "Add a Property" search go through the
  /// already-deployed `properties-by-ids` Edge Function, which returns every
  /// row with the full embed — owner profile plus all three category
  /// sub-tables. Returns raw rows keyed the way [PropertyModel.fromSupabase]
  /// reads them (the function's `commercialDetails`/`landDetails` aliases are
  /// copied onto `properties_commercial`/`properties_land`;
  /// `residentialDetails` and `user_profile` are already read as-is).
  static Future<List<Map<String, dynamic>>> _fetchCompareRows(
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'properties-by-ids',
      body: body,
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final rows = data is Map ? data['rows'] : null;
    if (rows is! List) return const [];
    return [
      for (final r in rows)
        if (r is Map)
          () {
            final row = Map<String, dynamic>.from(r);
            if (row['commercialDetails'] is Map) {
              row['properties_commercial'] = row['commercialDetails'];
            }
            if (row['landDetails'] is Map) {
              row['properties_land'] = row['landDetails'];
            }
            return row;
          }(),
    ];
  }

  /// Raw row per property id — the portal reads several compared fields
  /// straight off the row (area_unit, rate_per_area, the sub-table columns,
  /// metadata.furnishedType, user_profile) that [PropertyModel] doesn't
  /// carry, so the rows below read the same fields from here.
  Map<String, Map<String, dynamic>> _rawById = {};

  Map<String, dynamic> _raw(PropertyModel p) => _rawById[p.id] ?? const {};

  Map<String, dynamic> _sub(PropertyModel p, String key) {
    final v = _raw(p)[key];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  Future<void> _loadProperties() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final compareProvider = context.read<CompareProvider>();

      // Seeds the global selection from an explicit deep link only when
      // nothing is already selected — never overrides an in-progress
      // comparison the user already built via the property cards.
      if (compareProvider.selectedIds.isEmpty &&
          widget.propertyIds.isNotEmpty) {
        final seeded = await _fetchRows({
          'ids': widget.propertyIds.take(CompareProvider.maxCompare).toList(),
        });
        for (final row in seeded) {
          compareProvider.add(PropertyModel.fromSupabase(row));
        }
      }

      final requestedIds = compareProvider.selectedIds;
      final rows = requestedIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _fetchRows({'ids': requestedIds});

      // The portal's availability rule: fetched with no status filter, then
      // `available = status === 'active' && approval_status === 'approved'`;
      // anything else is dropped from the comparison.
      final rawById = <String, Map<String, dynamic>>{
        for (final r in rows)
          if (r['status'] == 'active' && r['approval_status'] == 'approved')
            r['id'].toString(): r,
      };
      final resolved = [
        for (final id in requestedIds)
          if (rawById.containsKey(id)) PropertyModel.fromSupabase(rawById[id]!),
      ];
      final missingIds = requestedIds
          .where((id) => !rawById.containsKey(id))
          .toList();
      // Never substitute a different property for one that can't be
      // resolved — drop the slot instead.
      for (final id in missingIds) {
        compareProvider.remove(id);
      }
      compareProvider.reconcileWithPool(resolved);

      if (!mounted) return;
      setState(() {
        _rawById = rawById;
        _properties = resolved;
        _unavailableCount = missingIds.length;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ComparePropertiesScreen] load failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  // ─── Compare actions ─────────────────────────────────────────

  Future<void> _openPicker() async {
    final compareProvider = context.read<CompareProvider>();
    // Portal PropertySearchModal: the server-side search for the first
    // compared property's category + listing type, excluding what's
    // already added (limit 50) — not whatever happens to be in memory.
    final first = _properties.isNotEmpty ? _properties.first : null;

    final result = await showModalBottomSheet<PropertyModel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PropertyPickerSheet(
        load: () async {
          final rows = await _fetchRows({
            if (first?.category != null) 'category': first!.category,
            if (first?.propertyType != null)
              'propertyType': first!.propertyType,
            'excludeIds': compareProvider.selectedIds,
            'limit': 50,
          });
          return [for (final r in rows) (PropertyModel.fromSupabase(r), r)];
        },
        isSelected: compareProvider.isSelected,
      ),
    );
    if (result == null || !mounted) return;

    final addResult = compareProvider.add(result);
    if (addResult == CompareAddResult.limitReached ||
        addResult == CompareAddResult.categoryMismatch) {
      // Portal: "Failed to Add Property" + the reason.
      _showMessage(
        'Failed to Add Property',
        addResult == CompareAddResult.limitReached
            ? 'Compare limit reached'
            : 'You can only compare properties of the same category and '
                  'listing type.',
      );
      return;
    }
    _showMessage(
      'Property Added',
      'Property has been added to comparison',
      isError: false,
    );
    _loadProperties();
  }

  void _removeProperty(String propertyId) {
    context.read<CompareProvider>().remove(propertyId);
    _loadProperties();
  }

  /// Portal: `clearCompare()` then `navigate('/')`.
  void _clearAll() {
    context.read<CompareProvider>().clear();
    Navigator.pop(context);
  }

  void _showMessage(String title, String description, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.error : AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(description),
          ],
        ),
      ),
    );
  }

  /// Portal `handleShareComparison`: the comparison link plus a short list
  /// of the first three properties.
  void _shareComparison() {
    final ids = _properties.map((p) => p.id).join(',');
    final category = _properties.first.category ?? 'properties';
    final label = category.isEmpty
        ? 'Properties'
        : '${category[0].toUpperCase()}${category.substring(1)}';
    final title = _properties.length == 1
        ? 'Property Comparison on PropCID'
        : 'Compare ${_properties.length} $label Properties';
    final list = _properties
        .take(3)
        .map((p) {
          final parts = p.location.split(',');
          final loc = parts.length > 1
              ? parts.sublist(parts.length - 2).join(',').trim()
              : (p.location.isNotEmpty ? p.location : 'Unknown Location');
          final t = p.title.length > 30
              ? '${p.title.substring(0, 30)}...'
              : p.title;
          return '• $t – $loc';
        })
        .join('\n');
    Share.share(
      '$title\n$list\nCompare: Price, Area, Amenities, Location, Seller '
      'Details\nhttps://propcid.com/compare?ids=$ids',
      subject: title,
    );
  }

  /// Portal "Browse Properties" → the search page.
  void _browseProperties() =>
      Navigator.pushNamed(context, AppConstants.searchScreen);

  void _openProperty(PropertyModel property) {
    Navigator.pushNamed(
      context,
      AppConstants.propertyDetailScreen,
      arguments: {'propertyId': property.id},
    );
  }

  // ─── UI ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compareProvider = context.watch<CompareProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            children: [
              _buildAppBar(compareProvider),
              if (_unavailableCount > 0) _buildUnavailableBanner(),
              Expanded(child: _buildBody(compareProvider)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(CompareProvider compareProvider) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_hasError) {
      return _buildErrorState();
    }
    if (_properties.isEmpty) {
      return _buildEmptyState();
    }
    if (_properties.length == 1) {
      return _buildSingleSelectedState();
    }

    final canAddMore = _properties.length < CompareProvider.maxCompare;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildToggleRow(),
          _buildScrollHint(canAddMore: canAddMore),
          const SizedBox(height: 10),
          _buildCompareArea(canAddMore: canAddMore),
          const SizedBox(height: 20),
          _buildFindBestPropertyButton(),
          // Clears the app's persistent floating assistant orb, which can
          // rest anywhere near the bottom of the screen — the last row must
          // never end up hidden underneath it.
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  /// A visible cue that there's more to see by swiping — the real-device
  /// pass flagged the horizontal scroll as not obvious on its own. Shown
  /// whenever there are more columns (properties + a possible "Add" tile)
  /// than comfortably fit on a phone width at once.
  Widget _buildScrollHint({required bool canAddMore}) {
    final totalColumns = _properties.length + (canAddMore ? 1 : 0);
    if (totalColumns <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          const Icon(
            Icons.swipe_left_alt_outlined,
            size: 14,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Swipe to compare all ${_properties.length} properties',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10.5,
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(CompareProvider compareProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: AppColors.cardShadow,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compare Properties', style: AppTextStyles.heading2),
                // Portal: "Comparing {count} {category} properties".
                if (_properties.length >= 2)
                  Text(
                    'Comparing ${_properties.length} '
                    '${_properties.first.category ?? ''} properties',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          if (_properties.length >= 2)
            IconButton(
              onPressed: _shareComparison,
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined, color: AppColors.primary),
            ),
          if (compareProvider.count > 0)
            TextButton(onPressed: _clearAll, child: const Text('Clear All')),
        ],
      ),
    );
  }

  Widget _buildUnavailableBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            // Portal toast: "Some properties unavailable" / "{{count}}
            // property(s) were removed from comparison as they are no
            // longer available."
            child: Text(
              'Some properties unavailable — $_unavailableCount property(s) '
              'were removed from comparison as they are no longer available.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Properties',
              style: AppTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load properties for comparison. Please try again.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadProperties,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.compare_arrows_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Properties to Compare',
              style: AppTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add properties to compare by clicking the compare button on '
              'property cards.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _browseProperties,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Browse Properties'),
            ),
          ],
        ),
      ),
    );
  }

  /// The 1-selected state — shown instead of the near-empty "add one more"
  /// prompt, so the user can actually see and manage the property they
  /// already picked rather than staring at a mostly-blank screen.
  Widget _buildSingleSelectedState() {
    final property = _properties.first;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add One More Property', style: AppTextStyles.heading3),
          const SizedBox(height: 4),
          Text(
            'You need at least 2 properties to compare. Add another property '
            'to continue.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: _buildHeaderCard(property, isBestValue: false),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _openPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add another property',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _browseProperties,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Browse Properties'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text('Compare Details', style: AppTextStyles.heading3),
          ),
          GestureDetector(
            onTap: () => setState(() => _showDiffsOnly = !_showDiffsOnly),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: _showDiffsOnly ? AppColors.primaryGradient : null,
                color: _showDiffsOnly ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _showDiffsOnly
                    ? AppColors.primaryGlow
                    : AppColors.cardShadow,
              ),
              child: Row(
                children: [
                  Icon(
                    _showDiffsOnly
                        ? Icons.check_circle
                        : Icons.filter_list_rounded,
                    size: 14,
                    color: _showDiffsOnly
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Differences only',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _showDiffsOnly
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Closing CTA, matching the reference design. Points at the existing
  /// Search Entry screen (`AppConstants.searchScreen`) — a safe, already-
  /// registered destination — rather than inventing a new "best property"
  /// flow that doesn't exist anywhere else in the app.
  Widget _buildFindBestPropertyButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            onTap: () =>
                Navigator.pushNamed(context, AppConstants.searchScreen),
            child: Ink(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                boxShadow: AppColors.primaryGlow,
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Find Your Best Property',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Shared compare area (header strip + matrix) ─────────────
  //
  // Both the property-card row and the comparison matrix read the SAME
  // [CompareLayoutMetrics], computed once here from the width actually
  // available (i.e. already inside the screen's own 16+16 side padding).
  // That shared instance is what keeps the label/summary column widths
  // identical and a property card's left edge lined up with its value
  // column below it, at any device width — not two independent layouts
  // that happen to use the same hard-coded numbers.
  Widget _buildCompareArea({required bool canAddMore}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = computeCompareLayoutMetrics(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderStrip(metrics: metrics, canAddMore: canAddMore),
              const SizedBox(height: 16),
              _buildComparisonMatrix(metrics),
            ],
          );
        },
      ),
    );
  }

  // ─── Property header strip ──────────────────────────────────
  //
  // A fixed summary panel (property count + "Swipe →" hint) at exactly
  // [CompareLayoutMetrics.labelWidth] — the same width the matrix's
  // attribute-label column uses below — followed by the SAME horizontally-
  // scrolling row of property cards the matrix's value columns sit under.
  // Kept in sync with the matrix below via [_mirrorScroll] rather than a
  // shared `ScrollController` (see the field docs), since the two
  // `SingleChildScrollView`s are still separate widgets.

  Widget _buildHeaderStrip({
    required CompareLayoutMetrics metrics,
    required bool canAddMore,
  }) {
    final bestValueIndex = _bestValueIndex(_properties);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryPanel(metrics),
        const SizedBox(width: CompareLayoutMetrics.gap),
        Expanded(
          child: SingleChildScrollView(
            controller: _headerScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _properties.length; i++)
                  Padding(
                    key: ValueKey('header-card-${_properties[i].id}'),
                    padding: const EdgeInsets.only(
                      right: CompareLayoutMetrics.gap,
                    ),
                    child: SizedBox(
                      width: metrics.columnWidth,
                      child: _buildHeaderCard(
                        _properties[i],
                        isBestValue: bestValueIndex == i,
                      ),
                    ),
                  ),
                if (canAddMore) _buildAddColumn(metrics),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The new fixed left-hand panel above the matrix's label column: an
  /// orange compare icon, the actual selected-property count, and the
  /// "Swipe →" hint — matching the approved mockup. Vertically centered
  /// against the header cards' fixed height so the row reads as one piece
  /// rather than top-pinned content floating above empty space.
  Widget _buildSummaryPanel(CompareLayoutMetrics metrics) {
    final count = _properties.length;
    return SizedBox(
      width: metrics.labelWidth,
      height: _kHeaderCellHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.compare_arrows_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$count ${count == 1 ? 'Property' : 'Properties'}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Swipe',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 11,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Comparison matrix ───────────────────────────────────────
  //
  // A fixed attribute-label column (never scrolls) beside a horizontally
  // scrollable row of per-property value columns. Section titles ("Property
  // Details", "Trust & Verification", ...) are NOT rendered inside the
  // narrow label column — that's what made them wrap onto 2-3 lines on a
  // real device. Instead every row/section is first flattened into
  // `_MatrixSlot`s so the label column and every value column can reserve
  // an identical blank slot for a section title, and the actual title text
  // is drawn once, full-width, in a `Positioned` overlay above both — never
  // constrained to the label column's width.

  Widget _buildComparisonMatrix(CompareLayoutMetrics metrics) {
    final sections = _buildSections(_properties);
    final slots = _buildSlots(sections);

    double y = 0;
    final banners = <_SectionBanner>[];
    for (final slot in slots) {
      if (slot.sectionTitle != null) {
        banners.add(_SectionBanner(slot.sectionTitle!, y));
      }
      y += slot.height;
    }

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabelColumn(slots, metrics),
            Expanded(
              child: Scrollbar(
                controller: _matrixScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _matrixScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _properties.length; i++)
                        _buildValueColumn(
                          _properties[i],
                          i,
                          slots,
                          metrics,
                          allProperties: _properties,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        for (final banner in banners)
          Positioned(
            top: banner.top,
            left: 0,
            right: 0,
            child: _buildSectionBanner(banner.title),
          ),
      ],
    );
  }

  /// Flattens visible sections/rows into a single ordered slot list — the
  /// label column, every value column, and the banner-offset computation
  /// above all walk this SAME list, so a section or row that's hidden by
  /// "Differences only" disappears from all three consistently.
  List<_MatrixSlot> _buildSlots(List<_CompareSection> sections) {
    final slots = <_MatrixSlot>[];
    for (final section in sections) {
      if (!_sectionHasVisibleRows(section)) continue;
      slots.add(_MatrixSlot.section(section.title));
      if (_collapsedSections.contains(section.title)) continue;
      for (final row in section.rows) {
        if (!_showDiffsOnly || row.valuesDiffer(_properties)) {
          slots.add(_MatrixSlot.row(row));
        }
      }
    }
    return slots;
  }

  /// A section title bar — small colored icon badge, bold title, and a
  /// chevron that collapses/expands the section's rows. Purely visual state
  /// (see [_collapsedSections]); the comparison data itself never changes.
  Widget _buildSectionBanner(String title) {
    final bool collapsed = _collapsedSections.contains(title);
    return GestureDetector(
      onTap: () => _toggleSection(title),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _kSectionCellHeight,
        color: AppColors.background,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _sectionIcon(title),
                size: 11,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            Icon(
              collapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  IconData _sectionIcon(String title) {
    switch (title) {
      case 'Basic Info':
        return Icons.info_outline;
      case 'Pricing':
        return Icons.currency_rupee_rounded;
      case 'Property Details':
        return Icons.home_work_outlined;
      case 'Amenities':
        return Icons.pool_outlined;
      case 'Trust & Verification':
        return Icons.verified_outlined;
      case 'Posted By':
        return Icons.person_outline_rounded;
      default:
        return Icons.info_outline;
    }
  }

  bool _sectionHasVisibleRows(_CompareSection section) {
    if (!_showDiffsOnly) return true;
    return section.rows.any((row) => row.valuesDiffer(_properties));
  }

  Widget _buildLabelColumn(
    List<_MatrixSlot> slots,
    CompareLayoutMetrics metrics,
  ) {
    return Container(
      width: metrics.labelWidth,
      margin: const EdgeInsets.only(right: CompareLayoutMetrics.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final slot in slots)
            if (slot.sectionTitle != null)
              // Blank — the real title is drawn once, full-width, by the
              // `Positioned` banner in `_buildComparisonMatrix`.
              SizedBox(height: slot.height)
            else
              Container(
                height: slot.height,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(slot.row!.icon, size: 13, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        slot.row!.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildValueColumn(
    PropertyModel property,
    int index,
    List<_MatrixSlot> slots,
    CompareLayoutMetrics metrics, {
    required List<PropertyModel> allProperties,
  }) {
    return Container(
      key: ValueKey('value-column-${property.id}'),
      width: metrics.columnWidth,
      margin: const EdgeInsets.only(right: CompareLayoutMetrics.gap),
      child: Column(
        children: [
          for (final slot in slots)
            if (slot.sectionTitle != null)
              SizedBox(height: slot.height)
            else
              _buildValueCell(slot.row!, property, allProperties, index),
        ],
      ),
    );
  }

  Widget _buildValueCell(
    _CompareRow row,
    PropertyModel property,
    List<PropertyModel> allProperties,
    int index,
  ) {
    final bestIndex = row.bestIndex?.call(allProperties);
    final isWinner = bestIndex == index;
    final isDiff = row.isOutlier(property, allProperties);

    return Container(
      height: row.height ?? _kDataCellHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isWinner
              ? AppColors.success.withOpacity(0.12)
              : (isDiff ? AppColors.error.withOpacity(0.05) : null),
          borderRadius: BorderRadius.circular(6),
        ),
        child: row.buildValue != null
            ? row.buildValue!(property)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isWinner) ...[
                    const Icon(
                      Icons.emoji_events_rounded,
                      size: 10,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      row.getValue(property),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isWinner
                            ? AppColors.success
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeaderCard(PropertyModel property, {required bool isBestValue}) {
    return Container(
      height: _kHeaderCellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.cardRadius),
                  topRight: Radius.circular(AppConstants.cardRadius),
                ),
                child: Image.network(
                  property.imageUrl,
                  height: _kHeaderImageHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: _kHeaderImageHeight,
                    color: AppColors.primaryLight,
                    child: const Icon(
                      Icons.home_outlined,
                      size: 28,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _removeProperty(property.id),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_headerStatusLabel(property) != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.getStatusChipBg(
                              _headerStatusLabel(property)!,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _headerStatusLabel(property)!,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.getStatusChipText(
                                _headerStatusLabel(property)!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isApproved(property))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.verifiedBadge,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '✓ Verified',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (isBestValue) ...[
                      if (_isApproved(property)) const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '★ Best Value',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fixed-height regardless of whether the actual title wraps
                // to one line or two, so every card's price/owner/actions
                // below land at the same Y — a short title no longer pulls
                // its own card's buttons up relative to its neighbours'.
                SizedBox(
                  height: 36,
                  child: Text(
                    property.title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  property.location,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _webPrice(_listingPrice(property)),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.priceColor,
                  ),
                ),
                const SizedBox(height: 6),
                _buildOwnerRow(property),
                const SizedBox(height: 8),
                // Portal card actions: Contact Owner + View Details (both
                // open the listing; contact lives on its detail page).
                _cardButton(
                  'Contact Owner',
                  filled: true,
                  onTap: () => _openProperty(property),
                ),
                const SizedBox(height: 4),
                _cardButton(
                  'View Details',
                  filled: false,
                  onTap: () => _openProperty(property),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Owner avatar + name + company — the portal card's user_profile block.
  Widget _buildOwnerRow(PropertyModel property) {
    final profile = _sub(property, 'user_profile');
    final name = profile['display_name']?.toString() ?? '';
    final company = profile['company_name']?.toString() ?? '';
    final avatar = profile['avatar_url']?.toString() ?? '';
    if (name.isEmpty && company.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: AppColors.primaryLight,
          backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
          child: avatar.isNotEmpty
              ? null
              : Text(
                  (name.isNotEmpty ? name : company)[0].toUpperCase(),
                  style: const TextStyle(fontSize: 8, color: AppColors.primary),
                ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            [
              if (name.isNotEmpty) name,
              if (company.isNotEmpty) company,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _cardButton(
    String label, {
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label),
            ),
    );
  }

  Widget _buildAddColumn(CompareLayoutMetrics metrics) {
    return Container(
      width: metrics.columnWidth,
      child: GestureDetector(
        onTap: _openPicker,
        child: Container(
          height: _kHeaderCellHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.textHint),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Add',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Best Value + row/section construction ──────────────────

  /// Portal `bestValuePropertyId`: lowest `price / (area || 1)`; the first
  /// minimum wins (JS `reduce`), so there is always one badge.
  int? _bestValueIndex(List<PropertyModel> properties) {
    if (properties.isEmpty) return null;
    var best = 0;
    double ratio(PropertyModel p) {
      final area = _num(_raw(p)['area']) ?? _num(_raw(p)['area_sqft']) ?? 0;
      final price = _num(_raw(p)['price']) ?? 0;
      return price / (area > 0 ? area : 1);
    }

    for (var i = 1; i < properties.length; i++) {
      if (ratio(properties[i]) < ratio(properties[best])) best = i;
    }
    return best;
  }

  /// Portal `isBestValue`: price (lower is better, missing = ∞), area,
  /// bedrooms, bathrooms, approval (higher is better, missing = 0); only a
  /// single unique best is highlighted.
  int? _portalBest(
    List<PropertyModel> props,
    double Function(PropertyModel) value, {
    bool lowerIsBetter = false,
  }) {
    if (props.length < 2) return null;
    final values = [for (final p in props) value(p)];
    final best = lowerIsBetter
        ? values.reduce((a, b) => a < b ? a : b)
        : values.reduce((a, b) => a > b ? a : b);
    if (values.where((v) => v == best).length != 1) return null;
    return values.indexOf(best);
  }

  // ── Portal field helpers (CompareProperties.tsx / utility.ts) ─────────

  static double? _num(Object? v) => switch (v) {
    null => null,
    final num n => n.toDouble(),
    _ => double.tryParse(v.toString().replaceAll(RegExp(r'[^\d.]'), '')),
  };

  /// JS truthiness for a displayed value: null/''/0/false → absent.
  static bool _present(Object? v) =>
      v != null && v != '' && v != 0 && v != false && v != '0';

  static String _str(Object? v) => _present(v) ? v.toString() : '—';

  bool _isApproved(PropertyModel p) =>
      (_raw(p)['approval_status'] ?? p.approvalStatus) == 'approved';

  /// `resolveListingPrice`: `price`, else the metadata fallbacks PG/co-living
  /// listings use.
  Object? _listingPrice(PropertyModel p) {
    final price = _raw(p)['price'] ?? p.price;
    if (_present(price)) return price;
    final meta = _raw(p)['metadata'] is Map
        ? _raw(p)['metadata'] as Map
        : const {};
    for (final key in [
      'totalSalePrice',
      'monthlyRentPerBed',
      'monthlyRentPerRoom',
      'pgRentAmount',
    ]) {
      if (_present(meta[key])) return meta[key];
    }
    return price;
  }

  /// `formatPrice` (INR): Cr / L / K abbreviations, "Price on Request" when
  /// absent.
  static String _webPrice(Object? price) {
    if (!_present(price)) return 'Price on Request';
    final n = _num(price);
    if (n == null) return price.toString();
    String f(double v) {
      final s = v.toStringAsFixed(2);
      return s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
    }

    if (n >= 10000000) return '₹${f(n / 10000000)} Cr';
    if (n >= 100000) return '₹${f(n / 100000)} L';
    if (n >= 10000) return '₹${f(n / 1000)} K';
    if (n >= 1000) {
      final s = n.round().toString();
      return '₹${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
    }
    return '₹${n.round()}';
  }

  static const Map<String, String> _kAreaUnits = {
    'sq_ft': 'Square Feet',
    'sq_mtr': 'Square Meters',
    'sq_yards': 'Square Yards',
    'acres': 'Acres',
    'hectares': 'Hectares',
    'bigha': 'Bigha',
    'katha': 'Katha',
    'marla': 'Marla',
    'kanal': 'Kanal',
  };

  /// `formatAreaWithUnit(area, area_unit || 'sq_ft')`.
  String _areaWithUnit(PropertyModel p, Object? area) {
    if (!_present(area)) return '—';
    final unit = _raw(p)['area_unit']?.toString();
    final u = (unit == null || unit.isEmpty) ? 'sq_ft' : unit;
    return '$area ${_kAreaUnits[u] ?? u}';
  }

  /// `formatRatePerArea(rate_per_area, 'sq_ft')`.
  String _ratePerArea(PropertyModel p) {
    final rate = _raw(p)['rate_per_area'];
    if (!_present(rate)) return 'Price on Request';
    return '${_webPrice(rate)} per Sq. Ft';
  }

  bool _isRent(PropertyModel p) =>
      (_raw(p)['property_type'] ?? p.propertyType) == 'rent';

  /// `metadata.furnishedType`: 'Raw' → Unfurnished, anything else →
  /// Furnished, unset → "—" (the `furnished` column can't tell unset apart).
  String _furnishing(PropertyModel p) {
    final meta = _raw(p)['metadata'];
    final type = meta is Map ? meta['furnishedType'] : null;
    if (!_present(type)) return '—';
    return type == 'Raw' ? 'Unfurnished' : 'Furnished';
  }

  String _floor(Map<String, dynamic> d) {
    if (_present(d['floor_number']) && _present(d['total_floors'])) {
      return '${d['floor_number']} / ${d['total_floors']}';
    }
    return _str(d['floor_number']);
  }

  String _capitalize(String v) =>
      v.isEmpty || v == '—' ? v : '${v[0].toUpperCase()}${v.substring(1)}';

  List<_CompareSection> _buildSections(List<PropertyModel> properties) {
    if (properties.isEmpty) return [];
    final category = properties.first.category;

    return [
      _CompareSection('Basic Info', [
        _CompareRow(
          label: 'Price',
          icon: Icons.currency_rupee,
          getValue: (p) => _webPrice(_listingPrice(p)),
          bestIndex: (props) => _portalBest(
            props,
            (p) => _num(_raw(p)['price']) ?? double.infinity,
            lowerIsBetter: true,
          ),
        ),
        _CompareRow(
          label: 'Listing Type',
          icon: Icons.sell_outlined,
          getValue: (p) => _isRent(p) ? 'For Rent' : 'For Sale',
        ),
        _CompareRow(
          label: 'Category',
          icon: Icons.category_outlined,
          getValue: (p) => _capitalize(_str(_raw(p)['category'])),
        ),
        _CompareRow(
          label: 'Location',
          icon: Icons.location_on_outlined,
          getValue: (p) => _str(_raw(p)['location']),
        ),
        _CompareRow(
          label: 'Area',
          icon: Icons.straighten,
          getValue: (p) => _areaWithUnit(p, _raw(p)['area']),
          bestIndex: (props) => _portalBest(
            props,
            (p) => _num(_raw(p)['area']) ?? _num(_raw(p)['area_sqft']) ?? 0,
          ),
        ),
        _CompareRow(
          label: 'Price per Area',
          icon: Icons.square_foot,
          getValue: _ratePerArea,
        ),
      ]),
      _CompareSection('Pricing', [
        _CompareRow(
          label: 'Monthly Rent',
          icon: Icons.payments_outlined,
          getValue: (p) =>
              _isRent(p) ? '${_webPrice(_listingPrice(p))}/mo' : '—',
        ),
        _CompareRow(
          label: 'Lease Duration',
          icon: Icons.timelapse_outlined,
          getValue: (p) =>
              _isRent(p) && _present(_raw(p)['lease_duration_months'])
              ? '${_raw(p)['lease_duration_months']} months'
              : '—',
        ),
        _CompareRow(
          label: 'Available From',
          icon: Icons.event_available_outlined,
          getValue: (p) => _isRent(p) ? _str(_raw(p)['available_from']) : '—',
        ),
      ]),
      _CompareSection('Property Details', _propertyDetailRows(category)),
      _CompareSection('Amenities', [
        _CompareRow(
          label: 'Amenities',
          icon: Icons.pool_outlined,
          getValue: (p) => '${p.amenities.length} amenities',
          buildValue: (p) => _buildAmenitiesCell(p.amenities),
          height: _kAmenitiesCellHeight,
        ),
      ]),
      _CompareSection('Trust & Verification', [
        _CompareRow(
          label: 'Approval Status',
          icon: Icons.verified_outlined,
          getValue: (p) => _isApproved(p)
              ? 'Verified'
              : _str(_raw(p)['approval_status'] ?? 'Pending'),
          buildValue: _buildApprovalCell,
          bestIndex: (props) =>
              _portalBest(props, (p) => _isApproved(p) ? 1 : 0),
        ),
      ]),
      _CompareSection('Posted By', [
        _CompareRow(
          label: 'Name',
          icon: Icons.person_outline,
          getValue: (p) => _str(_sub(p, 'user_profile')['display_name']),
        ),
        _CompareRow(
          label: 'Company',
          icon: Icons.business_outlined,
          getValue: (p) => _str(_sub(p, 'user_profile')['company_name']),
        ),
        _CompareRow(
          label: 'User Type',
          icon: Icons.badge_outlined,
          getValue: (p) =>
              _capitalize(_str(_sub(p, 'user_profile')['user_type'])),
        ),
      ]),
    ];
  }

  /// Portal approval cell: green "Verified" pill when approved, else a
  /// yellow pill with the status (or "Pending").
  Widget _buildApprovalCell(PropertyModel p) {
    final ok = _isApproved(p);
    final color = ok ? AppColors.success : AppColors.warning;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                ok ? 'Verified' : _str(_raw(p)['approval_status'] ?? 'Pending'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Category rows — the portal's exact rows, labels, sources and formats
  /// per category (built off the first property; CompareProvider enforces
  /// one category + listing type). PG/co-living and others get none, as on
  /// the portal.
  List<_CompareRow> _propertyDetailRows(String? category) {
    Map<String, dynamic> res(PropertyModel p) =>
        _sub(p, 'residentialDetails').isNotEmpty
        ? _sub(p, 'residentialDetails')
        : _sub(p, 'properties_residential');
    Map<String, dynamic> com(PropertyModel p) =>
        _sub(p, 'properties_commercial');
    Map<String, dynamic> land(PropertyModel p) => _sub(p, 'properties_land');

    switch (category) {
      case 'residential':
        return [
          _CompareRow(
            label: 'Bedrooms/BHK',
            icon: Icons.bed_outlined,
            getValue: (p) => _present(res(p)['bedrooms'])
                ? '${res(p)['bedrooms']} BHK'
                : '—',
            bestIndex: (props) =>
                _portalBest(props, (p) => _num(res(p)['bedrooms']) ?? 0),
          ),
          _CompareRow(
            label: 'Bathrooms',
            icon: Icons.bathtub_outlined,
            getValue: (p) => _str(res(p)['bathrooms']),
            bestIndex: (props) =>
                _portalBest(props, (p) => _num(res(p)['bathrooms']) ?? 0),
          ),
          _CompareRow(
            label: 'Furnishing',
            icon: Icons.chair_outlined,
            getValue: _furnishing,
          ),
          _CompareRow(
            label: 'Parking',
            icon: Icons.local_parking_outlined,
            getValue: (p) => _str(res(p)['parking_spaces']),
          ),
          _CompareRow(
            label: 'Floor',
            icon: Icons.layers_outlined,
            getValue: (p) => _floor(res(p)),
          ),
          _CompareRow(
            label: 'Facing',
            icon: Icons.explore_outlined,
            getValue: (p) => _capitalize(_str(res(p)['facing_direction'])),
          ),
          _CompareRow(
            label: 'Property Age',
            icon: Icons.calendar_today_outlined,
            getValue: (p) => _present(res(p)['age_of_property'])
                ? '${res(p)['age_of_property']} years'
                : '—',
          ),
          _CompareRow(
            label: 'Balconies',
            icon: Icons.balcony_outlined,
            getValue: (p) => _str(res(p)['balconies']),
          ),
        ];
      case 'commercial':
        return [
          _CompareRow(
            label: 'Washrooms',
            icon: Icons.wc_outlined,
            getValue: (p) => _str(com(p)['washrooms']),
          ),
          _CompareRow(
            label: 'Parking',
            icon: Icons.local_parking_outlined,
            getValue: (p) => _str(com(p)['parking_spaces']),
          ),
          _CompareRow(
            label: 'Floor',
            icon: Icons.layers_outlined,
            getValue: (p) => _floor(com(p)),
          ),
          _CompareRow(
            label: 'Furnishing',
            icon: Icons.chair_outlined,
            getValue: _furnishing,
          ),
          _CompareRow(
            label: 'Power Load',
            icon: Icons.bolt_outlined,
            getValue: (p) => _present(com(p)['power_load_kw'])
                ? '${com(p)['power_load_kw']} kW'
                : '—',
          ),
          _CompareRow(
            label: 'Cafeteria',
            icon: Icons.local_cafe_outlined,
            getValue: (p) => _present(com(p)['cafeteria']) ? 'Yes' : 'No',
          ),
          _CompareRow(
            label: 'Conference Rooms',
            icon: Icons.meeting_room_outlined,
            getValue: (p) => _str(com(p)['conference_rooms']),
          ),
          _CompareRow(
            label: 'Built-up Area',
            icon: Icons.crop_square,
            getValue: (p) => _areaWithUnit(p, com(p)['built_up_area_sqft']),
          ),
          _CompareRow(
            label: 'Carpet Area',
            icon: Icons.crop_square_outlined,
            getValue: (p) => _areaWithUnit(p, com(p)['carpet_area_sqft']),
          ),
        ];
      case 'land':
        return [
          _CompareRow(
            label: 'Plot Area',
            icon: Icons.landscape_outlined,
            getValue: (p) => _present(land(p)['area_sqft'])
                ? '${land(p)['area_sqft']} sqft'
                : '—',
          ),
          _CompareRow(
            label: 'Boundary Wall',
            icon: Icons.fence_outlined,
            getValue: (p) => _present(land(p)['boundary_wall']) ? 'Yes' : 'No',
          ),
          _CompareRow(
            label: 'Water Source',
            icon: Icons.water_drop_outlined,
            getValue: (p) => _str(land(p)['water_source']),
          ),
          _CompareRow(
            label: 'Road Width',
            icon: Icons.add_road_outlined,
            getValue: (p) => _present(land(p)['road_width_ft'])
                ? '${land(p)['road_width_ft']} ft'
                : '—',
          ),
          _CompareRow(
            label: 'Soil Type',
            icon: Icons.terrain_outlined,
            getValue: (p) => _capitalize(_str(land(p)['soil_type'])),
          ),
          _CompareRow(
            label: 'Slope',
            icon: Icons.trending_up_rounded,
            getValue: (p) => _present(land(p)['slope_percentage'])
                ? '${land(p)['slope_percentage']}%'
                : '—',
          ),
        ];
      case 'pg_coliving':
      default:
        return const [];
    }
  }

  void _showAllAmenities(List<AmenityModel> amenities) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Amenities'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in amenities)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    a.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAmenitiesCell(List<AmenityModel> amenities) {
    if (amenities.isEmpty) {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: AppTextStyles.caption,
      );
    }
    const int cap = 3;
    final shown = amenities.take(cap).toList();
    final remaining = amenities.length - shown.length;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final amenity in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              amenity.name,
              style: const TextStyle(fontSize: 9, color: AppColors.primary),
            ),
          ),
        if (remaining > 0)
          // Portal: '+N More' opens the full amenities list.
          GestureDetector(
            onTap: () => _showAllAmenities(amenities),
            child: Text(
              '+$remaining More',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  /// Same source the matrix's own "Status" row reads
  /// (`possessionStatus` first, then the first raw hashtag), reused here so
  /// the header card's badge can never disagree with the row below it.
  String? _headerStatusLabel(PropertyModel property) {
    final value =
        property.possessionStatus ??
        (property.statusTags.isNotEmpty ? property.statusTags.first : null);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }
}

// Fixed cell sizing for the label-column + horizontally-scrollable
// value-columns layout — every value column and the label column share
// these exact heights row-for-row, so nothing needs to sync two separate
// scroll positions: the header card is just the first "row" inside each
// column, scrolling together with the rest by construction.
//
// Column and label WIDTHS are no longer fixed constants — they come from
// [computeCompareLayoutMetrics], computed once per layout pass from the
// actual available width. Only heights stay fixed here: the design's card
// proportions don't need to change with screen width the way column widths
// do to keep the left-edge alignment the mockup calls for.
const double _kHeaderCellHeight = 272;
const double _kHeaderImageHeight = 80;
const double _kSectionCellHeight = 28;
const double _kDataCellHeight = 46;
// Amenity chips wrap onto up to two lines; the default row height clips
// them, so this one row gets its own taller slot (both the label cell and
// the value cells for this row use it, so alignment is unaffected).
const double _kAmenitiesCellHeight = 60;

// ─────────────────────────────────────────────
//  Compare Row / Section data classes
// ─────────────────────────────────────────────
class _CompareSection {
  final String title;
  final List<_CompareRow> rows;
  const _CompareSection(this.title, this.rows);
}

class _CompareRow {
  final String label;
  final IconData icon;
  final String Function(PropertyModel) getValue;

  /// Optional custom cell content (e.g. amenity chips) — falls back to a
  /// plain centred [getValue] text when absent.
  final Widget Function(PropertyModel)? buildValue;

  /// Returns the index of the winning property among the full compared
  /// list, or null when there's no meaningful winner for this row (no
  /// comparator, all-null, or a tie).
  final int? Function(List<PropertyModel>)? bestIndex;

  /// Overrides [_kDataCellHeight] for rows whose content needs more room
  /// (e.g. wrapped amenity chips). The label cell and every value cell for
  /// this row all read the same override, so row alignment never drifts.
  final double? height;

  const _CompareRow({
    required this.label,
    required this.icon,
    required this.getValue,
    this.buildValue,
    this.bestIndex,
    this.height,
  });

  bool valuesDiffer(List<PropertyModel> properties) {
    if (properties.length < 2) return false;
    final first = getValue(properties.first);
    return properties.any((p) => getValue(p) != first);
  }

  /// Whether [property]'s own value is the odd one out among [properties] —
  /// used to tint only the genuine outlier cell(s) red, not every cell in a
  /// row the moment anything differs. Mirrors the reference design, where
  /// e.g. a "3 BHK / 3 BHK / 3 BHK / 2 BHK" row only tints the lone "2 BHK"
  /// cell, leaving the matching majority plain. Ties (no single clear
  /// majority, e.g. every value distinct, or a 2-vs-2 split) tint nothing —
  /// there's no "normal" value to call anyone an outlier against.
  bool isOutlier(PropertyModel property, List<PropertyModel> properties) {
    if (properties.length < 2) return false;
    final values = [for (final p in properties) getValue(p)];
    final counts = <String, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
    if (maxCount == values.length) return false;
    final modeValues = counts.entries
        .where((e) => e.value == maxCount)
        .map((e) => e.key)
        .toList();
    if (modeValues.length != 1) return false;
    return getValue(property) != modeValues.first;
  }
}

/// One vertical slot in the comparison matrix — either a blank spacer where
/// a full-width section-title banner will be drawn on top, or a data row.
/// The label column and every value column iterate the same list of these,
/// so their heights can never drift out of alignment.
class _MatrixSlot {
  final String? sectionTitle;
  final _CompareRow? row;

  const _MatrixSlot.section(this.sectionTitle) : row = null;
  const _MatrixSlot.row(this.row) : sectionTitle = null;

  double get height => sectionTitle != null
      ? _kSectionCellHeight
      : (row!.height ?? _kDataCellHeight);
}

/// A section title and the vertical offset (within the matrix) its banner
/// should be drawn at — computed once by walking the same `_MatrixSlot`
/// list used to lay out the label/value columns.
class _SectionBanner {
  final String title;
  final double top;
  const _SectionBanner(this.title, this.top);
}

// ─────────────────────────────────────────────
//  Property Picker Bottom Sheet
// ─────────────────────────────────────────────
class _PropertyPickerSheet extends StatefulWidget {
  /// Portal PropertySearchModal's server search (`properties-by-ids` with
  /// category/propertyType/excludeIds/limit 50) — each result with its raw
  /// row, for the owner-name/company search fields.
  final Future<List<(PropertyModel, Map<String, dynamic>)>> Function() load;
  final bool Function(String id) isSelected;

  const _PropertyPickerSheet({required this.load, required this.isSelected});

  @override
  State<_PropertyPickerSheet> createState() => _PropertyPickerSheetState();
}

class _PropertyPickerSheetState extends State<_PropertyPickerSheet> {
  String _query = '';
  late final Future<List<(PropertyModel, Map<String, dynamic>)>> _future =
      widget.load();

  /// Portal search fields: title, location, category, property_type, owner
  /// display_name / company_name, and "furnished".
  bool _matches(PropertyModel p, Map<String, dynamic> row) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final profile = row['user_profile'] is Map
        ? row['user_profile'] as Map
        : const {};
    final fields = [
      p.title,
      p.location,
      row['category'],
      row['property_type'],
      profile['display_name'],
      profile['company_name'],
      if (row['furnished'] == true) 'furnished',
    ];
    return fields.any((f) => (f?.toString() ?? '').toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    // A `Material` here, not a plain `Container(color: ...)` — the sheet's
    // `ListTile`s need an unobstructed `Material` ancestor for their ink
    // splashes to paint (see the transparent sheet background).
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a Property', style: AppTextStyles.heading3),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText:
                            'Search by property name, location or project...',
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<(PropertyModel, Map<String, dynamic>)>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _message(
                      'Failed to load properties',
                      'Please try again.',
                    );
                  }
                  final all = snapshot.data ?? const [];
                  final filtered = [
                    for (final e in all)
                      if (_matches(e.$1, e.$2)) e,
                  ];
                  if (filtered.isEmpty) {
                    return all.isEmpty
                        ? _message(
                            'No compatible properties found',
                            'Try changing your search',
                          )
                        : _message(
                            'No properties found',
                            'Try changing your search terms',
                          );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _buildTile(context, filtered[i].$1, filtered[i].$2),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String title, String body) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(body, style: AppTextStyles.caption),
      ],
    ),
  );

  Widget _buildTile(
    BuildContext context,
    PropertyModel p,
    Map<String, dynamic> row,
  ) {
    final added = widget.isSelected(p.id);
    final approved = row['approval_status'] == 'approved';
    final meta = [
      if ((row['area']?.toString() ?? '').isNotEmpty) '${row['area']} sqft',
      if ((row['category']?.toString() ?? '').isNotEmpty) row['category'],
      if ((row['property_type']?.toString() ?? '').isNotEmpty)
        row['property_type'],
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              p.imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: AppColors.primaryLight,
                child: const Icon(
                  Icons.home_outlined,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (approved) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        size: 13,
                        color: AppColors.verifiedBadge,
                      ),
                    ],
                  ],
                ),
                Text(
                  p.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
                Text(
                  _ComparePropertiesScreenState._webPrice(
                    row['price'] ?? p.price,
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.priceColor,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: added ? null : () => Navigator.pop(context, p),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(added ? 'Already Added' : 'Add to Compare'),
            ),
          ),
        ],
      ),
    );
  }
}
