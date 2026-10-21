import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/validation/validators.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';

/// Name/email edit dialog — the fallback used for individual users, who have
/// no dedicated registration screen the way builders, brokers and influencers
/// do.
///
/// Writes straight to `profiles` via [AuthService.updateProfileFields] —
/// display_name/email only, matching the portal's own individual edit
/// (`EditProfile.tsx:470`), which likewise just updates those two `profiles`
/// columns rather than the Supabase Auth email itself.
///
/// Previously this called [AuthProvider.updateProfile], which only updates
/// the provider's in-memory `_userName`/`_userEmail` — nothing was ever
/// written to the database, so the "Profile updated" snackbar was shown for a
/// change that silently reverted on the next profile fetch.
void showEditProfileDialog(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final nameController = TextEditingController(text: authProvider.userName);
  final emailController = TextEditingController(text: authProvider.userEmail);
  final saving = ValueNotifier<bool>(false);

  showDialog(
    context: context,
    builder: (dialogContext) => ValueListenableBuilder<bool>(
      valueListenable: saving,
      builder: (dialogContext, isSaving, _) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              enabled: !isSaving,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              enabled: !isSaving,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    final name = nameController.text.trim();
                    final emailVal = emailController.text.trim();
                    final nameErr = Validators.required(name);
                    final emailErr =
                        Validators.required(emailVal) ??
                        Validators.email(emailVal);
                    if (nameErr != null || emailErr != null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(nameErr ?? emailErr!)),
                      );
                      return;
                    }

                    final userId = authProvider.userId;
                    if (userId == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You must be logged in to update your profile.',
                          ),
                        ),
                      );
                      return;
                    }

                    saving.value = true;
                    try {
                      await AuthService().updateProfileFields(userId, {
                        'display_name': name,
                        'email': emailVal,
                      });
                      await authProvider.refreshProfile();
                    } catch (e) {
                      saving.value = false;
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not save your profile. Please try again.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully'),
                      ),
                    );
                  },
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
