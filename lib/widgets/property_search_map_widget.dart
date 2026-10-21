// widgets/property_search_map_widget.dart
//
// Multi-marker search-results map — the Flutter port of the website's
// GooglePropertyMap.tsx. One marker per property (no clustering, matching
// the website), a two-tap marker -> summary card -> detail flow (the card
// itself is rendered by the caller, see MapPropertySummaryCard), highlight
// circles around the selected property, and a fitBounds-then-zoom-clamp
// camera — all direct ports, not approximations.
//
// Kept fully separate from the existing single-marker PropertyMapWidget
// (different camera/interaction rules, used only on the detail screen for
// one static pin) — zero risk to that already-working screen.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/property_model.dart';

class PropertySearchMapWidget extends StatefulWidget {
  final List<PropertyModel> properties;
  final PropertyModel? selectedProperty;
  final ValueChanged<PropertyModel?> onMarkerTap;

  const PropertySearchMapWidget({
    super.key,
    required this.properties,
    required this.selectedProperty,
    required this.onMarkerTap,
  });

  @override
  State<PropertySearchMapWidget> createState() =>
      _PropertySearchMapWidgetState();
}

class _PropertySearchMapWidgetState extends State<PropertySearchMapWidget> {
  GoogleMapController? _controller;

  static const LatLng _indiaCenter = LatLng(20.5937, 78.9629);
  static const double _indiaZoom = 5;
  static const double _singlePropertyZoom = 14;
  static const double _maxAutoFitZoom = 15;

  List<PropertyModel> get _plottable => widget.properties
      .where((p) => p.latitude != null && p.longitude != null)
      .toList();

  @override
  void didUpdateWidget(covariant PropertySearchMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.properties != widget.properties) {
      _fitToProperties();
    } else if (oldWidget.selectedProperty?.id != widget.selectedProperty?.id &&
        widget.selectedProperty != null) {
      _panToSelected();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Set<Marker> _buildMarkers() {
    final String? selectedId = widget.selectedProperty?.id;
    return _plottable.map((p) {
      final bool isSelected = p.id == selectedId;
      return Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.latitude!, p.longitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isSelected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed,
        ),
        zIndex: isSelected ? 1000 : 1,
        onTap: () => widget.onMarkerTap(p),
      );
    }).toSet();
  }

  Set<Circle> _buildCircles() {
    final PropertyModel? selected = widget.selectedProperty;
    if (selected?.latitude == null || selected?.longitude == null) return {};

    final LatLng center = LatLng(selected!.latitude!, selected.longitude!);
    return {
      Circle(
        circleId: const CircleId('selected-inner'),
        center: center,
        radius: 800,
        fillColor: Colors.deepOrange.withOpacity(0.15),
        strokeColor: Colors.deepOrange.withOpacity(0.4),
        strokeWidth: 1,
      ),
      Circle(
        circleId: const CircleId('selected-outer'),
        center: center,
        radius: 2000,
        fillColor: Colors.transparent,
        strokeColor: Colors.deepOrange.withOpacity(0.3),
        strokeWidth: 1,
      ),
    };
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _fitToProperties() async {
    final controller = _controller;
    if (controller == null) return;
    final points = _plottable
        .map((p) => LatLng(p.latitude!, p.longitude!))
        .toList();

    if (points.isEmpty) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: _indiaCenter, zoom: _indiaZoom),
        ),
      );
      return;
    }
    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: _singlePropertyZoom),
        ),
      );
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsFor(points), 60),
    );
  }

  Future<void> _panToSelected() async {
    final controller = _controller;
    final selected = widget.selectedProperty;
    if (controller == null ||
        selected?.latitude == null ||
        selected?.longitude == null) {
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(selected!.latitude!, selected.longitude!),
          zoom: _singlePropertyZoom,
        ),
      ),
    );
  }

  /// Port of the website's addListenerOnce(map, "idle", clamp-to-15) — only
  /// matters right after an auto-fit, which can zoom in tighter than
  /// desired for a small/tight cluster of markers.
  Future<void> _onCameraIdle() async {
    final controller = _controller;
    if (controller == null) return;
    final zoom = await controller.getZoomLevel();
    if (zoom > _maxAutoFitZoom) {
      await controller.animateCamera(CameraUpdate.zoomTo(_maxAutoFitZoom));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: _indiaCenter,
        zoom: _indiaZoom,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        // Let the platform view finish mounting before animating the
        // camera — same pattern the existing PropertyMapWidget already uses.
        Future.delayed(const Duration(milliseconds: 200), _fitToProperties);
      },
      markers: _buildMarkers(),
      circles: _buildCircles(),
      onCameraIdle: _onCameraIdle,
      zoomControlsEnabled: true,
      myLocationButtonEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
    );
  }
}
