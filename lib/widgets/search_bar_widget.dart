import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/frosted_glass.dart';

class SearchBarWidget extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final Widget? trailing;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  // ── Appearance overrides ────────────────────────────────────────────────
  // Purely additive. Every default below reproduces the exact rendering this
  // widget had before these parameters existed, so the Home Screen (its other
  // caller, via PremiumSearchSection) is untouched. The Search Entry screen
  // passes the redesign's taller 54/18 surface.

  /// Overall bar height. 48 is the Home Screen's size.
  final double height;

  /// Corner radius. 14 is the Home Screen's value.
  final double borderRadius;

  /// Drop shadow. Null keeps the Home Screen's existing subtle shadow.
  final List<BoxShadow>? boxShadow;

  /// Inset before the leading search icon. 12 is the Home Screen's gutter.
  final double leadingPadding;

  /// Inset after [trailing]. 12 is the Home Screen's gutter.
  final double trailingPadding;

  /// Gap between the search icon and the field. 8 is the Home Screen's value.
  final double iconGap;

  /// Gap between the field and [trailing]. 0 is the Home Screen's value — its
  /// mic badge sits flush against the expanded field. The Search Entry screen
  /// passes 10 so the badge reads as spaced inside the bar rather than butted
  /// up against the text.
  final double trailingGap;

  /// When true, renders as a frosted/translucent glass surface (backdrop
  /// blur + translucent white + a subtle border) instead of the default
  /// opaque `cardBackground` fill — used by the Home Screen's glassmorphism
  /// redesign. Defaults to false so every other existing caller (e.g. the
  /// Search Entry screen) keeps its exact current opaque appearance.
  final bool glass;

  /// The leading icon. Defaults to the magnifying glass every existing
  /// caller (Home's search preview, this screen previously) already shows.
  final IconData leadingIcon;

  const SearchBarWidget({
    super.key,
    required this.hint,
    this.onTap,
    this.trailing,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.height = 48,
    this.borderRadius = 14,
    this.boxShadow,
    this.leadingPadding = 12,
    this.trailingPadding = 12,
    this.iconGap = 8,
    this.trailingGap = 0,
    this.glass = false,
    this.leadingIcon = Icons.search,
  });

  @override
  Widget build(BuildContext context) {
    final bool isReadOnly = onTap != null;

    final Widget content = Row(
        children: [
          SizedBox(width: leadingPadding),

          Icon(
            leadingIcon,
            color: glass ? AppColors.primary : AppColors.textSecondary,
            size: glass ? 20 : 18,
          ),

          SizedBox(width: iconGap),

          Expanded(
            child: isReadOnly
                ? GestureDetector(
                    onTap: onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hint,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  )
                : TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    textInputAction: TextInputAction.search,
                    autofocus: autofocus,
                    style: AppTextStyles.body.copyWith(height: 1.2),
                    cursorColor: AppColors.primary,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: AppTextStyles.body.copyWith(
                        color: AppColors.textHint,
                        height: 1.2,
                      ),
                      // Every border slot must be nulled out individually, and
                      // `filled` must be switched off explicitly. `border:
                      // InputBorder.none` alone is NOT enough: AppTheme's
                      // global `inputDecorationTheme` sets `filled: true` plus
                      // an `enabledBorder`/`focusedBorder` pair, and those take
                      // precedence over `border` whenever the field is enabled
                      // or focused. The focused variant is a 2 dp primary
                      // outline at a 14 dp radius, so a focused field painted a
                      // second, smaller rounded border (and a second white
                      // fill) inside this widget's own container — the
                      // double-border artefact. This widget draws the only
                      // visible surface; the field itself must be invisible.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      // Zero, not the previous `bottom: 12`. That padding was
                      // compensating for the theme-supplied decoration box;
                      // with the decoration gone, the Row's centre alignment
                      // plus `textAlignVertical` centre the text on its own.
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
          ),

          if (!isReadOnly &&
              controller != null &&
              controller!.text.isNotEmpty) ...[
            IconButton(
              icon: const Icon(
                Icons.clear,
                color: AppColors.textSecondary,
                size: 18,
              ),
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
          ],

          if (trailing != null) ...[SizedBox(width: trailingGap), trailing!],

          SizedBox(width: trailingPadding),
        ],
      );

    if (!glass) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow:
              boxShadow ??
              [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
        ),
        child: content,
      );
    }

    // Glass variant: real frosted glass — backdrop blur, translucent white
    // fill, bright rim and a soft orange-tinted float shadow. Content
    // (icon/text/trailing action) stays fully opaque and readable.
    return FrostedGlass(
      height: height,
      borderRadius: borderRadius,
      blur: 16,
      shadow: boxShadow ?? AppColors.glassShadow,
      borderColor: Colors.white.withValues(alpha: 0.85),
      child: content,
    );
  }
}
