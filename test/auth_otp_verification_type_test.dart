// Phase 6 — OTP verification_type contract.
//
// `send-otp`'s `verify`/`create_user` actions return `verification_type`,
// GoTrue's own classification of the token they just issued: `"signup"`
// for a brand-new/unconfirmed user, `"magiclink"` once the user is already
// confirmed (see that function's own header comment). `AuthService
// .verifyOtp` previously called `supabase.auth.verifyOTP` with a hardcoded
// `OtpType.magiclink` regardless of which one the backend actually
// returned — which the backend's own comment warns fails with a misleading
// `otp_expired` for a brand-new signup, since GoTrue issued a `signup`
// token for that case, not a `magiclink` one.
//
// `AuthService.otpTypeFromVerificationType` is the pure mapping pulled out
// for exactly this reason: it's exercised here directly, with no Supabase
// call, auth flow, or network involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/services/auth_service.dart';

void main() {
  group('AuthService.otpTypeFromVerificationType', () {
    test('"signup" maps to OtpType.signup — a brand-new, unconfirmed user', () {
      expect(AuthService.otpTypeFromVerificationType('signup'), OtpType.signup);
    });

    test(
      '"magiclink" maps to OtpType.magiclink — an already-confirmed user',
      () {
        expect(
          AuthService.otpTypeFromVerificationType('magiclink'),
          OtpType.magiclink,
        );
      },
    );

    test('a missing verification_type falls back to magiclink — the '
        'pre-this-fix behaviour, for an older send-otp deployment', () {
      expect(AuthService.otpTypeFromVerificationType(null), OtpType.magiclink);
    });

    test('an unrecognised value also falls back to magiclink, not a crash', () {
      // send-otp's own header comment lists exactly two literal values —
      // this only guards against a future third value being introduced
      // without this mapping being updated to match.
      expect(
        AuthService.otpTypeFromVerificationType('something_else'),
        OtpType.magiclink,
      );
    });
  });
}
