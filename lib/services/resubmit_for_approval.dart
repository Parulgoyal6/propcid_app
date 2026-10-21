// services/resubmit_for_approval.dart
//
// Sends an owner's edit of already-published content back to review, the way
// the website does: every save by a non-admin demotes the row to
// `approval_status = 'pending'`.
//
// `approval_status` is a staff-only column (trg_guard_staff_cols), so a plain
// client UPDATE cannot touch it. `resubmit_for_approval` is a SECURITY DEFINER
// RPC that checks ownership itself and does the demotion.
//
// CALL THIS BEFORE writing the edited fields, so the previous-approved snapshot
// trigger still sees the untouched last-approved row.
//
// Admins publish straight through on the website, so they are skipped here.
import 'package:supabase_flutter/supabase_flutter.dart';

const List<String> _adminRoles = ['admin', 'super_admin'];

/// Returns true when the row was moved to pending, false when skipped (admin)
/// or the caller does not own the row. Throws on RPC failure so the edit is not
/// saved as if it had been re-queued.
Future<bool> resubmitForApproval(
  SupabaseClient client, {
  required String table,
  required String id,
}) async {
  final uid = client.auth.currentUser?.id;
  if (uid == null) return false;

  final profile = await client
      .from('profiles')
      .select('user_role')
      .eq('user_id', uid)
      .maybeSingle();
  if (_adminRoles.contains(profile?['user_role'])) return false;

  final result = await client.rpc(
    'resubmit_for_approval',
    params: {'p_table': table, 'p_id': id},
  );
  return result == true;
}
