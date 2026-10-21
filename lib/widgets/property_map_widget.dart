import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// =============================================================================
// PropertyMapWidget
// Renders a rounded Google Map with a single marker for the property location.
// Public API is unchanged (latitude, longitude, title) so all existing call
// sites keep working — only the internal zoom level + camera behaviour improved.
// =============================================================================
class PropertyMapWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String title;

  const PropertyMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
  });

  @override
  State<PropertyMapWidget> createState() => _PropertyMapWidgetState();
}

class _PropertyMapWidgetState extends State<PropertyMapWidget> {
  GoogleMapController? _controller;

  // Slightly zoomed out starting point so the animateCamera call on load
  // has somewhere to travel to — gives the map a subtle "settle in" feel.
  static const double _initialZoom = 14.0;
  static const double _targetZoom = 16.0;

  /// The property screen can first paint with cached data and later
  /// replace it with the authoritative fetched row — if the coordinates
  /// differ, `markers` already rebuilds to the new position on its own
  /// (`build()` recomputes it from `widget.latitude`/`longitude` every
  /// time), but `GoogleMap.initialCameraPosition` is only read once, at
  /// creation, so the camera itself would otherwise stay put while the pin
  /// jumped out from under it.
  @override
  void didUpdateWidget(covariant PropertyMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude == widget.latitude &&
        oldWidget.longitude == widget.longitude) {
      return;
    }
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(widget.latitude, widget.longitude),
          zoom: _targetZoom,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng position = LatLng(widget.latitude, widget.longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 250,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: position,
            zoom: _initialZoom,
          ),
          onMapCreated: (GoogleMapController controller) {
            _controller = controller;
            // Subtle camera animation into the final zoom level once the
            // map has actually mounted, instead of snapping straight to 16.
            Future.delayed(const Duration(milliseconds: 200), () {
              _controller?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: position, zoom: _targetZoom),
                ),
              );
            });
          },
          markers: {
            Marker(
              markerId: const MarkerId('property'),
              position: position,
              infoWindow: InfoWindow(title: widget.title),
            ),
          },
          zoomControlsEnabled: true,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }
}
