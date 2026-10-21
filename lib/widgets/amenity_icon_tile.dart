import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_text_styles.dart';

class AmenityIconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const AmenityIconTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: AppConstants.amenityIconSize,
          height: AppConstants.amenityIconSize,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
