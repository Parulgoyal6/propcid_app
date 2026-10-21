import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Notifications bottom sheet.
///
/// Extracted verbatim from `_ProfileScreenState._showNotificationsScreen` (and
/// its `_buildNotificationItem` helper) so the rebuilt Profile screen composes
/// it instead of carrying it inline — see blueprint §1.2.4 and §6. Body
/// unchanged.
///
/// Note: the four entries below are the same static placeholders the screen
/// has always shown; wiring this to the real `notifications` table is not part
/// of this workstream. The standalone `/notifications` route
/// (`NotificationsScreen`) is a separate, unrelated screen and is untouched.
void showNotificationsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: AppTextStyles.heading3.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildNotificationItem(
                  'Visit Scheduled',
                  'Your visit for 3BHK Apartment is confirmed for tomorrow at 10:00 AM',
                  '2 hours ago',
                  Icons.calendar_today,
                  AppColors.primary,
                ),
                const SizedBox(height: 12),
                _buildNotificationItem(
                  'Property Price Drop',
                  'The 2BHK Flat you saved is now available at 10% less price',
                  '5 hours ago',
                  Icons.trending_down,
                  const Color(0xFF10B981),
                ),
                const SizedBox(height: 12),
                _buildNotificationItem(
                  'New Property Match',
                  'A new property matching your preferences is available in your area',
                  '1 day ago',
                  Icons.home,
                  const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 12),
                _buildNotificationItem(
                  'Visit Reminder',
                  "Don't forget your scheduled visit for Villa tomorrow",
                  '2 days ago',
                  Icons.alarm,
                  const Color(0xFF3B82F6),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildNotificationItem(
  String title,
  String message,
  String time,
  IconData icon,
  Color color,
) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                time,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textHint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
