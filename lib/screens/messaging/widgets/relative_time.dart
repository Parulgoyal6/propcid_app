/// Compact "2m / 15m / 1h / 3h / 5h" style timestamps for the message lists,
/// matching the prototype's chat rows.
///
/// Formatting only — no locale package is involved, so this adds no
/// dependency.
String formatRelativeTime(DateTime? time) {
  if (time == null) return '';

  final now = DateTime.now();
  final diff = now.difference(time.toLocal());

  if (diff.isNegative) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';

  final weeks = diff.inDays ~/ 7;
  if (weeks < 5) return '${weeks}w';

  final months = diff.inDays ~/ 30;
  if (months < 12) return '${months}mo';

  return '${diff.inDays ~/ 365}y';
}

/// Clock time shown under a chat bubble, e.g. "10:02 AM".
String formatClockTime(DateTime? time) {
  if (time == null) return '';

  final local = time.toLocal();
  final hour24 = local.hour;
  final suffix = hour24 < 12 ? 'AM' : 'PM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');

  return '$hour12:$minute $suffix';
}
