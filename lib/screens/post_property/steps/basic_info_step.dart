import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/post_property_provider.dart';
import '../../../services/geocoding_service.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/location_picker_map.dart';
import '../listing_constants.dart';
import '../portal_kit.dart';
import '../portal_theme.dart';
import '../widgets/project_tag_selector.dart';

/// Step 2 — reproduction of the portal's `BasicInfoStep.tsx`.
///
/// Render order, copy, placeholders, label icons and required markers are taken
/// from source. The portal branches on all 15 category x listingType
/// combinations, but every branch for a given category renders the same tree —
/// listing type does not vary this step — so the category switch below is the
/// whole of that logic.
///
/// The portal's Google Maps picker (left third of the location grid) is
/// reproduced via [LocationPickerMap] — the same map/reverse-geocoding widget
/// already used by the builder/broker/influencer registration wizards. Tapping
/// it fills address/city/state/pincode/landmark and the provider's
/// latitude/longitude, exactly like `GoogleLocationPicker`'s
/// `onLocationSelect`. The Property Address field itself uses
/// [AddressAutocompleteField] — the same type-ahead widget those wizards use
/// — so typing an address surfaces suggestions the same way selecting a
/// suggestion or tapping the map both resolve through [_onLocationSelected].
class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({super.key});

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _pgPropertyName;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _stateField;
  late final TextEditingController _pincode;
  late final TextEditingController _landmark;

  /// True while [_onLocationSelected] is writing [_address]'s text itself
  /// (a resolved map tap or autocomplete pick) — [_onAddressChanged] must
  /// not mistake that programmatic write for the user editing the field, or
  /// it would clear the very coordinates that same call is about to set.
  bool _suppressCoordClear = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<PostPropertyProvider>();
    _title = TextEditingController(text: p.title);
    _description = TextEditingController(text: p.description);
    _pgPropertyName = TextEditingController(text: p.text('pgPropertyName'));
    _address = TextEditingController(text: p.location);
    // AddressAutocompleteField has no plain onChanged of its own (only
    // onPlaceSelected, fired when a suggestion is tapped) — without this,
    // typing a full address and never tapping a suggestion left the provider's
    // location empty, same as not typing anything at all.
    _address.addListener(_onAddressChanged);
    _city = TextEditingController(text: p.city);
    _stateField = TextEditingController(text: p.state);
    _pincode = TextEditingController(text: p.pincode);
    _landmark = TextEditingController(text: p.landmark);
  }

  @override
  void dispose() {
    _address.removeListener(_onAddressChanged);
    for (final c in [
      _title,
      _description,
      _pgPropertyName,
      _address,
      _city,
      _stateField,
      _pincode,
      _landmark,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  PostPropertyProvider get _p => context.read<PostPropertyProvider>();

  /// `formData.propertyType` as the portal spells it.
  static String _portalType(PropertyCategory? c) => switch (c) {
    PropertyCategory.land => 'land',
    PropertyCategory.residential => 'residential',
    PropertyCategory.commercial => 'commercial',
    PropertyCategory.pg => 'pg/Co-living',
    PropertyCategory.other => 'others',
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final type = _portalType(provider.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortalStepHeader(
          icon: 'file-text',
          title: 'Basic Information',
          subtitle: 'Essential details about your property',
          // badge2 (propertyType) renders before badge (listingType).
          badge2: type.isEmpty ? null : type,
          badge: provider.listingIntent?.name,
        ),

        // The step's white card: border-orange-100/70, shadow-sm,
        // rounded-2xl, p-4.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PortalTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PortalTheme.headerBorder),
            boxShadow: PortalTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Category block (space-y-4) ───────────────────────────
              // The portal's `grid-cols-1 md:grid-cols-2` (3 for commercial)
              // is a single column at mobile width, so these stack in the
              // portal's own source order.
              _headline(provider),
              const SizedBox(height: 16),

              if (provider.category == PropertyCategory.land) ...[
                _landType(provider),
                const SizedBox(height: 16),
              ] else if (provider.category == PropertyCategory.residential) ...[
                _residentialSubType(provider),
                const SizedBox(height: 16),
              ] else if (provider.category == PropertyCategory.commercial) ...[
                _commercialSubType(provider),
                const SizedBox(height: 16),
                _furnishingType(provider),
                const SizedBox(height: 16),
              ] else if (provider.category == PropertyCategory.pg) ...[
                ..._pgFields(provider),
              ],

              // 'others' adds nothing between Headline and Description.
              _descriptionBlock(provider),

              // LocationDetails carries `mt-4` in the portal.
              const SizedBox(height: 16),
              _locationDetails(),

              // space-y-3 between the category block and the project tag.
              const SizedBox(height: 12),
              _projectTag(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Headline ────────────────────────────────────────────────────────────

  Widget _headline(PostPropertyProvider p) {
    final placeholder = switch (p.category) {
      PropertyCategory.land => 'e.g., 2 Acre Agricultural Land in Green Valley',
      PropertyCategory.commercial =>
        'e.g., Premium Office Space in Business District',
      PropertyCategory.pg => 'e.g., Luxury Boys PG near University',
      _ => 'e.g., Modern 3BHK Apartment in Downtown',
    };

    return PortalField(
      label: 'Property Headline',
      required: true,
      child: PortalTextField(
        controller: _title,
        hint: placeholder,
        prefix: const PortalIconTint('type', color: PortalTheme.iconBlue),
        onChanged: (v) => _p.setTitle(v),
      ),
    );
  }

  // ── Description ─────────────────────────────────────────────────────────

  Widget _descriptionBlock(PostPropertyProvider p) {
    final placeholder = switch (p.category) {
      PropertyCategory.land =>
        'Describe the land - soil type, water availability, road connectivity, nearby facilities...',
      PropertyCategory.commercial =>
        'Describe the commercial space - floor area, parking, facilities, foot traffic...',
      PropertyCategory.residential =>
        'Describe the residential space - floor area, parking, facilities, foot traffic...',
      PropertyCategory.pg =>
        'Describe the PG/Co-living space - environment, nearby facilities, special amenities...',
      PropertyCategory.other =>
        'Describe the other property - floor area, parking, facilities, foot traffic...',
      null => '',
    };

    return PortalField(
      label: 'Property Description',
      required: true,
      child: PortalTextField(
        controller: _description,
        hint: placeholder,
        maxLines: 2, // rows={2}
        prefix: const PortalIconTint(
          'align-left',
          color: PortalTheme.iconPrimary,
        ),
        onChanged: (v) => _p.setDescription(v),
      ),
    );
  }

  // ── Land ────────────────────────────────────────────────────────────────

  Widget _landType(PostPropertyProvider p) {
    final subtype = p.text('landSubtype');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortalLabelledSelect(
          label: 'Subtype',
          required: true,
          icon: 'layers',
          iconColor: PortalTheme.iconPrimary, // was text-orange-500
          value: subtype,
          placeholder: 'Select subtype',
          options: kLandSubtypes,
          onChanged: (v) {
            // The portal clears landType whenever the subtype changes.
            _p.setText('landSubtype', v);
            _p.setText('landType', '');
          },
        ),
        if (subtype == 'land') ...[
          const SizedBox(height: 8), // mt-2
          PortalField(
            label: 'Land Use Type',
            required: true,
            child: PortalSelect(
              value: p.text('landType'),
              placeholder: 'Select Land Use Type',
              options: kLandTypeOptions,
              onChanged: (v) => _p.setText('landType', v),
            ),
          ),
        ],
        if (subtype == 'plot') ...[
          const SizedBox(height: 8),
          PortalField(
            label: 'Plot Type',
            required: true,
            child: PortalSelect(
              value: p.text('landType'),
              placeholder: 'Select Plot Type',
              options: kPlotTypeOptions,
              onChanged: (v) => _p.setText('landType', v),
            ),
          ),
        ],
      ],
    );
  }

  // ── Residential ─────────────────────────────────────────────────────────

  Widget _residentialSubType(PostPropertyProvider p) => PortalLabelledSelect(
    label: 'Property Type',
    required: true,
    icon: 'home',
    iconColor: PortalTheme.iconGreen, // text-green-500
    value: p.residentialSubType,
    placeholder: 'Select property type',
    groups: [for (final g in kResidentialSubTypeGroups) (g.label, g.options)],
    onChanged: (v) => _p.setResidentialSubType(v),
  );

  // ── Commercial ──────────────────────────────────────────────────────────

  /// Verbatim from the inline array in `CommercialSubType`.
  static const List<String> _commercialSubTypes = [
    'Office Space',
    'Shop',
    'Showroom',
    'Co-working Space',
    'Warehouse',
    'Godown',
    'Factory',
    'Industrial Shed',
    'Business Center',
    'Retail Space',
    'Food Court Space',
    'Hotel',
    'Restaurant Space',
    'Commercial Building',
  ];

  Widget _commercialSubType(PostPropertyProvider p) => PortalLabelledSelect(
    label: 'Commercial Property Type',
    required: true,
    icon: 'building-2',
    iconColor: PortalTheme.iconIndigo, // text-indigo-500
    value: p.text('commercialSubType'),
    placeholder: 'Select property type',
    options: _commercialSubTypes,
    onChanged: (v) {
      // The portal writes BOTH keys from this one select.
      _p.setText('commercialSubType', v);
      _p.setText('commercialType', v);
    },
  );

  Widget _furnishingType(PostPropertyProvider p) => PortalLabelledSelect(
    label: 'Furnishing Type',
    required: true,
    icon: 'home',
    iconColor: PortalTheme.success, // text-emerald-500
    value: p.furnishingType,
    placeholder: 'Select furnishing type',
    options: const ['Raw', 'Semi-Furnished', 'Fully-Furnished'],
    onChanged: (v) => _p.setFurnishingType(v),
  );

  // ── PG ──────────────────────────────────────────────────────────────────

  List<Widget> _pgFields(PostPropertyProvider p) => [
    PortalLabelledSelect(
      label: 'Property Type',
      required: true,
      icon: 'bed-double',
      iconColor: PortalTheme.iconRed, // text-pink-500
      value: p.text('pgPropertyType'),
      placeholder: 'Select property type',
      options: kPgPropertyTypes,
      onChanged: (v) => _p.setText('pgPropertyType', v),
    ),
    const SizedBox(height: 16),
    PortalLabelledSelect(
      label: 'Building Type',
      required: true,
      icon: 'building',
      iconColor: PortalTheme.iconTeal, // text-teal-500
      value: p.text('buildingType'),
      placeholder: 'Select building type',
      options: kBuildingTypeOptions,
      onChanged: (v) => _p.setText('buildingType', v),
    ),
    const SizedBox(height: 16),
    PortalField(
      label: 'PG / Property Name',
      required: true,
      child: PortalTextField(
        controller: _pgPropertyName,
        hint: 'e.g., Zolo Stays, Stanza Living...',
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
        ],
        onChanged: (v) => _p.setText('pgPropertyName', v),
      ),
    ),
    const SizedBox(height: 16),
    PortalLabelledSelect(
      label: 'Property Status',
      required: true,
      icon: 'circle-dot',
      iconColor: PortalTheme.iconTeal, // text-cyan-500
      value: p.text('propertyStatus'),
      placeholder: 'Select status',
      options: const ['Available', 'Occupied', 'Immediate Move-In'],
      onChanged: (v) => _p.setText('propertyStatus', v),
    ),
    const SizedBox(height: 16),
  ];

  // ── Location Details ────────────────────────────────────────────────────

  /// Mirrors `handleLocationSelect` in the portal's `BasicInfoStep.tsx`: keep
  /// the existing value when the geocode result didn't resolve that field.
  ///
  /// [fromAutocomplete] distinguishes the two ways this fires:
  ///   * a map tap/drag has no pre-existing address text to protect, so the
  ///     address field is filled from the geocode result — preferring the
  ///     complete [GeocodedAddress.formattedAddress] over the narrower
  ///     street-only [GeocodedAddress.addressLine1] (route + street number
  ///     only, or a lossy first-comma-segment fallback), so a tapped pin
  ///     reads as a real address, not just a street name.
  ///   * an autocomplete pick already wrote the exact suggestion the user
  ///     chose into [_address] before this fires (`AddressAutocompleteField
  ///     ._selectPrediction`) — overwriting it with `addressLine1` here used
  ///     to silently shorten whatever full description the user had just
  ///     picked, so that text is left alone in this case.
  void _onLocationSelected(
    double lat,
    double lng,
    GeocodedAddress? address, {
    bool fromAutocomplete = false,
  }) {
    _suppressCoordClear = true;
    setState(() {
      if (!fromAutocomplete) {
        final full = address?.formattedAddress?.trim();
        final line1 = address?.addressLine1?.trim();
        final text = (full != null && full.isNotEmpty) ? full : line1;
        if (text != null && text.isNotEmpty) _address.text = text;
      }
      if ((address?.city ?? '').isNotEmpty) _city.text = address!.city!;
      if ((address?.state ?? '').isNotEmpty) {
        _stateField.text = address!.state!;
      }
      if ((address?.pincode ?? '').isNotEmpty) {
        _pincode.text = address!.pincode!;
      }
      if ((address?.landmark ?? '').isNotEmpty) {
        _landmark.text = address!.landmark!;
      }
    });
    _p.setLocation(_address.text);
    _p.setCity(_city.text);
    _p.setState(_stateField.text);
    _p.setPincode(_pincode.text);
    _p.setLandmark(_landmark.text);
    _p.setLatitude(lat);
    _p.setLongitude(lng);
    _suppressCoordClear = false;
  }

  /// Forgets a previously-resolved pin the moment the address text no
  /// longer matches it — a manual edit (typing over a selection, or
  /// deleting part of it) with no accompanying map tap or autocomplete pick
  /// means whatever coordinates were set for the OLD text can no longer be
  /// trusted to describe the new one. Guarded by [_suppressCoordClear] so
  /// [_onLocationSelected]'s own programmatic text writes — the normal,
  /// successful path — never trip this.
  void _onAddressChanged() {
    _p.setLocation(_address.text);
    if (_suppressCoordClear) return;
    if (_p.latitude != null || _p.longitude != null) {
      _p.setLatitude(null);
      _p.setLongitude(null);
    }
  }

  /// A tapped suggestion's place-details lookup failed — `_address` already
  /// shows that suggestion's full text (written before the lookup even
  /// started), but no coordinates were ever resolved for it. Clearing here
  /// keeps a stale old pin from looking like it still describes whatever
  /// text is now showing, and tells the user plainly why nothing moved.
  void _onPlaceSelectionFailed() {
    _suppressCoordClear = false;
    if (_p.latitude != null || _p.longitude != null) {
      _p.setLatitude(null);
      _p.setLongitude(null);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't resolve that address. Please pick a suggestion again "
          'or tap the map to set the location.',
        ),
      ),
    );
  }

  Widget _locationDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PortalSectionDivider(
        icon: 'map-pin',
        title: 'Location Details',
        iconBg: PortalTheme.accentSurface, // bg-blue-100
        iconColor: PortalTheme.iconBlue, // text-blue-600
      ),
      // Reproduction of the portal's Google Maps picker — tap to drop a
      // pin, reverse-geocoded into the fields below.
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LocationPickerMap(
          initialLat: _p.latitude,
          initialLng: _p.longitude,
          onLocationSelected: _onLocationSelected,
        ),
      ),
      const SizedBox(height: 16),
      PortalField(
        label: 'Property Address',
        required: true,
        child: AddressAutocompleteField(
          controller: _address,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: PortalTheme.cardSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            hintText:
                'Type to search property address (Google Maps auto-complete)...',
            hintStyle: PortalTheme.inputText.copyWith(
              color: AppColors.textHint,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: PortalTheme.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: PortalTheme.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          maxLines: 2,
          onSelectionStart: () => _suppressCoordClear = true,
          onPlaceSelected: (address, lat, lng) => _onLocationSelected(
            lat,
            lng,
            address,
            fromAutocomplete: true,
          ),
          onPlaceSelectionFailed: _onPlaceSelectionFailed,
        ),
      ),
      const SizedBox(height: 16),
      PortalLabelledField(
        label: 'City',
        required: true,
        icon: 'map',
        iconColor: PortalTheme.success, // text-emerald-500
        child: PortalTextField(
          controller: _city,
          hint: 'Type city name',
          onChanged: (v) => _p.setCity(v),
        ),
      ),
      const SizedBox(height: 16),
      PortalLabelledField(
        label: 'State',
        required: true,
        icon: 'globe',
        iconColor: PortalTheme.iconBlue, // text-blue-500
        child: PortalTextField(
          controller: _stateField,
          hint: 'State',
          onChanged: (v) => _p.setState(v),
        ),
      ),
      const SizedBox(height: 16),
      PortalLabelledField(
        label: 'Pincode',
        required: true,
        icon: 'hash',
        iconColor: PortalTheme.iconMuted, // text-slate-500
        child: PortalTextField(
          controller: _pincode,
          hint: 'Pincode',
          keyboardType: TextInputType.number,
          onChanged: (v) => _p.setPincode(v),
        ),
      ),
      const SizedBox(height: 16),
      PortalLabelledField(
        label: 'Landmark',
        // Portal's own label has no asterisk (BasicInfoStep.tsx:648-651) and
        // its validation rule table has no 'landmark' entry at all
        // (propertyListingRules.ts) — Landmark is genuinely optional there.
        // `required: true` here was a Flutter-only mismatch: it showed a
        // required marker with nothing behind it (no rule in
        // listing_validation_rules.dart ever blocked Continue on a blank
        // Landmark), so the field claimed to be mandatory while never
        // actually being enforced as one.
        icon: 'landmark',
        iconColor: PortalTheme.iconRed, // text-rose-500
        child: PortalTextField(
          controller: _landmark,
          hint: 'Famous landmark nearby',
          onChanged: (v) => _p.setLandmark(v),
        ),
      ),
    ],
  );

  // ── Builder Project tag ─────────────────────────────────────────────────

  Widget _projectTag() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PortalSectionDivider(
        icon: 'building-2',
        title: 'Builder Project (Optional)',
      ),
      ProjectTagSelector(),
    ],
  );
}
