/// A builder project as it appears inside a chat: the card rendered for a
/// received `project_share` message.
///
/// Deliberately not the app-wide `ProjectModel` — a chat bubble only needs
/// the few columns the portal's `ProjectShareMessage` shows (title,
/// description, location), the same reason `property_share`/`reel_share`
/// use [SharedPropertyPreview]/[SharedReelPreview].
class SharedProjectPreview {
  final String id;
  final String title;
  final String? description;
  final String? location;

  const SharedProjectPreview({
    required this.id,
    required this.title,
    this.description,
    this.location,
  });
}
