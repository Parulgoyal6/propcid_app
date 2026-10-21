import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/social_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/social_provider.dart';
import '../../services/social_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/toggle_row.dart';
import '../shared/section_loader.dart';
import 'widgets/social_screen_shell.dart';

/// Social ▸ Preferences — the design's `isSocialPreferences` screen.
///
/// Renders the caller's `social_share_preferences` row: seven auto-share
/// switches, six default-target switches, and the caption defaults — and now
/// actually saves edits back via [SocialService.savePreferences], the same
/// upsert the portal's `savePreferences` does.
class SocialPreferencesScreen extends StatelessWidget {
  const SocialPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialPreferencesSection(),
      child: const _PreferencesView(),
    );
  }
}

class _PreferencesViewState extends State<_PreferencesView>
    with DeferredSectionLoader<_PreferencesView> {
  final _service = SocialService();
  SocialPreferences? _draft;
  bool _saving = false;
  bool _wasLoading = true;

  @override
  void loadSection(String userId) =>
      context.read<SocialPreferencesSection>().loadFor(userId);

  void _edit(SocialPreferences Function(SocialPreferences) update) {
    setState(() => _draft = update(_draft!));
  }

  Future<void> _save() async {
    final userId = context.read<AuthProvider>().userId;
    final draft = _draft;
    if (userId == null || draft == null) return;

    setState(() => _saving = true);
    try {
      await _service.savePreferences(userId, draft);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences saved')));
      reloadSection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save preferences: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialPreferencesSection>();

    // The draft is seeded once from the first successful load, then owned
    // entirely by local edits — a background reload (e.g. after Save) must
    // not silently discard an in-progress edit.
    if (_wasLoading && !section.loading && !section.failed) {
      _draft = section.value;
    }
    _wasLoading = section.loading;

    return SocialPreferencesBody(
      preferences: _draft ?? section.value,
      loading: section.loading,
      failed: section.failed,
      saving: _saving,
      onChanged: _draft == null ? null : _edit,
      onSave: _draft == null ? null : _save,
    );
  }
}

class _PreferencesView extends StatefulWidget {
  const _PreferencesView();

  @override
  State<_PreferencesView> createState() => _PreferencesViewState();
}

class SocialPreferencesBody extends StatelessWidget {
  final SocialPreferences preferences;
  final bool loading;
  final bool failed;
  final bool saving;

  /// Null while nothing has loaded yet — the toggles render inert until
  /// there's a real draft to mutate, same intent as the old read-only phase
  /// but now temporary rather than permanent.
  final void Function(SocialPreferences Function(SocialPreferences))? onChanged;
  final VoidCallback? onSave;

  const SocialPreferencesBody({
    super.key,
    required this.preferences,
    required this.loading,
    required this.failed,
    this.saving = false,
    this.onChanged,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = preferences;
    final editable = onChanged != null;

    return SocialScreenShell(
      title: 'Preferences',
      subtitle: 'Auto-share & publishing defaults',
      bottomPadding: 100,
      children: [
        const SizedBox(height: 18),
        if (failed)
          DashboardCard(
            child: Text(
              "Couldn't load your preferences. Try again in a moment.",
              style: AppTextStyles.caption.copyWith(
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          )
        else ...[
          DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SocialCardHeading(
                  'Auto-share',
                  'Automatically pre-select publishing when you create these.',
                ),
                const SizedBox(height: 14),
                ..._toggles(
                  const [
                    'Properties',
                    'Projects',
                    'Videos',
                    'Reels',
                    'Blogs',
                    'Promotions',
                    'Open Houses',
                  ],
                  [
                    prefs.autoShareProperty,
                    prefs.autoShareProjects,
                    prefs.autoShareVideos,
                    prefs.autoShareReels,
                    prefs.autoShareBlogs,
                    prefs.autoSharePromotions,
                    prefs.autoShareOpenHouses,
                  ],
                  onChanged == null
                      ? null
                      : [
                          (v) =>
                              (p) => p.copyWith(autoShareProperty: v),
                          (v) =>
                              (p) => p.copyWith(autoShareProjects: v),
                          (v) =>
                              (p) => p.copyWith(autoShareVideos: v),
                          (v) =>
                              (p) => p.copyWith(autoShareReels: v),
                          (v) =>
                              (p) => p.copyWith(autoShareBlogs: v),
                          (v) =>
                              (p) => p.copyWith(autoSharePromotions: v),
                          (v) =>
                              (p) => p.copyWith(autoShareOpenHouses: v),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SocialCardHeading(
                  'Default targets',
                  'Which platforms/placements are pre-checked on '
                      '"Publish Everywhere".',
                ),
                const SizedBox(height: 14),
                ..._toggles(
                  const [
                    'Facebook',
                    'Instagram',
                    'Instagram Feed',
                    'Instagram Reel',
                    'Facebook Story',
                    'Instagram Story',
                  ],
                  [
                    prefs.fbEnabled,
                    prefs.igEnabled,
                    prefs.igFeed,
                    prefs.igReel,
                    prefs.fbStory,
                    prefs.igStory,
                  ],
                  onChanged == null
                      ? null
                      : [
                          (v) =>
                              (p) => p.copyWith(fbEnabled: v),
                          (v) =>
                              (p) => p.copyWith(igEnabled: v),
                          (v) =>
                              (p) => p.copyWith(igFeed: v),
                          (v) =>
                              (p) => p.copyWith(igReel: v),
                          (v) =>
                              (p) => p.copyWith(fbStory: v),
                          (v) =>
                              (p) => p.copyWith(igStory: v),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SocialCardHeading(
                  'Caption defaults',
                  "Captions are written automatically from each item's title "
                      '& details — these are optional extras.',
                ),
                const SizedBox(height: 14),
                const SocialFieldLabel('Auto-share rule'),
                const SizedBox(height: 6),
                _AutoShareRuleField(
                  value: prefs.autoShareRule,
                  enabled: editable,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!((p) => p.copyWith(autoShareRule: v)),
                ),
                const SizedBox(height: 14),
                const SocialFieldLabel(
                  'Default hashtags (comma separated, max 30)',
                ),
                const SizedBox(height: 6),
                _HashtagsField(
                  value: prefs.defaultHashtags.join(', '),
                  enabled: editable,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(
                          (p) => p.copyWith(
                            defaultHashtags: v
                                .split(RegExp(r'[,\n]'))
                                .map((h) => h.trim().replaceAll('#', ''))
                                .where((h) => h.isNotEmpty)
                                .take(30)
                                .toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                const SocialFieldLabel('Default call to action'),
                const SizedBox(height: 6),
                _CtaField(
                  value: prefs.defaultCta ?? '',
                  enabled: editable,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(
                          (p) => p.copyWith(
                            defaultCta: v.trim().isEmpty ? null : v.trim(),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
          AppActionButton(
            label: saving ? 'Saving…' : 'Save settings',
            height: 46,
            elevated: true,
            onTap: (onSave == null || saving) ? null : onSave,
          ),
        ],
      ],
    );
  }

  /// The design's 46 dp bordered switch rows, 8 dp apart. `onEdits[i]` maps a
  /// new value to a preference-copy — null renders every row dimmed and
  /// inert (nothing loaded yet), same visual the old permanently-read-only
  /// phase used.
  List<Widget> _toggles(
    List<String> labels,
    List<bool> values,
    List<SocialPreferences Function(SocialPreferences) Function(bool)>? onEdits,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        ToggleRow(
          label: labels[i],
          value: values[i],
          bordered: true,
          onChanged: onEdits == null ? null : (v) => onChanged!(onEdits[i](v)),
        ),
      );
    }
    return rows;
  }
}

/// The portal's `auto_share_rule` select — same documented token set as the
/// `social_share_preferences.auto_share_rule` column (no DB CHECK enforces
/// it, so these are the values the app itself always writes).
class _AutoShareRuleField extends StatelessWidget {
  static const _options = [
    ('all', 'Every item'),
    ('luxury', 'Luxury only'),
    ('commercial', 'Commercial only'),
    ('projects', 'Projects only'),
    ('builders', 'Builders only'),
    ('videos', 'Videos only'),
    ('blogs', 'Blogs only'),
  ];

  final String value;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _AutoShareRuleField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final known = _options.any((o) => o.$1 == value);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: known ? value : 'all',
          isExpanded: true,
          isDense: true,
          onChanged: (!enabled || onChanged == null)
              ? null
              : (v) {
                  if (v != null) onChanged!(v);
                },
          items: [
            for (final o in _options)
              DropdownMenuItem(value: o.$1, child: Text(o.$2)),
          ],
        ),
      ),
    );
  }
}

class _HashtagsField extends StatefulWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _HashtagsField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_HashtagsField> createState() => _HashtagsFieldState();
}

class _HashtagsFieldState extends State<_HashtagsField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  String _lastExternal = '';

  @override
  void initState() {
    super.initState();
    _lastExternal = widget.value;
  }

  @override
  void didUpdateWidget(_HashtagsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync from outside if the user hasn't typed since the last sync
    // (avoids clobbering a caret mid-edit on every keystroke's rebuild).
    if (widget.value != _lastExternal && widget.value != _controller.text) {
      _controller.text = widget.value;
      _lastExternal = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      maxLines: 2,
      onChanged: (v) {
        _lastExternal = v;
        widget.onChanged?.call(v);
      },
      style: AppTextStyles.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'realestate, propcid',
        hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CtaField extends StatefulWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _CtaField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_CtaField> createState() => _CtaFieldState();
}

class _CtaFieldState extends State<_CtaField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  String _lastExternal = '';

  @override
  void initState() {
    super.initState();
    _lastExternal = widget.value;
  }

  @override
  void didUpdateWidget(_CtaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _lastExternal && widget.value != _controller.text) {
      _controller.text = widget.value;
      _lastExternal = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: (v) {
        _lastExternal = v;
        widget.onChanged?.call(v);
      },
      style: AppTextStyles.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'e.g. Call now or DM us for a viewing',
        hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
