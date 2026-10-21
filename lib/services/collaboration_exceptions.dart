/// A collaboration action was refused by the backend for a reason the user
/// should be told about — the RPCs and Edge Functions behind
/// [CollaborationService] already return user-appropriate messages (e.g.
/// "Only the client can pay for this collaboration."), so this simply
/// preserves that text rather than replacing it with a generic one.
class CollaborationException implements Exception {
  final String message;
  const CollaborationException(this.message);
  @override
  String toString() => message;
}

/// Client-side validation failed before any network call was made (wrong
/// mime type, too large, wrong duration).
class CollabMediaValidationError implements Exception {
  final String message;
  const CollabMediaValidationError(this.message);
  @override
  String toString() => message;
}
