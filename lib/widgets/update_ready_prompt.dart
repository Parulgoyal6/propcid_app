import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// The one user-facing surface of the flexible in-app update flow — shown
/// only after Play has finished downloading an update in the background.
/// Styling mirrors the delete-comment confirmation dialog
/// (post_comments_sheet.dart's `_delete`) for visual consistency with the
/// rest of the app's AlertDialogs.
void showUpdateReadyPrompt(
  BuildContext context, {
  required VoidCallback onRestart,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Update ready'),
      content: Text(
        'A new version of PropCID is ready. Restart to complete the update.',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            onRestart();
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: const Text('Restart now'),
        ),
      ],
    ),
  );
}
