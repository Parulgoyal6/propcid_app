/// A reel as it appears inside a chat: the rich card rendered for a received
/// `reel_share` message.
///
/// Deliberately not the app-wide `ReelModel` — that parser needs the joined
/// `profiles`/`properties` data `ReelsService.getReels()`'s full-feed query
/// produces, which would be a large, unnecessary fetch just to show a
/// thumbnail and title in a chat bubble (mirrors why `property_share` uses
/// [SharedPropertyPreview] instead of the app-wide `PropertyModel`). A reel
/// share's `reel_id` can point at either an uploaded reel
/// (`influencer_videos`) or a listing's own video played as a reel
/// (`properties`/`properties_public`) — see
/// `MessagingService.fetchSharedReels`, which resolves both sources into
/// this one small shape.
class SharedReelPreview {
  final String id;
  final String title;
  final String? thumbnailUrl;

  /// The uploader's display name - only filled by the in-chat reel picker
  /// ([MessagingService.searchReels]), where each result row shows it.
  final String? ownerName;

  const SharedReelPreview({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.ownerName,
  });
}
