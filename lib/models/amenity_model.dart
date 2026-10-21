class AmenityModel {
  final String id;
  final String name;
  final String icon;
  final String color;

  AmenityModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  factory AmenityModel.fromJson(Map<String, dynamic> json) {
    return AmenityModel(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      color: json['color'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'icon': icon, 'color': color};
  }
}

class NearbyPlaceModel {
  final String id;
  final String name;
  final String type;
  final String distance;
  final String duration;
  final String icon;
  final String color;

  NearbyPlaceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.distance,
    required this.duration,
    required this.icon,
    required this.color,
  });

  factory NearbyPlaceModel.fromJson(Map<String, dynamic> json) {
    return NearbyPlaceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      distance: json['distance'] as String,
      duration: json['duration'] as String,
      icon: json['icon'] as String,
      color: json['color'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'distance': distance,
      'duration': duration,
      'icon': icon,
      'color': color,
    };
  }
}
