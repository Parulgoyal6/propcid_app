import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether an [AuthException] raised by `Supabase.auth.updateUser(password:)`
/// during a registration screen's submit is harmless and should let
/// registration continue, rather than abort it.
///
/// `same_password` means the account's password already matches what's being
/// set — typically a previous, partially-successful submit (password updated
/// successfully, then the backend registration-submit call failed) being
/// retried with the same value. That is not a real authentication failure,
/// so it must not block the retry from ever reaching the backend. Every
/// other code is a genuine auth problem and must still abort registration —
/// this checks the structured `code` only, never the HTTP status or message
/// text.
///
/// Shared by the broker/builder/influencer registration screens and
/// IndividualUsernamePasswordScreen — each wraps only its own
/// `updateUser` call in `on AuthException catch (e) { if
/// (!isHarmlessSamePasswordError(e)) rethrow; }`, so this is the one place
/// the actual decision is both made and unit-tested.
bool isHarmlessSamePasswordError(AuthException e) => e.code == 'same_password';
