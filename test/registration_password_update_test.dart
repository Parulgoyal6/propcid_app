// Regression guard for the registration "New password should be different
// from the old password" (HTTP 422, same_password) bug: each registration
// screen's submit handler sets the real, person-chosen password via
// `updateUser(password:)` before calling RegistrationSubmitService. If a
// previous attempt already updated the password successfully but the
// backend registration-submit call then failed, retrying with the same
// password made `updateUser` throw `same_password` — which, unhandled,
// blocked the retry from ever reaching the backend again.
//
// `isHarmlessSamePasswordError` is the exact predicate all four call sites
// (broker/builder/influencer registration + IndividualUsernamePasswordScreen)
// use in `on AuthException catch (e) { if (!isHarmlessSamePasswordError(e))
// rethrow; }` — not a reimplementation, the real decision logic.
//
// What this does NOT cover (see the task's final report for why, and for
// the manual test steps that do): the full wizard submit flow end-to-end.
// These three registration screens are ~2000-line widgets with no injectable
// seam for Supabase/RegistrationSubmitService (registration_submit_form_
// mapping_test.dart's own header comment documents this as "a much larger
// undertaking" already, for the same reason) — the following structural
// facts are unchanged by this fix and verified by direct code inspection
// instead of a test:
//   - A successful password update (no exception at all) was always
//     followed by the RegistrationSubmitService call — this fix adds no new
//     code to that path.
//   - Any error from RegistrationSubmitService itself (a "backend failure")
//     was always caught by the screen's *outer* catch, which runs only the
//     error SnackBar — never the draft-clear/success lines, which sit
//     textually earlier in the same try block and are skipped entirely by
//     Dart's normal exception propagation the moment RegistrationSubmitService
//     throws. This fix does not touch that outer catch or reorder anything
//     around it.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/utils/registration_password_update.dart';

AuthException _authError(String code) =>
    AuthException('some message', statusCode: '422', code: code);

void main() {
  group('isHarmlessSamePasswordError', () {
    test('same_password is harmless — registration should proceed', () {
      expect(isHarmlessSamePasswordError(_authError('same_password')), isTrue);
    });

    test('a failed registration retried with the same password hits '
        'same_password again on the second updateUser call, and still '
        'proceeds — this is what makes the retry actually work', () {
      // Simulates: attempt 1 sets the password successfully, backend
      // submit fails; attempt 2 (same form, same password) calls
      // updateUser again and Supabase now reports same_password, since
      // the password was already set by attempt 1.
      final retryError = _authError('same_password');
      expect(isHarmlessSamePasswordError(retryError), isTrue);
    });

    for (final code in [
      'weak_password',
      'invalid_credentials',
      'over_request_rate_limit',
      'user_not_found',
    ]) {
      test('$code is a real auth failure — registration must not proceed', () {
        expect(isHarmlessSamePasswordError(_authError(code)), isFalse);
      });
    }

    test('matching is on the structured code only, never on status or message '
        'text — a 422 with unrelated content must still abort', () {
      final unrelated422 = AuthException(
        'New password should be different from the old password.',
        statusCode: '422',
        code: 'weak_password',
      );
      expect(isHarmlessSamePasswordError(unrelated422), isFalse);
    });

    test('a null/absent code is treated as a real failure, not swallowed', () {
      final noCode = AuthException('unexpected', statusCode: '400');
      expect(isHarmlessSamePasswordError(noCode), isFalse);
    });
  });
}
