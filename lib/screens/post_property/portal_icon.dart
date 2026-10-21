import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a lucide-react icon from `assets/lucide`.
///
/// The SVGs are generated straight out of the portal's own
/// `node_modules/lucide-react` by `scripts/t0/gen_lucide.py`, so these are the
/// same shapes the portal draws — not Material look-alikes.
///
/// lucide artwork is stroke-based on a 24x24 viewBox with
/// `stroke="currentColor"`, so tinting is a `srcIn` colour filter.
class PortalIcon extends StatelessWidget {
  const PortalIcon(this.name, {super.key, this.size = 20, this.color});

  /// lucide's kebab-case name, e.g. `file-text`, `building`, `arrow-right`.
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.black;
    return SvgPicture.asset(
      'assets/lucide/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}

/// lucide icon names for the wizard steps, from the `icon` field on each entry
/// of `stepsRaw` (PropertyWizard.tsx:1350).
class PortalStepIcons {
  PortalStepIcons._();

  static const String category = 'building'; // Building
  static const String basicInfo = 'file-text'; // FileText
  static const String dimensions = 'building'; // Building
  static const String condition = 'file-text'; // FileText
  static const String amenities = 'list'; // List
  static const String legal = 'file-text'; // FileText
  static const String pricing = 'building'; // Building
  static const String media = 'image'; // Image

  /// Flutter-only Review step; the portal has no equivalent.
  static const String review = 'file-check-2';
}
