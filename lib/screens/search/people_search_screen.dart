// screens/search/people_search_screen.dart
//
// People Search: the paginated people list, reached from the Search entry
// screen's suggestion dropdown.
//
// Property search is not involved. This screen reads no `FilterProvider`, touches
// no `PropertyProvider` and shares no state with `SearchResultsScreen`; the two
// only share widget-level conventions (the pinned header block, the
// `maxScrollExtent - 300` pagination trigger, `AppConstants.searchPageSize`).
//
// The provider is screen-scoped through `ChangeNotifierProvider(create:)`, the
// pattern `PublicProfileScreen` established, so nothing is added to the global
// provider tree in `main.dart`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/people_search_result.dart';
import '../../providers/people_search_provider.dart';
import 'widgets/people_result_card.dart';
import 'widgets/search_error_state.dart';

/// Debounce before a keystroke becomes a query. 300 ms is what
/// `SearchModal.tsx:65` uses, and what this app's own search box already uses.
const Duration _kDebounce = Duration(milliseconds: 300);

/// Placeholder cards on a first load. `BrokersList.tsx:112` renders eight; six
/// fill a phone viewport without shimmering below the fold.
const int _kSkeletonCount = 6;

class PeopleSearchScreen extends StatelessWidget {
  /// Seeded from the Search entry screen so the first result set is already on
  /// screen when this opens, rather than showing a prompt for a query the user
  /// has just typed.
  final String initialQuery;

  /// Injected by tests. Production always builds a real provider.
  @visibleForTesting
  final PeopleSearchProvider? providerOverride;

  const PeopleSearchScreen({
    super.key,
    this.initialQuery = '',
    this.providerOverride,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PeopleSearchProvider>(
      create: (_) =>
          providerOverride ??
          PeopleSearchProvider(pageSize: AppConstants.searchPageSize),
      child: _PeopleSearchView(initialQuery: initialQuery),
    );
  }
}

class _PeopleSearchView extends StatefulWidget {
  final String initialQuery;

  const _PeopleSearchView({required this.initialQuery});

  @override
  State<_PeopleSearchView> createState() => _PeopleSearchViewState();
}

class _PeopleSearchViewState extends State<_PeopleSearchView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scroll = ScrollController();

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<PeopleSearchProvider>();
      final seed = widget.initialQuery.trim();
      if (seed.isEmpty) {
        _focusNode.requestFocus();
      } else {
        provider.search(seed);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Same trigger distance as SearchResultsScreen._maybeLoadMore.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      context.read<PeopleSearchProvider>().loadMore();
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Fires on any non-empty query, matching `SearchModal.tsx:64`. No minimum
    // length: the entry screen's 3-character floor exists for the `global_search`
    // RPC, which returns nothing under two characters. This is a plain `ilike`.
    _debounce = Timer(_kDebounce, () {
      if (!mounted) return;
      context.read<PeopleSearchProvider>().search(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    context.read<PeopleSearchProvider>().search('');
    _focusNode.requestFocus();
  }

  void _openProfile(PersonResult result) {
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': result.userId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PeopleSearchProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              onClear: _clear,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            _RoleChipRow(
              selected: provider.role,
              onSelected: (role) =>
                  context.read<PeopleSearchProvider>().selectRole(role),
            ),
            _CountLine(provider: provider),
            Expanded(child: _buildBody(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PeopleSearchProvider provider) {
    if (provider.isIdle) return const _IdlePrompt();

    if (provider.hasError) {
      return SearchErrorState(
        onRetry: () => context.read<PeopleSearchProvider>().retry(),
      );
    }

    if (provider.isSearching && provider.results.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingL,
          AppConstants.spacingS,
          AppConstants.spacingL,
          AppConstants.spacingXXL,
        ),
        itemCount: _kSkeletonCount,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingM),
        itemBuilder: (_, _) => const PeopleResultSkeleton(),
      );
    }

    if (provider.isEmptyResult) {
      return _NoResults(query: provider.query.trim(), onClear: _clear);
    }

    final results = provider.results;

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingL,
        AppConstants.spacingS,
        AppConstants.spacingL,
        AppConstants.spacingXXL,
      ),
      // One extra row for the load-more indicator when another page exists.
      itemCount: results.length + (provider.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppConstants.spacingM),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }

        final result = results[index];
        return PeopleResultCard(
          result: result,
          onTap: () => _openProfile(result),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onBack;

  const _Header({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingM,
        AppConstants.spacingM,
        AppConstants.spacingM,
        AppConstants.spacingS,
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: AppConstants.spacingS),
          Expanded(
            child: Container(
              height: AppConstants.searchBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingM,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(
                  AppConstants.searchBarRadius,
                ),
                boxShadow: AppColors.surfaceCardShadow,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      style: AppTextStyles.body.copyWith(fontSize: 14),
                      // AppTheme's inputDecorationTheme sets `filled: true` plus
                      // enabled/focused OutlineInputBorders, and those win over
                      // `border: InputBorder.none` alone. All six border slots
                      // plus `filled: false` have to be nulled out — the recipe
                      // `SearchBarWidget` documents and
                      // test/search_bar_parity_test.dart guards.
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: 'Search builders, brokers, people…',
                        hintStyle: AppTextStyles.body.copyWith(
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: onClear,
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppColors.textHint,
                              ),
                            ),
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
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.cardBackground,
            shape: BoxShape.circle,
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: Icon(icon, size: 16, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// The role filter.
///
/// "All" sends no `user_type` predicate, which is what the portal's three
/// role-agnostic people queries do. The four named chips reproduce the split the
/// portal expresses as three separate directory pages.
class _RoleChipRow extends StatelessWidget {
  final PeopleRole selected;
  final ValueChanged<PeopleRole> onSelected;

  const _RoleChipRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: AppConstants.spacingXS,
      ),
      child: Row(
        children: [
          for (final role in PeopleRole.values) ...[
            if (role != PeopleRole.values.first)
              const SizedBox(width: AppConstants.spacingS),
            _RoleChip(
              role: role,
              isSelected: role == selected,
              onTap: () => onSelected(role),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final PeopleRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: role.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.hairline,
              ),
            ),
            child: Text(
              role.label,
              style: AppTextStyles.chip.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.cardBackground
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "12 people found" — hidden until a search has actually returned.
class _CountLine extends StatelessWidget {
  final PeopleSearchProvider provider;

  const _CountLine({required this.provider});

  @override
  Widget build(BuildContext context) {
    final count = provider.totalCount;
    if (provider.isIdle ||
        provider.hasError ||
        !provider.hasSearched ||
        count == null ||
        count == 0) {
      return const SizedBox(height: AppConstants.spacingS);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingL,
        AppConstants.spacingS,
        AppConstants.spacingL,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$count ${count == 1 ? 'person' : 'people'} found',
          style: AppTextStyles.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _IdlePrompt extends StatelessWidget {
  const _IdlePrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SingleChildScrollView(
        child: EmptyStateView(
          icon: Icons.group_outlined,
          title: 'Find people on PropCid',
          message:
              'Search builders, brokers, influencers and members by name, '
              'company or bio.',
          titleFontSize: 18,
        ),
      ),
    );
  }
}

/// No matches.
///
/// Wording from `SearchModal.tsx:512-533` — "No matches found", the query echoed
/// back, and a button that empties the box.
class _NoResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: EmptyStateView(
          icon: Icons.person_search_outlined,
          title: 'No matches found',
          message: "We couldn't find any people for “$query”.",
          actionLabel: 'Try another search',
          onAction: onClear,
          titleFontSize: 18,
        ),
      ),
    );
  }
}
