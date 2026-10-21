import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';

/// A single action used across the reels feed — originally the vertical
/// right-rail (like / comment / share / save), now also reused (same
/// business logic, callbacks, and provider wiring) inside the horizontal
/// action row on the new white property card.
///
/// Animates a spring "pop" on tap and supports an active tint.
class ReelActionButton extends StatefulWidget {
  const ReelActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
    this.activeIcon,
    this.axis = Axis.vertical,
    this.baseColor,
    this.labelColor,
    this.iconSize = 26,
    this.iconBoxSize = 46,
    this.showIconBackground = true,
    this.showLabelShadow,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeColor;

  /// Layout direction for icon + label. Defaults to [Axis.vertical] to
  /// preserve the original right-rail look. Pass [Axis.horizontal] for the
  /// new horizontal action row on the white card.
  final Axis axis;

  /// Icon color when not active. Defaults to white (original dark-video
  /// overlay usage). Pass a dark color when placing this on a light/white
  /// background (e.g. the new property card).
  final Color? baseColor;

  /// Label text color. Defaults to match [baseColor].
  final Color? labelColor;

  final double iconSize;
  final double iconBoxSize;

  /// Whether to draw the translucent circular backdrop behind the icon.
  /// The original video-overlay buttons use this; the new light-background
  /// action row looks cleaner without it.
  final bool showIconBackground;

  /// Whether the label text gets a drop shadow (for legibility over a
  /// busy video background). Defaults to matching [showIconBackground]
  /// (preserves old behavior); pass explicitly to decouple the two — e.g.
  /// a plain-white video overlay button with no icon backdrop but a text
  /// shadow for legibility.
  final bool? showLabelShadow;

  @override
  State<ReelActionButton> createState() => _ReelActionButtonState();
}

class _ReelActionButtonState extends State<ReelActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0).then((_) => _controller.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = widget.activeColor ?? Colors.white;
    final Color base = widget.baseColor ?? Colors.white;
    final Color labelColor = widget.labelColor ?? base;
    final IconData icon = widget.isActive
        ? (widget.activeIcon ?? widget.icon)
        : widget.icon;

    final iconWidget = ScaleTransition(
      scale: _scale,
      child: Container(
        width: widget.iconBoxSize,
        height: widget.iconBoxSize,
        decoration: widget.showIconBackground
            ? BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              )
            : null,
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: widget.isActive ? activeColor : base,
          size: widget.iconSize,
        ),
      ),
    );

    final labelWidget = Text(
      widget.label,
      style: AppTextStyles.caption.copyWith(
        color: widget.isActive ? activeColor : labelColor,
        fontSize: widget.axis == Axis.horizontal ? 13 : 11,
        fontWeight: FontWeight.w600,
        shadows: (widget.showLabelShadow ?? widget.showIconBackground)
            ? const [Shadow(color: Colors.black54, blurRadius: 4)]
            : null,
      ),
    );

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: widget.axis == Axis.vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [iconWidget, const SizedBox(height: 6), labelWidget],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [iconWidget, const SizedBox(width: 8), labelWidget],
            ),
    );
  }
}
