// screens/profile/widgets/public_profile_info_cards.dart
//
// About, Contact (locked / unlocked), Details and the social link row.
//
// Every card is built on the shared `DashboardCard` / `DashboardCardTitle` /
// `DashboardSectionLabel` primitives, so surface, radius, shadow, padding and
// title weight match the rest of the app without restating them.
// `ImageFilter` for the locked-contact blur comes from dart:ui — material
// exports `ImageFiltered` but not the filter itself.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/shared/app_action_button.dart';
import '../../../widgets/shared/app_surface_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// About
// ─────────────────────────────────────────────────────────────────────────────

/// Bio, clamped to four lines with a "Read more" that appears only when the text
/// actually overflows.
class ProfileAboutCard extends StatefulWidget {
  final String bio;

  const ProfileAboutCard({super.key, required this.bio});

  @override
  State<ProfileAboutCard> createState() => _ProfileAboutCardState();
}

class _ProfileAboutCardState extends State<ProfileAboutCard> {
  static const int _collapsedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.body.copyWith(
      fontSize: 13.5,
      height: 1.55,
      color: AppColors.textSecondary,
    );

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardCardTitle('About'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // Measured rather than guessed: showing "Read more" under text that
              // already fits is a small but constant irritation.
              final painter = TextPainter(
                text: TextSpan(text: widget.bio, style: style),
                maxLines: _collapsedLines,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);

              final overflows = painter.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: const Duration(
                      milliseconds: AppConstants.animationDurationMs,
                    ),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Text(
                      widget.bio,
                      style: style,
                      maxLines: _expanded ? null : _collapsedLines,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                  ),
                  if (overflows) ...[
                    const SizedBox(height: AppConstants.spacingS),
                    ScaleTap(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Semantics(
                        button: true,
                        label: _expanded ? 'Read less' : 'Read more',
                        child: Text(
                          _expanded ? 'Read less' : 'Read more',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact
// ─────────────────────────────────────────────────────────────────────────────

/// Contact details, gated on connection.
///
/// The portal reveals phone and email only when `networkStatus === 'connected'`
/// or you are the owner (UserProfile.tsx:1520). The address is always public.
///
/// When locked, the real values are **never placed in the widget tree** — the
/// blurred plate is built from empty grey bars. Blurring a real value would leave
/// it readable in the widget inspector, in the semantics tree, and to anything
/// that reads the render object.
class ProfileContactCard extends StatelessWidget {
  final UserProfile profile;

  /// Whether the viewer may see phone and email.
  final bool unlocked;

  /// Null hides the Connect affordance — used for a self-view and while the
  /// connection state is still resolving.
  final VoidCallback? onConnect;

  const ProfileContactCard({
    super.key,
    required this.profile,
    required this.unlocked,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked
                    ? Icons.contact_page_outlined
                    : Icons.lock_outline_rounded,
                size: 16,
                color: unlocked ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              const DashboardCardTitle('Contact'),
            ],
          ),
          const SizedBox(height: AppConstants.spacingM),
          // 300 ms fade + resize as the card unlocks — the payoff for connecting.
          AnimatedSwitcher(
            duration: const Duration(
              milliseconds: AppConstants.animationDurationMs,
            ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              // `alignment`, not the deprecated `axisAlignment`: the card grows
              // downward from its top edge so the title stays put.
              child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: unlocked
                ? _UnlockedBody(
                    profile: profile,
                    key: const ValueKey('unlocked'),
                  )
                : _LockedBody(
                    profile: profile,
                    onConnect: onConnect,
                    key: const ValueKey('locked'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UnlockedBody extends StatelessWidget {
  final UserProfile profile;

  const _UnlockedBody({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final phone = profile.effectivePhone;
    final email = profile.email;
    final address = profile.effectiveAddress;

    final rows = <Widget>[
      if (phone != null)
        _ContactActionRow(
          icon: Icons.call_outlined,
          label: 'Phone',
          value: phone,
          actionIcon: Icons.north_east_rounded,
          onTap: () => _launch(Uri(scheme: 'tel', path: phone)),
        ),
      if (email != null)
        _ContactActionRow(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: email,
          actionIcon: Icons.north_east_rounded,
          onTap: () => _launch(Uri(scheme: 'mailto', path: email)),
        ),
      if (address != null)
        _ContactActionRow(
          icon: Icons.place_outlined,
          label: 'Address',
          value: address,
          actionIcon: Icons.map_outlined,
          onTap: () => _launch(
            Uri.parse(
              'https://www.google.com/maps/search/?api=1'
              '&query=${Uri.encodeComponent(address)}',
            ),
          ),
        ),
    ];

    if (rows.isEmpty) {
      return Text(
        'No contact details shared yet.',
        style: AppTextStyles.caption.copyWith(fontSize: 12.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: AppConstants.spacingM),
            const Divider(height: 1, thickness: 1, color: AppColors.hairline),
            const SizedBox(height: AppConstants.spacingM),
          ],
          rows[i],
        ],
      ],
    );
  }

  /// Best-effort: a device with no dialler or mail client must not throw.
  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Intentionally silent — there is nothing useful to tell the user, and the
      // row simply does nothing, which is the same as the portal's behaviour on
      // an unsupported scheme.
    }
  }
}

class _ContactActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final IconData actionIcon;
  final VoidCallback onTap;

  const _ContactActionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.actionIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      button: true,
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              Icon(actionIcon, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedBody extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onConnect;

  const _LockedBody({super.key, required this.profile, this.onConnect});

  @override
  Widget build(BuildContext context) {
    final address = profile.effectiveAddress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Contact details locked. Connect to view.',
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              ),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Column(
                  children: [
                    _placeholderRow(widthFactor: 0.55),
                    const SizedBox(height: AppConstants.spacingM),
                    _placeholderRow(widthFactor: 0.72),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Connect to view contact details',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
        if (onConnect != null) ...[
          const SizedBox(height: AppConstants.spacingM),
          AppActionButton(
            label: 'Connect',
            icon: Icons.person_add_alt_1_rounded,
            variant: AppActionButtonVariant.outline,
            height: 44,
            onTap: onConnect,
          ),
        ],
        // The address stays public even while locked — portal parity.
        if (address != null) ...[
          const SizedBox(height: AppConstants.spacingM),
          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
          const SizedBox(height: AppConstants.spacingM),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// A circle and two bars: the *shape* of a contact row, carrying no data.
  Widget _placeholderRow({required double widthFactor}) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: AppColors.hairline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: widthFactor,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details
// ─────────────────────────────────────────────────────────────────────────────

/// One label/value pair.
@immutable
class ProfileDetailRow {
  final String label;
  final String? value;

  /// Rendered as chips rather than a comma-joined string.
  final List<String> chips;

  /// Opens externally when tapped — used for the website row.
  final String? linkUrl;

  const ProfileDetailRow({
    required this.label,
    this.value,
    this.chips = const [],
    this.linkUrl,
  });

  bool get hasContent =>
      (value != null && value!.isNotEmpty) || chips.isNotEmpty;
}

/// A titled group of rows inside the Details card.
@immutable
class ProfileDetailGroup {
  final String title;
  final List<ProfileDetailRow> rows;

  const ProfileDetailGroup({required this.title, required this.rows});

  List<ProfileDetailRow> get populated =>
      rows.where((r) => r.hasContent).toList(growable: false);
}

/// The portal's five separate sidebar cards, merged into one grouped card with
/// progressive disclosure.
///
/// On a phone, five always-expanded boxes of label/value pairs is a lot of
/// scrolling for information most visitors skim. The first five rows show; the
/// rest are one tap away.
class ProfileDetailsCard extends StatefulWidget {
  final List<ProfileDetailGroup> groups;

  const ProfileDetailsCard({super.key, required this.groups});

  /// True when at least one group has a populated row — the card is omitted
  /// entirely otherwise.
  static bool hasContent(List<ProfileDetailGroup> groups) =>
      groups.any((g) => g.populated.isNotEmpty);

  @override
  State<ProfileDetailsCard> createState() => _ProfileDetailsCardState();
}

class _ProfileDetailsCardState extends State<ProfileDetailsCard> {
  static const int _collapsedRowBudget = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups
        .where((g) => g.populated.isNotEmpty)
        .toList(growable: false);

    final totalRows = groups.fold<int>(0, (acc, g) => acc + g.populated.length);
    final needsDisclosure = totalRows > _collapsedRowBudget;

    final children = <Widget>[];
    var rendered = 0;

    for (final group in groups) {
      final rows = group.populated;
      final visible = <ProfileDetailRow>[];

      for (final row in rows) {
        if (!_expanded && needsDisclosure && rendered >= _collapsedRowBudget) {
          break;
        }
        visible.add(row);
        rendered++;
      }

      if (visible.isEmpty) continue;

      if (children.isNotEmpty) {
        children.addAll(const [
          SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: AppColors.hairline),
          SizedBox(height: 14),
        ]);
      }

      children.add(DashboardSectionLabel(group.title));
      children.add(const SizedBox(height: 10));

      for (var i = 0; i < visible.length; i++) {
        if (i > 0) children.add(const SizedBox(height: AppConstants.spacingM));
        children.add(_DetailRowView(row: visible[i]));
      }
    }

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardCardTitle('Details'),
          const SizedBox(height: AppConstants.spacingM),
          AnimatedSize(
            duration: const Duration(
              milliseconds: AppConstants.animationDurationMs,
            ),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
          if (needsDisclosure) ...[
            const SizedBox(height: 14),
            ScaleTap(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Semantics(
                button: true,
                label: _expanded ? 'Show fewer details' : 'Show all details',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Flexible: at 1.3x text scale "Show fewer details" measured
                      // 284 dp against 256 dp available at 320 dp width. The
                      // chevron is fixed, so the label is what must give. Found by
                      // test/public_profile_device_validation_test.dart.
                      Flexible(
                        child: Text(
                          _expanded ? 'Show fewer details' : 'Show all details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(
                          milliseconds: AppConstants.animationDurationMs,
                        ),
                        curve: Curves.easeOutCubic,
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRowView extends StatelessWidget {
  final ProfileDetailRow row;

  const _DetailRowView({required this.row});

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.caption.copyWith(
      fontSize: 12.5,
      color: AppColors.textSecondary,
    );

    if (row.chips.isNotEmpty) {
      // Chips need the full width, so they stack under their label.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label, style: labelStyle),
          const SizedBox(height: AppConstants.spacingS),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in row.chips)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(
                      AppConstants.chipRadius,
                    ),
                  ),
                  child: Text(
                    chip,
                    style: AppTextStyles.chip.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    final valueStyle = AppTextStyles.body.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: row.linkUrl == null ? AppColors.textPrimary : AppColors.primary,
    );

    final value = Text(
      row.value!,
      textAlign: TextAlign.right,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: valueStyle,
    );

    // At raised text scale a label and a right-aligned value can no longer share a
    // line without clipping, so the pair stacks.
    //
    // The threshold was `scale(13) > 17`, which at exactly 1.3x yields 16.9 — so
    // the one scale the spec promises to support was the one that did NOT stack,
    // and the Row overflowed by 57 dp at 320 dp. Stacking from ~1.16x instead.
    // Found by test/public_profile_device_validation_test.dart.
    final stacked = MediaQuery.textScalerOf(context).scale(13) >= 15;

    final body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.label, style: labelStyle),
              const SizedBox(height: 2),
              Align(alignment: Alignment.centerLeft, child: value),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flexible as well as the threshold: a belt-and-braces guard so an
              // unusually long label can never overflow even below the stacking
              // point.
              Flexible(
                child: Text(
                  row.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
              const SizedBox(width: AppConstants.spacingL),
              Expanded(child: value),
            ],
          );

    if (row.linkUrl == null) return body;

    return ScaleTap(
      onTap: () => _openLink(row.linkUrl!),
      child: Semantics(
        button: true,
        label: '${row.label} ${row.value}',
        child: body,
      ),
    );
  }

  /// Normalises a scheme-less value, exactly as the portal does
  /// (UserProfile.tsx:1321: `startsWith('http') ? value : 'https://$value'`).
  Future<void> _openLink(String raw) async {
    final normalised = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    try {
      await launchUrl(
        Uri.parse(normalised),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Silent, as above.
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Social links
// ─────────────────────────────────────────────────────────────────────────────

/// Brand-coloured circular links.
///
/// Platform brand colours are the one permitted exception to the palette: they
/// are identity, not theme. Using `AppColors.primary` for all six would make them
/// unrecognisable at 18 dp.
class ProfileSocialLinksRow extends StatelessWidget {
  final UserProfile profile;

  const ProfileSocialLinksRow({super.key, required this.profile});

  static bool hasContent(UserProfile profile) =>
      profile.socialMedia.hasAnySocialLink;

  @override
  Widget build(BuildContext context) {
    final sm = profile.socialMedia;

    final links = <_SocialLink>[
      if (sm.facebook != null)
        _SocialLink(
          'Facebook',
          FontAwesomeIcons.facebook,
          const Color(0xFF1877F2),
          sm.facebook!,
        ),
      if (sm.instagram != null)
        _SocialLink(
          'Instagram',
          FontAwesomeIcons.instagram,
          const Color(0xFFE4405F),
          sm.instagram!,
        ),
      if (sm.linkedin != null)
        _SocialLink(
          'LinkedIn',
          FontAwesomeIcons.linkedin,
          const Color(0xFF0A66C2),
          sm.linkedin!,
        ),
      if (sm.youtube != null)
        _SocialLink(
          'YouTube',
          FontAwesomeIcons.youtube,
          const Color(0xFFFF0000),
          sm.youtube!,
        ),
      if (sm.whatsapp != null)
        _SocialLink(
          'WhatsApp',
          FontAwesomeIcons.whatsapp,
          const Color(0xFF25D366),
          sm.whatsapp!,
        ),
      if (sm.telegram != null)
        _SocialLink(
          'Telegram',
          FontAwesomeIcons.telegram,
          const Color(0xFF229ED9),
          sm.telegram!,
        ),
      if (sm.twitter != null)
        _SocialLink(
          'X',
          FontAwesomeIcons.xTwitter,
          const Color(0xFF1A1A2E),
          sm.twitter!,
        ),
    ];

    if (links.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final link in links) _SocialPill(link: link)],
    );
  }
}

@immutable
class _SocialLink {
  final String name;
  final FaIconData icon;
  final Color color;
  final String raw;

  const _SocialLink(this.name, this.icon, this.color, this.raw);

  /// Handles the two shorthand forms the portal normalises: a bare WhatsApp
  /// number (UserProfile.tsx:1576) and a bare Telegram handle
  /// (UserProfile.tsx:1581).
  String get url {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    switch (name) {
      case 'WhatsApp':
        final digits = raw.replaceAll(RegExp(r'\D'), '');
        return 'https://wa.me/$digits';
      case 'Telegram':
        return 'https://t.me/${raw.replaceAll('@', '')}';
      default:
        return 'https://$raw';
    }
  }
}

class _SocialPill extends StatelessWidget {
  final _SocialLink link;

  const _SocialPill({required this.link});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${link.name}',
      child: ScaleTap(
        onTap: () async {
          try {
            await launchUrl(
              Uri.parse(link.url),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {
            // Silent — a malformed stored handle should not crash the screen.
          }
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Center(child: FaIcon(link.icon, size: 18, color: link.color)),
        ),
      ),
    );
  }
}
