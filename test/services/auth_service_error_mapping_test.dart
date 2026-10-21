import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/services/auth_service.dart';
import 'package:propcid_app/services/edge_functions_service.dart';

/// Exercises `AuthService.mapEdgeFunctionFailure` — the mapping that keeps
/// the Flutter login error copy in parity with the portal's `username-auth`
/// edge function contract (`propcid/supabase/functions/username-auth/index.ts`).
/// A `static` method, so no `AuthService` instance (and therefore no live
/// Supabase client) needs to exist for this test.
void main() {
  group('AuthService.mapEdgeFunctionFailure', () {
    test(
      'unknown username and wrong password produce the identical generic message',
      () {
        // The edge function itself already collapses both cases into one
        // 401 body — this just confirms the client does not re-introduce a
        // distinction (which would reopen the enumeration the endpoint exists
        // to close).
        const unknownUsername = EdgeFunctionFailure(
          status: 401,
          message: 'Invalid username or password.',
        );
        const wrongPassword = EdgeFunctionFailure(
          status: 401,
          message: 'Invalid username or password.',
        );

        expect(
          AuthService.mapEdgeFunctionFailure(unknownUsername),
          AuthService.mapEdgeFunctionFailure(wrongPassword),
        );
        expect(
          AuthService.mapEdgeFunctionFailure(unknownUsername),
          'Invalid username or password.',
        );
      },
    );

    test('email_not_confirmed gets the specific verification message', () {
      const failure = EdgeFunctionFailure(
        status: 403,
        code: 'email_not_confirmed',
        message: 'email_not_confirmed',
      );

      expect(
        AuthService.mapEdgeFunctionFailure(failure),
        'Please verify your email before signing in.',
      );
    });

    test('HTTP 429 produces a rate-limit message', () {
      const failure = EdgeFunctionFailure(
        status: 429,
        message: 'Too many attempts. Please try again later.',
      );

      expect(
        AuthService.mapEdgeFunctionFailure(failure),
        'Too many attempts. Please try again later.',
      );
    });

    test('HTTP 429 with an empty body still produces a rate-limit message', () {
      const failure = EdgeFunctionFailure(status: 429, message: '');

      expect(
        AuthService.mapEdgeFunctionFailure(failure),
        'Too many attempts. Please try again later.',
      );
    });

    test(
      'HTTP 503 / configuration failure produces a service-unavailable message',
      () {
        const failure = EdgeFunctionFailure(
          status: 503,
          message: 'Service temporarily unavailable. Please try again shortly.',
        );

        expect(
          AuthService.mapEdgeFunctionFailure(failure),
          'Service temporarily unavailable. Please try again shortly.',
        );
      },
    );

    test(
      'a network failure (no status) falls back to the generic network message',
      () {
        const failure = EdgeFunctionFailure(
          message: 'A network error occurred. Please try again.',
        );

        expect(
          AuthService.mapEdgeFunctionFailure(failure),
          'A network error occurred. Please try again.',
        );
      },
    );
  });
}
