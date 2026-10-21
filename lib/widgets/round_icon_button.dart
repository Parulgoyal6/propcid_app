import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Small circular icon button used for the compare-toggle affordance on
/// every reusable property card (vertical/horizontal/compact/search-row) —
/// pulled into one widget so the four cards render it identically instead of
/// four near-duplicate `Container`s.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.semanticLabel,
    this.onTap,
    this.size = 36,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color color;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            shape: BoxShape.circle,
            boxShadow: AppColors.cardShadow,
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
      ),
    );
  }
}
