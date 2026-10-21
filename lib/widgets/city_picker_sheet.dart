// widgets/city_picker_sheet.dart
//
// The "Select City" bottom sheet used by Search and Search Results: a search
// box, a grid of popular cities, and the full A-Z list with a radio per row,
// confirmed with an Apply button. Selecting works exactly as the old plain
// list did (one city, or All Cities = no city filter) - only the look and the
// Apply step are new.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/available_location.dart';
import '../providers/available_locations_provider.dart';
import '../providers/filter_provider.dart';

/// Opens the sheet. [onApplied] runs after the chosen city has been written to
/// [FilterProvider] (e.g. to re-run the active search).
Future<void> showCityPickerSheet(
  BuildContext context, {
  VoidCallback? onApplied,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => _CityPickerBody(
        scrollController: scrollController,
        onApply: (cities) {
          context.read<FilterProvider>().setCities(cities);
          Navigator.pop(sheetContext);
          onApplied?.call();
        },
        onClose: () => Navigator.pop(sheetContext),
      ),
    ),
  );
}

const List<String> _kPopularCities = [
  'Delhi',
  'Mumbai',
  'Bangalore',
  'Hyderabad',
  'Chennai',
  'Pune',
  'Kolkata',
  'Ahmedabad',
];

class _CityPickerBody extends StatefulWidget {
  const _CityPickerBody({
    required this.scrollController,
    required this.onApply,
    required this.onClose,
  });

  final ScrollController scrollController;
  final void Function(List<String> cities) onApply;
  final VoidCallback onClose;

  @override
  State<_CityPickerBody> createState() => _CityPickerBodyState();
}

class _CityPickerBodyState extends State<_CityPickerBody> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _ascending = true;

  /// The city that will be applied; null means "All Cities".
  late String? _selected = () {
    final cities = context.read<FilterProvider>().cities;
    return cities.isEmpty ? null : cities.first;
  }();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The location in [all] matching a popular city's name (also accepting
  /// "New Delhi" for "Delhi"); null when this deployment has none.
  AvailableLocation? _match(List<AvailableLocation> all, String name) {
    final n = name.toLowerCase();
    for (final l in all) {
      final c = l.city.toLowerCase();
      if (c == n || c == 'new $n') return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select City',
                        style: AppTextStyles.heading2.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose a city to find properties',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close',
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<AvailableLocationsProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }
                return _buildContent(provider.locations);
              },
            ),
          ),
          _buildApplyBar(),
        ],
      ),
    );
  }

  Widget _buildContent(List<AvailableLocation> all) {
    final sorted = [...all]
      ..sort((a, b) {
        final r = a.city.toLowerCase().compareTo(b.city.toLowerCase());
        return _ascending ? r : -r;
      });
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? sorted
        : sorted
              .where(
                (l) =>
                    l.city.toLowerCase().contains(q) ||
                    (l.state ?? '').toLowerCase().contains(q),
              )
              .toList();
    final popular = [
      for (final name in _kPopularCities)
        if (_match(all, name) != null) _match(all, name)!,
    ];

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      children: [
        // search
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(
                    hintText: 'Search city...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                  child: const Icon(
                    Icons.cancel_rounded,
                    size: 18,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
        ),
        if (popular.isNotEmpty && q.isEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Popular Cities',
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: [for (final l in popular) _popularChip(l)],
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'All Cities',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: _ascending ? 'Sorted A to Z' : 'Sorted Z to A',
              child: GestureDetector(
                onTap: () => setState(() => _ascending = !_ascending),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _ascending
                        ? Icons.sort_by_alpha_rounded
                        : Icons.sort_rounded,
                    size: 17,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (q.isEmpty) _row(title: 'All Cities', value: null),
        for (final l in shown)
          _row(title: l.city, subtitle: l.state, value: l.city),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text('No cities found', style: AppTextStyles.caption),
            ),
          ),
      ],
    );
  }

  Widget _popularChip(AvailableLocation l) {
    final selected = _selected == l.city;
    return GestureDetector(
      onTap: () => setState(() => _selected = l.city),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l.city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  /// One list row: pin, city (+ state), and a radio. [value] is the city name
  /// it selects; null selects "All Cities".
  Widget _row({required String title, String? subtitle, String? value}) {
    final selected = _selected == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selected = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20,
              color: selected ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.hairline,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.ctaGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () =>
                    widget.onApply(_selected == null ? [] : [_selected!]),
                child: Center(
                  child: Text(
                    'Apply',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
