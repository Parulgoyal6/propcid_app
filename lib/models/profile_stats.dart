/// The three headline counts on the Profile screen's stats row.
///
/// A plain value object, not a table-backed model (blueprint §16.4): each
/// field comes from a different table via its own thin service.
class ProfileStats {
  /// Accepted network connections — `builder_networks`.
  final int followers;

  /// Ratings received — `user_ratings`.
  final int reviews;

  /// Unique profile viewers — `profile_views`.
  final int profileViews;

  /// Mean rating, one decimal. Not shown on the tiles but derived from the
  /// same query as [reviews], so it is carried here rather than re-fetched.
  final double averageRating;

  const ProfileStats({
    this.followers = 0,
    this.reviews = 0,
    this.profileViews = 0,
    this.averageRating = 0,
  });

  static const ProfileStats zero = ProfileStats();
}
