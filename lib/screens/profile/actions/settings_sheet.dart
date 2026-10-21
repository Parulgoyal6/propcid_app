import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/notification_alert_preference.dart';
import 'change_password_screen.dart';
import 'logout_dialog.dart';

/// Settings bottom sheet.
///
/// Started as five toggles extracted verbatim from
/// `_ProfileScreenState._showSettingsScreen` — Dark Mode, Push Notifications,
/// Location Services, Language and Email Updates — every one a hard-coded
/// value with an empty `(value) {}` callback. None of them changed anything;
/// picking a switch just visually flipped it and forgot the choice on the
/// next open.
///
/// Checked against what this app actually has (no `ThemeMode`/dark palette,
/// no `flutter_localizations`/ARB files, no `profiles` email-preference
/// column or digest sender, and `geolocator`'s own `LocationService` wrapper
/// with nothing in the app calling it for a "nearby properties" feature) —
/// four of the five had nothing real to connect to and were removed rather
/// than kept as decoration. Only "Push Notifications" had a genuine, already
/// -running behavior underneath it — the Notification Centre's arrival sound
/// and vibration (`NotificationProvider._onInserted`) — so it stays,
/// retitled to describe that honestly and wired to
/// [NotificationAlertPreference] instead of a switch that reset itself.
void showSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _SettingsSheetBody(),
  );
}

class _SettingsSheetBody extends StatefulWidget {
  const _SettingsSheetBody();

  @override
  State<_SettingsSheetBody> createState() => _SettingsSheetBodyState();
}

class _SettingsSheetBodyState extends State<_SettingsSheetBody> {
  static const int _gracePeriodDays = 14;
  static const List<String> _monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Null while the persisted value is still loading — [_buildSettingItem]
  /// renders that as a plain chevron rather than guessing a switch position.
  bool? _alertsEnabled;

  /// Null while there's no pending request (or it hasn't loaded yet) — the
  /// "Delete Account" tile shows normally either way. Holds `id`/`created_at`
  /// from the caller's own row, readable under
  /// "Users can view their own deletion requests" RLS.
  Map<String, dynamic>? _pendingDeletion;
  bool _cancellingDeletion = false;

  @override
  void initState() {
    super.initState();
    NotificationAlertPreference.isEnabled().then((value) {
      if (mounted) setState(() => _alertsEnabled = value);
    });
    _fetchPendingDeletion();
  }

  Future<void> _fetchPendingDeletion() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('account_deletion_requests')
          .select('id, created_at')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .maybeSingle();
      if (mounted) setState(() => _pendingDeletion = row);
    } catch (_) {
      // Fails open — the tile just shows the normal "Delete Account" entry.
    }
  }

  Future<void> _cancelDeletion() async {
    final request = _pendingDeletion;
    if (request == null) return;
    setState(() => _cancellingDeletion = true);
    try {
      await Supabase.instance.client.rpc(
        'cancel_own_deletion_request',
        params: {'p_request_id': request['id']},
      );
      if (!mounted) return;
      setState(() {
        _pendingDeletion = null;
        _cancellingDeletion = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account deletion request has been withdrawn.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancellingDeletion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Failed to cancel your request. Please try again.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// `created_at` + the grace period, formatted "12 Sep 2026" — same shape
  /// `property_detail_screen.dart` already uses elsewhere, no new
  /// date-formatting dependency.
  String _deletionDateLabel(String createdAt) {
    final created = DateTime.tryParse(createdAt) ?? DateTime.now();
    final date = created.add(const Duration(days: _gracePeriodDays));
    return '${date.day} ${_monthAbbreviations[date.month - 1]} ${date.year}';
  }

  Future<void> _setAlertsEnabled(bool value) async {
    setState(() => _alertsEnabled = value);
    await NotificationAlertPreference.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
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
                  'Settings',
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
                _buildSettingItem(
                  Icons.notifications_outlined,
                  'Notification Alerts',
                  'Sound and vibration for new activity',
                  _alertsEnabled,
                  (value) => _setAlertsEnabled(value),
                ),
                const SizedBox(height: 12),
                _buildNavItem(
                  Icons.lock_outline,
                  'Change Password',
                  'Update your sign-in password',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.logout,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.red,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      showLogoutDialog(context);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_pendingDeletion != null)
                  _buildPendingDeletionCard()
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_forever_outlined,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.red,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          AppConstants.accountDeletionScreen,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDeletionCard() {
    final request = _pendingDeletion!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.access_time, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your account deletion request is in process. Your account '
                  'will be deleted on '
                  '${_deletionDateLabel(request['created_at'] as String)} '
                  'unless you cancel before then.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _cancellingDeletion ? null : _cancelDeletion,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: Text(
              _cancellingDeletion ? 'Cancelling…' : 'Cancel Deletion Request',
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain navigation row — same visual shell as [_buildSettingItem] but a
/// chevron-and-tap instead of a switch, for an action that opens another
/// screen rather than toggling a preference in place.
Widget _buildNavItem(
  IconData icon,
  String title,
  String subtitle, {
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textHint.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ],
      ),
    ),
  );
}

Widget _buildSettingItem(
  IconData icon,
  String title,
  String subtitle,
  bool? value,
  Function(bool) onChanged,
) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.textHint.withOpacity(0.1)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
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
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (value != null)
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          )
        else
          const Icon(Icons.chevron_right, color: AppColors.textHint),
      ],
    ),
  );
}
