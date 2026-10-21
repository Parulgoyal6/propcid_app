/// A property as it appears inside a chat: the picker's search results, and
/// the rich card rendered for a received `property_share` message.
///
/// Deliberately not the app-wide `PropertyModel` — that parser expects
/// columns (beds/baths/amenities/etc.) the `properties_public` view this is
/// sourced from doesn't carry. The portal's own `SharePropertyModal.tsx` hits
/// exactly the same limitation ("properties_public doesn't carry every field
/// the app's Property type has") and defines its own narrow shape rather
/// than forcing the full type — this mirrors that choice on mobile.
class SharedPropertyPreview {
  final String id;
  final String title;
  final String? price;
  final String? location;
  final String? imageUrl;

  const SharedPropertyPreview({
    required this.id,
    required this.title,
    this.price,
    this.location,
    this.imageUrl,
  });

  factory SharedPropertyPreview.fromSupabase(Map<String, dynamic> json) {
    final media = json['media_urls'];
    final firstImage = media is List && media.isNotEmpty
        ? media.first?.toString()
        : null;

    return SharedPropertyPreview(
      id: json['id']?.toString() ?? '',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'Untitled property',
      price: json['price']?.toString(),
      location: json['location'] as String?,
      imageUrl: firstImage,
    );
  }
}
