// widgets/address_autocomplete_field.dart
//
// The office-address `TextField` with a type-ahead suggestions dropdown,
// mirroring the portal's `officeAddressAutocompleteRef` — a
// `google.maps.places.Autocomplete` attached directly to the office address
// `<Input>` (BuilderRegistration.tsx:1624-1626 and the equivalent in the
// broker/influencer wizards). Selecting a suggestion resolves it to
// coordinates + address components via [PlacesAutocompleteService], which
// the caller feeds into the same `onLocationSelected` handler the map picker
// already uses.
//
// Flutter's built-in `Autocomplete`/`RawAutocomplete` only supports a
// synchronous `optionsBuilder`, which can't drive a debounced network call.
// This widget is a small, self-contained debounce + `Overlay` dropdown
// instead — the standard pattern for network-backed autocomplete in Flutter.
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/geocoding_service.dart';
import '../services/places_autocomplete_service.dart';

class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.decoration,
    this.maxLines = 2,
    required this.onPlaceSelected,
    this.onSelectionStart,
    this.onPlaceSelectionFailed,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final int maxLines;

  /// Fires once a tapped suggestion's place details resolve.
  final void Function(GeocodedAddress address, double lat, double lng)
  onPlaceSelected;

  /// Fires synchronously the moment a suggestion is tapped, *before* its
  /// text is written into [controller] and before the place-details lookup
  /// starts. Optional — existing callers that don't pass it keep behaving
  /// exactly as before.
  ///
  /// A caller that clears stored coordinates whenever [controller]'s text
  /// changes (to stop an edited address from keeping an old pin) needs this:
  /// without it, there is no way to tell "the user is about to replace this
  /// text with a freshly-resolved selection" apart from "the user is typing
  /// a fresh, as-yet-unresolved edit" — both look identical as a plain
  /// controller-text-changed event. Pair with [onPlaceSelected] (resolved)
  /// or [onPlaceSelectionFailed] (not resolved) to know when that one
  /// selection attempt is over.
  final VoidCallback? onSelectionStart;

  /// Fires when a tapped suggestion's place-details lookup fails (network
  /// error, zero results) — [controller] already shows that suggestion's
  /// full text at this point (it's written before the lookup starts, same
  /// as before this field gained this callback), but no coordinates were
  /// ever resolved for it. A caller that tracks "do I still have a valid
  /// pin for what the text field currently shows" needs this signal: without
  /// it, a failed lookup left old, now-mismatched coordinates looking as
  /// valid as ever. Optional — existing callers that don't pass it see no
  /// behavior change (the text is still left as the selected description,
  /// same as before this field gained this callback).
  final VoidCallback? onPlaceSelectionFailed;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _service = PlacesAutocompleteService();
  final _layerLink = LayerLink();
  final _focusNode = FocusNode();
  // Groups the field and its dropdown into one `TapRegion` — see the
  // `TapRegion` note on `build()` for why this is required, not cosmetic.
  final Object _groupId = UniqueKey();
  OverlayEntry? _overlayEntry;
  List<PlacePrediction> _predictions = [];
  Timer? _debounce;
  bool _loading = false;
  int _requestId = 0;
  bool _suppressNextChange = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _removeOverlay();
    });
  }

  void _onTextChanged() {
    // Skip the fetch this listener would otherwise schedule for the text
    // `_selectPrediction` just wrote programmatically — without this, picking
    // a suggestion re-opens the dropdown moments later with matches for the
    // full description that was just selected.
    if (_suppressNextChange) {
      _suppressNextChange = false;
      return;
    }
    _debounce?.cancel();
    final text = widget.controller.text.trim();
    if (text.length < 3) {
      setState(() => _predictions = []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchPredictions(text),
    );
  }

  Future<void> _fetchPredictions(String input) async {
    final requestId = ++_requestId;
    setState(() => _loading = true);
    final results = await _service.autocomplete(input);
    // Drop stale responses from a request superseded by more typing.
    if (!mounted || requestId != _requestId) return;

    setState(() {
      _predictions = results;
      _loading = false;
    });

    if (results.isEmpty) {
      _removeOverlay();
    } else if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? MediaQuery.of(context).size.width;
    final height = box?.size.height ?? 56;
    final scheme = Theme.of(context).colorScheme;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, height + 4),
          child: TapRegion(
            groupId: _groupId,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: scheme.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _predictions.length,
                  itemBuilder: (context, i) {
                    final prediction = _predictions[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      title: Text(
                        prediction.description,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => _selectPrediction(prediction),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _selectPrediction(PlacePrediction prediction) async {
    widget.onSelectionStart?.call();
    _suppressNextChange = true;
    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.collapsed(
      offset: prediction.description.length,
    );
    setState(() => _predictions = []);
    _removeOverlay();
    _focusNode.unfocus();

    final details = await _service.placeDetails(prediction.placeId);
    if (!mounted) return;
    if (details == null) {
      widget.onPlaceSelectionFailed?.call();
      return;
    }
    widget.onPlaceSelected(
      details.address,
      details.latitude,
      details.longitude,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      // `TextField` unfocuses itself on ANY tap outside its own bounds by
      // default — including a tap on a suggestion in the separate `Overlay`
      // below, which tears the overlay down before the `ListTile`'s `onTap`
      // finishes registering, so selecting a suggestion silently did nothing.
      // Grouping the field and the overlay's `TapRegion` under the same
      // `groupId` makes a tap on either count as "inside," and disabling the
      // field's own default via `onTapOutside` hands control to this region
      // exclusively (its `onTapOutside` still fires for a genuine tap
      // elsewhere on the screen).
      child: TapRegion(
        groupId: _groupId,
        onTapOutside: (event) {
          _focusNode.unfocus();
          _removeOverlay();
        },
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLines: widget.maxLines,
          onTapOutside: (event) {},
          decoration: widget.decoration.copyWith(
            suffixIcon: _loading
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
