/// Canonical identity-verification status for the signed-in user, exactly as
/// returned by the authenticated `verify-identifier` Edge Function's
/// `status` action (and optionally echoed by its `verify` action). See
/// `docs/PropCID_Flutter_Auth_Implementation_Plan.md` section 5.
///
/// This is the server's word on what's verified — never derived from a
/// locally persisted flag or from the mere presence of a value in a draft or
/// profile field.
class IdentityStatus {
  const IdentityStatus({
    required this.email,
    required this.emailVerified,
    required this.phone,
    required this.phoneVerified,
  });

  final String? email;
  final bool emailVerified;
  final String? phone;
  final bool phoneVerified;

  /// Parses the exact `{email, email_verified, phone, phone_verified}`
  /// shape. Throws [FormatException] on anything else — malformed server
  /// data must never be silently treated as "nothing verified", since that
  /// could hide a real verified identifier and prompt a redundant OTP.
  factory IdentityStatus.fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    final emailVerified = json['email_verified'];
    final phone = json['phone'];
    final phoneVerified = json['phone_verified'];
    if (email is! String? ||
        phone is! String? ||
        emailVerified is! bool ||
        phoneVerified is! bool) {
      throw const FormatException('Malformed identity status payload.');
    }
    return IdentityStatus(
      email: email,
      emailVerified: emailVerified,
      phone: phone,
      phoneVerified: phoneVerified,
    );
  }

  bool get bothVerified => emailVerified && phoneVerified;
}
