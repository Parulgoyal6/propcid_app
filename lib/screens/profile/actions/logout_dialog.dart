import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';

/// Logout confirmation dialog.
///
/// Extracted verbatim from `_ProfileScreenState._showLogoutDialog` so the
/// Profile screen, the Workspace Drawer, the More bottom sheet and the
/// Settings sheet can all invoke one implementation instead of duplicating it
/// — see blueprint §1.2.4 and §6. The dialog body (copy/styling) is
/// unchanged; the post-logout navigation now comes from
/// `AuthProvider.logout()` itself (the single owner of all auth-driven
/// navigation — see `auth_provider.dart`), not from a second
/// `pushNamedAndRemoveUntil` here.
void showLogoutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.logout, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Logout'),
        ],
      ),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            authProvider.logout();
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
}
