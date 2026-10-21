import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The design system's switch.
///
/// Spec: track `40×24` radius `999`, ON `#5B50E8` / OFF `#EDEDF2`, knob
/// `20×20` white sliding `left: 2 → 18` over `.15s ease`.
///
/// Deliberately not Material's [Switch]. That widget is `52×32` with its own
/// knob proportions and cannot be resized to `40×24` without a
/// `Transform.scale` that distorts the knob and the tap target. At ~40 lines a
/// purpose-built toggle matches the design exactly and stays predictable.
class AppToggle extends StatelessWidget {
  final bool value;

  /// Null renders the toggle in a non-interactive, dimmed state.
  final ValueChanged<bool>? onChanged;

  /// Track and knob geometry. Defaults are the settings-row spec above; the
  /// Upgrade screen's billing-period switch is the design's larger `44×26`
  /// variant with a `22` knob, which keeps the same 2 dp inset and travel.
  final double trackWidth;
  final double trackHeight;
  final double knobSize;

  /// Track colour when [value] is false.
  ///
  /// Overridable because the billing-period switch is not an on/off control —
  /// it selects between Monthly and Yearly, so the design keeps the track
  /// primary in both positions rather than greying it out.
  final Color inactiveTrackColor;

  const AppToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.trackWidth = 40,
    this.trackHeight = 24,
    this.knobSize = 20,
    this.inactiveTrackColor = AppColors.hairline,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: trackWidth,
            height: trackHeight,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : inactiveTrackColor,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  // 2 dp inset when off, and the mirrored inset when on — 18 dp
                  // at the default size, 20 dp for the 44 dp billing track.
                  left: value ? trackWidth - knobSize - 2 : 2,
                  top: (trackHeight - knobSize) / 2,
                  child: Container(
                    width: knobSize,
                    height: knobSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row: label (+ optional description) on the left, [AppToggle] on
/// the right.
///
/// Used by Social Preferences (13 toggles across two sections) and the Network
/// Communication Hub's Settings tab (2 toggles).
class ToggleRow extends StatelessWidget {
  final String label;

  /// Secondary line beneath the label. Omitted when null, matching the rows in
  /// the design that are label-only.
  final String? description;

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Draws a hairline under the row so a run of them reads as a grouped list.
  final bool showDivider;

  /// Renders the row as the design's standalone 46 dp bordered box — the shape
  /// Social ▸ Preferences uses — instead of a flat row in a grouped list.
  final bool bordered;

  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.description,
    this.showDivider = false,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      toggled: value,
      child: Container(
        // 46 dp is the design's height, applied as a *minimum* rather than a
        // fixed size: on a narrow screen a label like "Instagram Story" wraps
        // to two lines, and a hard 46 would squash it. Normal-width rows still
        // land on exactly 46.
        constraints: bordered ? const BoxConstraints(minHeight: 46) : null,
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: bordered ? AppConstants.spacingS : AppConstants.spacingM,
        ),
        decoration: bordered
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                border: Border.all(color: AppColors.hairline),
              )
            : (showDivider
                  ? const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.hairline),
                      ),
                    )
                  : null),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            // ExcludeSemantics: the row already announces label + state, so the
            // inner toggle would otherwise be read out twice.
            ExcludeSemantics(
              child: AppToggle(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
