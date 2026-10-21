class NearbyPlace {
  final String name;
  final String type;
  final String distance;
  final String duration;
  final double latitude;
  final double longitude;

  NearbyPlace({
    required this.name,
    required this.type,
    required this.distance,
    required this.duration,
    required this.latitude,
    required this.longitude,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> json, String placeType) {
    return NearbyPlace(
      name: json["name"] ?? "",
      type: placeType,
      distance: "",
      duration: "",
      latitude: json["geometry"]["location"]["lat"].toDouble(),
      longitude: json["geometry"]["location"]["lng"].toDouble(),
    );
  }
}
