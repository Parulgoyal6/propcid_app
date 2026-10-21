// widgets/location_picker_map.dart
//
// Mirrors `GoogleLocationPicker.tsx` with `hideSearch={true}` — the mode
// every registration wizard actually uses (BuilderRegistration.tsx:1617,
// BrokerRegistration.tsx and InfluencerRegistration.tsx pass the same prop).
// Tapping the map drops a pin and reverse-geocodes it via
// [GeocodingService], exactly like the portal's `performGeocode` +
// `updateMarker`. The search bar the portal shows when `hideSearch` is false
// is not built here, since no caller needs it.
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/geocoding_service.dart';

/// What [LocationPickerMap] should do about its pin/camera when
/// `initialLat`/`initialLng` change out from under it, decided as a pure
/// function so this branching is directly unit-testable without a real
/// `GoogleMap` platform view (not available in a widget test here).
///
///   * [moveTo] — the parent resolved a new, different, valid location
///     (autocomplete, a restored draft, edit mode opening) — move the pin
///     there and animate the camera to it.
///   * [clear] — the parent explicitly cleared a location this widget was
///     still showing (e.g. the address was hand-edited after a pin was
///     dropped) — drop the pin.
///   * [none] — nothing to do: unchanged coordinates, a widget rebuild with
///     no real prop change, or a clear that doesn't apply (the user already
///     moved past the old pin via their own tap/drag, so there is nothing
///     of the parent's left to undo).
///
/// Never a signal to call `onLocationSelected` — that callback means "the
/// user picked a location," and a prop change is the opposite direction:
/// the parent telling this widget about a location, not the other way
/// round. Returning only this enum (never invoking a callback) is what
/// makes a feedback loop structurally impossible here, not just unlikely.
enum LocationSyncAction { none, moveTo, clear }

LocationSyncAction decideLocationSync({
  required double? oldLat,
  required double? oldLng,
  required double? newLat,
  required double? newLng,
  required double? currentSelectedLat,
  required double? currentSelectedLng,
}) {
  final hasNew = newLat != null && newLng != null;
  final hadOld = oldLat != null && oldLng != null;

  if (!hasNew) {
    final selectionStillMatchesOld =
        hadOld && currentSelectedLat == oldLat && currentSelectedLng == oldLng;
    return selectionStillMatchesOld
        ? LocationSyncAction.clear
        : LocationSyncAction.none;
  }

  final unchanged = hadOld && oldLat == newLat && oldLng == newLng;
  return unchanged ? LocationSyncAction.none : LocationSyncAction.moveTo;
}

class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    this.initialLat,
    this.initialLng,
    required this.onLocationSelected,
  });

  final double? initialLat;
  final double? initialLng;

  /// Fires on every tap/drag, even when reverse geocoding fails — [address]
  /// is null in that case, matching the portal's `onLocationSelect(lat, lng)`
  /// fallback call when `performGeocode` catches an error.
  final void Function(double lat, double lng, GeocodedAddress? address)
  onLocationSelected;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  final _geocodingService = GeocodingService();
  GoogleMapController? _controller;
  LatLng? _selected;
  bool _geocoding = false;

  // GoogleLocationPicker.tsx:134 — Delhi, the same fallback centre when no
  // initial coordinates are supplied.
  static const LatLng _defaultCenter = LatLng(28.7041, 77.1025);

  // The portal's `GoogleLocationPicker` recentres on a resolved address
  // (e.g. picked from autocomplete after this map already mounted) — close
  // enough to "you just chose this" to be worth a deliberate zoom-in, not
  // just a marker move.
  static const double _selectedZoom = 15;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _selected = LatLng(widget.initialLat!, widget.initialLng!);
    }
  }

  /// Keeps the map in sync when the parent resolves (or clears) a location
  /// *after* this widget already mounted — e.g. autocomplete fills
  /// `initialLat`/`initialLng` once this screen's map picker is already on
  /// screen. `GoogleMap.initialCameraPosition` is only read once, at
  /// creation, so without this the pin/camera would otherwise never move
  /// for anything but a user's own tap/drag on the map itself.
  @override
  void didUpdateWidget(covariant LocationPickerMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final action = decideLocationSync(
      oldLat: oldWidget.initialLat,
      oldLng: oldWidget.initialLng,
      newLat: widget.initialLat,
      newLng: widget.initialLng,
      currentSelectedLat: _selected?.latitude,
      currentSelectedLng: _selected?.longitude,
    );

    switch (action) {
      case LocationSyncAction.none:
        return;
      case LocationSyncAction.clear:
        setState(() => _selected = null);
      case LocationSyncAction.moveTo:
        final newPoint = LatLng(widget.initialLat!, widget.initialLng!);
        // A tap/drag already updates `_selected` itself and calls
        // `onLocationSelected` directly — this path is only reached for a
        // prop change the PARENT made (autocomplete, a restored draft, edit
        // mode), so it must never call `onLocationSelected` back out, or a
        // parent that re-renders on every notify would loop. See
        // `decideLocationSync`'s own doc comment.
        setState(() => _selected = newPoint);
        _animateTo(newPoint);
    }
  }

  void _animateTo(LatLng point) {
    // The controller may not exist yet (prop changed before `onMapCreated`
    // fired) — `initState`/`build` already seed `_selected` from the latest
    // `initialLat`/`initialLng` in that case, so the map's own
    // `initialCameraPosition` opens in the right place without needing an
    // animated move.
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: _selectedZoom),
      ),
    );
  }

  Future<void> _handleTap(LatLng point) async {
    setState(() {
      _selected = point;
      _geocoding = true;
    });

    final address = await _geocodingService.reverseGeocode(
      point.latitude,
      point.longitude,
    );

    if (!mounted) return;
    setState(() => _geocoding = false);
    widget.onLocationSelected(point.latitude, point.longitude, address);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final center = _selected ?? _defaultCenter;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            GoogleMap(
              // Both listing wizards render this inside a
              // SingleChildScrollView, whose own vertical PanGestureRecognizer
              // otherwise wins the gesture arena against the map's — a drag
              // that should pan the map instead scrolls the page, and pinch
              // zoom doesn't register either. EagerGestureRecognizer claims
              // the gesture for the map immediately so panning/zooming work
              // as expected; tapping to drop a pin was never affected by this
              // (arena resolution for pans/scale, not taps).
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              initialCameraPosition: CameraPosition(
                target: center,
                zoom: _selected != null ? 15 : 6,
              ),
              onMapCreated: (controller) => _controller = controller,
              onTap: _handleTap,
              markers: _selected == null
                  ? const {}
                  : {
                      Marker(
                        markerId: const MarkerId('picked-location'),
                        position: _selected!,
                        draggable: true,
                        onDragEnd: _handleTap,
                      ),
                    },
              zoomControlsEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_geocoding)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.location_on, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _geocoding
                            ? 'Locating...'
                            : 'Tap on the map to select location',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
