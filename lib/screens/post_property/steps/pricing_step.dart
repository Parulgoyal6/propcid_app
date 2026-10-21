import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/amount_in_words.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_area_units.dart';
import '../listing_constants.dart';

/// Step 7: pricing terms beyond the headline price already captured in Basic
/// Info — rate/deposit/maintenance/booking/lock-in, negotiability toggles and
/// brokerage (shared), plus Commercial investment/lease-term fields and
/// PG rent/sale/lease-specific fields. Mirrors the React PricingStep.
class PricingStep extends StatefulWidget {
  const PricingStep({super.key});

  @override
  State<PricingStep> createState() => _PricingStepState();
}

class _PricingStepState extends State<PricingStep> {
  /// Apartment subtype on a rent or lease listing — the combination React
  /// renders "Society charges" for.
  static bool _isApartmentRental(PostPropertyProvider p) =>
      p.category == PropertyCategory.residential &&
      kApartmentSubtypes.contains(p.residentialSubType ?? '') &&
      (p.listingIntent == ListingIntent.rent ||
          p.listingIntent == ListingIntent.lease);

  static const _lockInOptions = [
    'None',
    '3 Months',
    '6 Months',
    '1 Year',
    '2 Years',
  ];

  late final TextEditingController _priceController;
  late final TextEditingController _ratePerAreaController;
  late final TextEditingController _securityDepositController;
  late final TextEditingController _maintenanceController;
  late final TextEditingController _societyChargesController;
  late final TextEditingController _bookingAmountController;
  late final TextEditingController _brokerageController;

  // Commercial
  late final TextEditingController _roiEstimateController;
  late final TextEditingController _currentRentalIncomeController;
  late final TextEditingController _leaseDurationController;
  late final TextEditingController _leaseEscalationController;
  late final TextEditingController _camChargesController;
  late final TextEditingController _fitOutPeriodController;

  // PG
  late final TextEditingController _monthlyRentPerBedController;
  late final TextEditingController _monthlyRentPerRoomController;
  late final TextEditingController _foodChargesController;
  late final TextEditingController _laundryChargesController;
  late final TextEditingController _totalSalePriceController;
  late final TextEditingController _occupancyRateController;

  @override
  void initState() {
    super.initState();
    final p = context.read<PostPropertyProvider>();
    _priceController = TextEditingController(text: p.price);
    _ratePerAreaController = TextEditingController(text: p.ratePerArea);
    _securityDepositController = TextEditingController(text: p.securityDeposit);
    _maintenanceController = TextEditingController(text: p.maintenanceCharges);
    _societyChargesController = TextEditingController(
      text: p.text('societyCharges'),
    );
    _bookingAmountController = TextEditingController(text: p.bookingAmount);
    _brokerageController = TextEditingController(text: p.brokerage);
    // TEMPORARY — P0 real-device edit-hydration trace.
    debugPrint(
      '[EDIT_TRACE][PRICING] provider.bookingAmount="${p.bookingAmount}" '
      'controller.bookingAmount="${_bookingAmountController.text}"',
    );
    debugPrint(
      '[EDIT_TRACE][PRICING] provider.brokerage="${p.brokerage}" '
      'controller.brokerage="${_brokerageController.text}"',
    );
    debugPrint(
      '[EDIT_TRACE][PRICING] provider.priceNegotiable=${p.priceNegotiable} '
      'provider.allInclusivePriceToggle=${p.allInclusivePriceToggle}',
    );

    _roiEstimateController = TextEditingController(text: p.text('roiEstimate'));
    _currentRentalIncomeController = TextEditingController(
      text: p.text('currentRentalIncome'),
    );
    _leaseDurationController = TextEditingController(
      text: p.text('leaseDuration'),
    );
    _leaseEscalationController = TextEditingController(
      text: p.text('leaseEscalationPercent'),
    );
    _camChargesController = TextEditingController(text: p.text('camCharges'));
    _fitOutPeriodController = TextEditingController(
      text: p.text('fitOutPeriod'),
    );

    _monthlyRentPerBedController = TextEditingController(
      text: p.text('monthlyRentPerBed'),
    );
    _monthlyRentPerRoomController = TextEditingController(
      text: p.text('monthlyRentPerRoom'),
    );
    _foodChargesController = TextEditingController(text: p.text('foodCharges'));
    _laundryChargesController = TextEditingController(
      text: p.text('laundryCharges'),
    );
    _totalSalePriceController = TextEditingController(
      text: p.text('totalSalePrice'),
    );
    _occupancyRateController = TextEditingController(
      text: p.text('occupancyRate'),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _ratePerAreaController.dispose();
    _securityDepositController.dispose();
    _maintenanceController.dispose();
    _societyChargesController.dispose();
    _bookingAmountController.dispose();
    _brokerageController.dispose();
    _roiEstimateController.dispose();
    _currentRentalIncomeController.dispose();
    _leaseDurationController.dispose();
    _leaseEscalationController.dispose();
    _camChargesController.dispose();
    _fitOutPeriodController.dispose();
    _monthlyRentPerBedController.dispose();
    _monthlyRentPerRoomController.dispose();
    _foodChargesController.dispose();
    _laundryChargesController.dispose();
    _totalSalePriceController.dispose();
    _occupancyRateController.dispose();
    super.dispose();
  }

  /// Mirrors `<AmountInWords value={...}/>`, rendered under every rupee
  /// input in the portal's PricingStep — not just the headline price.
  Widget _amountWords(String value) {
    final words = amountToWordsIndian(value);
    if (words.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '₹${groupIndianDigits(value)} · $words Rupees',
        style: AppTextStyles.caption,
      ),
    );
  }

  String _priceLabel(ListingIntent? intent) {
    switch (intent) {
      case ListingIntent.rent:
        return 'Monthly Rent';
      case ListingIntent.lease:
        return 'Lease Amount';
      case ListingIntent.sell:
      default:
        return 'Expected Price';
    }
  }

  /// The label React passes to `<PriceInput label=...>`, per category and
  /// listing type (PricingStep.tsx:594-718). Transcribed verbatim, including
  /// the portal saying "Total Asking Price" on residential and commercial
  /// *rent*, and the missing space in land/sell's "Asking Price*".
  ///
  /// Returns null for the two PG branches React gives a different control:
  /// pg/rent uses Monthly Rent Per Bed, pg/sell uses Total Sale Price.
  static String? _askingPriceLabel(
    PropertyCategory? category,
    ListingIntent? intent,
  ) {
    return switch ((category, intent)) {
      (PropertyCategory.land, ListingIntent.rent) => 'Rent amount per month *',
      (PropertyCategory.land, ListingIntent.sell) => 'Asking Price*',
      (PropertyCategory.land, ListingIntent.lease) => 'Lease Amount per year *',
      (PropertyCategory.pg, ListingIntent.lease) => 'Lease Amount per year *',
      (PropertyCategory.pg, _) => null,
      (_, ListingIntent.rent) => 'Total Asking Price *',
      (_, ListingIntent.sell) => 'Expected Price *',
      (_, ListingIntent.lease) => 'Lease Amount *',
      _ => null,
    };
  }

  /// React's `PriceInput` writes three fields from the one box
  /// (PricingStep.tsx:44) — `price` is the column, `expectedPrice` and
  /// `leaseAmount` are the metadata mirrors the web reads back.
  Widget _priceField(PostPropertyProvider provider) {
    final label = _askingPriceLabel(provider.category, provider.listingIntent);
    if (label == null) return const SizedBox.shrink();
    final words = amountToWordsIndian(provider.price);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardField(
          label: label,
          child: WizardTextField(
            controller: _priceController,
            hint: '0',
            keyboardType: TextInputType.number,
            onChanged: (v) {
              // `value.replace(/[^\d]/g, '')` — digits only, no decimal point.
              final digits = v.replaceAll(RegExp(r'[^\d]'), '');
              final p = context.read<PostPropertyProvider>();
              p.setPrice(digits);
              p.setText('expectedPrice', digits);
              p.setText('leaseAmount', digits);
            },
          ),
        ),
        // Mirrors `<AmountInWords value={...}/>` (PricingStep.tsx:53) —
        // "₹45,00,000 · Forty Five Lakh Rupees", live on every keystroke.
        if (words.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '₹${groupIndianDigits(provider.price)} · $words Rupees',
            style: AppTextStyles.caption,
          ),
        ],
        const WizardDivider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final intent = provider.listingIntent;
    final isSell = intent == ListingIntent.sell;
    final isRentOrLease =
        intent == ListingIntent.rent || intent == ListingIntent.lease;
    final isCommercial = provider.category == PropertyCategory.commercial;
    final isPg = provider.category == PropertyCategory.pg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.currency_rupee, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                '${_priceLabel(intent)}: ${provider.price.isEmpty ? '—' : provider.price}',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.request_quote_outlined,
          title: 'Pricing Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // React renders PriceInput first in every branch.
              _priceField(provider),
              if (isSell && !isPg) ...[
                WizardField(
                  // Was "Rate per Area" with no required marker — unclear
                  // this field (unlike every other value+unit pair in the
                  // wizard) had no persistent currency symbol once typed
                  // into, and its unit dropdown had no caption of its own.
                  // Portal's equivalent label is "Rate Per Unit *"
                  // (PricingStep.tsx:113-116) — presentation-only change,
                  // same `ratePerArea`/`ratePerAreaUnit` fields underneath.
                  label: 'Rate Per Unit *',
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: WizardTextField(
                          controller: _ratePerAreaController,
                          hint: '0',
                          prefixText: '₹',
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            // React writes BOTH keys from this one input
                            // (PricingStep.tsx:124): ratePerArea is the
                            // canonical field, pricePerSqFt the mirror the
                            // web reads on cards. Flutter wrote only the
                            // former, so metadata.pricePerSqFt was blank on
                            // every app-created listing.
                            final p = context.read<PostPropertyProvider>();
                            p.setRatePerArea(v);
                            p.setText('pricePerSqFt', v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _RateUnitDropdown(provider: provider)),
                    ],
                  ),
                ),
                _amountWords(provider.ratePerArea),
                const WizardDivider(),
              ],
              if (isRentOrLease) ...[
                WizardField(
                  label: 'Security Deposit *',
                  child: WizardTextField(
                    controller: _securityDepositController,
                    hint: '₹0',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setSecurityDeposit(v),
                  ),
                ),
                _amountWords(provider.securityDeposit),
                const WizardDivider(),
              ],
              // React shows "Society charges" for apartments and
              // "Maintenance charges" for everything else EXCEPT Land
              // (PricingStep.tsx's own JSX per branch, not just
              // propertyListingRules.ts's required-ness rule): never on
              // Land at all, and on a sell listing only for Others and PG
              // (Others/Sell renders <Maintenance/> at PricingStep.tsx:803;
              // PG/Sell at :752) — Residential/Sell and Commercial/Sell are
              // the two sell branches that genuinely have no such field.
              if (_isApartmentRental(provider)) ...[
                WizardField(
                  label: 'Society Charges (Monthly) *',
                  child: WizardTextField(
                    controller: _societyChargesController,
                    hint: '₹0',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('societyCharges', v),
                  ),
                ),
                _amountWords(provider.text('societyCharges')),
              ] else if (provider.category != PropertyCategory.land &&
                  (isRentOrLease ||
                      (isSell &&
                          provider.category == PropertyCategory.other))) ...[
                WizardField(
                  label: 'Maintenance Charges (Monthly) *',
                  child: WizardTextField(
                    controller: _maintenanceController,
                    hint: '₹0',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setMaintenanceCharges(v),
                  ),
                ),
                _amountWords(provider.maintenanceCharges),
              ],
              // React renders <TokenAmount> in every one of its 15 branches.
              ...[
                const WizardDivider(),
                WizardField(
                  label: 'Booking / Token Amount *',
                  child: WizardTextField(
                    controller: _bookingAmountController,
                    hint: '₹0',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBookingAmount(v),
                  ),
                ),
                _amountWords(provider.bookingAmount),
              ],
              if (isRentOrLease) ...[
                const WizardDivider(),
                WizardField(
                  label: 'Lock-in Period *',
                  child: WizardChipGroup(
                    options: _lockInOptions,
                    selected: provider.lockInPeriod,
                    onSelected: (v) =>
                        context.read<PostPropertyProvider>().setLockInPeriod(v),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isCommercial && isSell) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.trending_up_outlined,
            title: 'Investment Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: WizardField(
                        label: 'ROI Estimate (%)',
                        child: WizardTextField(
                          controller: _roiEstimateController,
                          hint: 'e.g., 6%',
                          onChanged: (v) => context
                              .read<PostPropertyProvider>()
                              .setText('roiEstimate', v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WizardField(
                        label: 'Current Rental Income',
                        child: WizardTextField(
                          controller: _currentRentalIncomeController,
                          hint: '₹/month',
                          onChanged: (v) => context
                              .read<PostPropertyProvider>()
                              .setText('currentRentalIncome', v),
                        ),
                      ),
                    ),
                  ],
                ),
                const WizardDivider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Currently Tenant Occupied',
                      value: provider.boolVal('tenantOccupied'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('tenantOccupied', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Lease Running',
                      value: provider.boolVal('leaseRunning'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('leaseRunning', v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        // Lease only — not needed on a commercial rent listing (the lease-
        // term rules in listing_validation_rules.dart match this).
        if (isCommercial && intent == ListingIntent.lease) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.article_outlined,
            title: 'Commercial Lease Terms',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: WizardField(
                        label: 'Lease Duration / Min Duration',
                        child: WizardTextField(
                          controller: _leaseDurationController,
                          hint: 'e.g., 3 Years',
                          onChanged: (v) {
                            final p = context.read<PostPropertyProvider>();
                            p.setText('leaseDuration', v);
                            p.setText('minRentalDuration', v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WizardField(
                        label: 'Rent Escalation (%)',
                        child: WizardTextField(
                          controller: _leaseEscalationController,
                          hint: 'e.g., 5% after 1 year',
                          onChanged: (v) {
                            final p = context.read<PostPropertyProvider>();
                            p.setText('leaseEscalationPercent', v);
                            p.setText('rentEscalation', v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const WizardDivider(),
                Row(
                  children: [
                    Expanded(
                      child: WizardField(
                        label: 'CAM Charges (Monthly)',
                        child: WizardTextField(
                          controller: _camChargesController,
                          hint: '₹ or ₹/sq.ft',
                          onChanged: (v) => context
                              .read<PostPropertyProvider>()
                              .setText('camCharges', v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WizardField(
                        label: 'Fit-out Period',
                        child: WizardTextField(
                          controller: _fitOutPeriodController,
                          hint: 'e.g., 1 Month',
                          onChanged: (v) => context
                              .read<PostPropertyProvider>()
                              .setText('fitOutPeriod', v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (isPg && intent == ListingIntent.rent) ...[
          WizardCard(
            icon: Icons.bed_outlined,
            title: 'PG Rent Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WizardField(
                            label: 'Monthly Rent Per Bed',
                            child: WizardTextField(
                              controller: _monthlyRentPerBedController,
                              hint: '₹0',
                              keyboardType: TextInputType.number,
                              onChanged: (v) => context
                                  .read<PostPropertyProvider>()
                                  .setText('monthlyRentPerBed', v),
                            ),
                          ),
                          _amountWords(provider.text('monthlyRentPerBed')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WizardField(
                            label: 'Monthly Rent Per Room',
                            child: WizardTextField(
                              controller: _monthlyRentPerRoomController,
                              hint: '₹0',
                              keyboardType: TextInputType.number,
                              onChanged: (v) => context
                                  .read<PostPropertyProvider>()
                                  .setText('monthlyRentPerRoom', v),
                            ),
                          ),
                          _amountWords(provider.text('monthlyRentPerRoom')),
                        ],
                      ),
                    ),
                  ],
                ),
                const WizardDivider(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WizardField(
                            label: 'Food Charges (if separate)',
                            child: WizardTextField(
                              controller: _foodChargesController,
                              hint: '₹0',
                              keyboardType: TextInputType.number,
                              onChanged: (v) => context
                                  .read<PostPropertyProvider>()
                                  .setText('foodCharges', v),
                            ),
                          ),
                          _amountWords(provider.text('foodCharges')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WizardField(
                            label: 'Laundry Charges (if separate)',
                            child: WizardTextField(
                              controller: _laundryChargesController,
                              hint: '₹0',
                              keyboardType: TextInputType.number,
                              onChanged: (v) => context
                                  .read<PostPropertyProvider>()
                                  .setText('laundryCharges', v),
                            ),
                          ),
                          _amountWords(provider.text('laundryCharges')),
                        ],
                      ),
                    ),
                  ],
                ),
                const WizardDivider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Housekeeping Included',
                      value: provider.boolVal('housekeepingIncluded'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('housekeepingIncluded', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Company Tie-Up Allowed',
                      value: provider.boolVal('companyTieUp'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('companyTieUp', v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (isPg && intent == ListingIntent.sell) ...[
          WizardCard(
            icon: Icons.sell_outlined,
            title: 'PG Sale Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WizardField(
                            label: 'Total Sale Price',
                            child: WizardTextField(
                              controller: _totalSalePriceController,
                              hint: '₹0',
                              keyboardType: TextInputType.number,
                              onChanged: (v) => context
                                  .read<PostPropertyProvider>()
                                  .setText('totalSalePrice', v),
                            ),
                          ),
                          _amountWords(provider.text('totalSalePrice')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WizardField(
                        label: 'Current Occupancy Rate (%)',
                        child: WizardTextField(
                          controller: _occupancyRateController,
                          hint: 'e.g., 80',
                          keyboardType: TextInputType.number,
                          onChanged: (v) => context
                              .read<PostPropertyProvider>()
                              .setText('occupancyRate', v),
                        ),
                      ),
                    ),
                  ],
                ),
                const WizardDivider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Business Included',
                      value: provider.boolVal('businessIncluded'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('businessIncluded', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Furniture Included',
                      value: provider.boolVal('furnitureIncluded'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('furnitureIncluded', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Brand/Franchise Included',
                      value: provider.boolVal('brandFranchiseIncluded'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('brandFranchiseIncluded', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Existing Staff Included',
                      value: provider.boolVal('existingStaffIncluded'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('existingStaffIncluded', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Management Transfer',
                      value: provider.boolVal('managementTransfer'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('managementTransfer', v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (isPg && intent == ListingIntent.lease) ...[
          WizardCard(
            icon: Icons.handshake_outlined,
            title: 'PG Lease Details',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WizardCheckboxTile(
                  label: 'Renewable Lease',
                  value: provider.boolVal('renewableLease'),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setBoolVal('renewableLease', v),
                ),
                WizardCheckboxTile(
                  label: 'Franchise Operation Allowed',
                  value: provider.boolVal('franchiseOperationAllowed'),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setBoolVal('franchiseOperationAllowed', v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        WizardCard(
          icon: Icons.tune_outlined,
          title: 'Other Details',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Portal shows Price Negotiable / All Inclusive / Tax & Govt
              // Included only for Land and Residential, across every listing
              // type (not gated on sell) — never for Commercial/PG/Others.
              // "Price is Negotiable" itself is deliberately not offered here
              // (explicit product decision) — `priceNegotiable` stays wired
              // end to end and simply keeps its default `false`/"not
              // negotiable" for every new listing.
              if (provider.category == PropertyCategory.land ||
                  provider.category == PropertyCategory.residential) ...[
                WizardCheckboxTile(
                  label: 'All Inclusive Price',
                  value: provider.allInclusivePriceToggle,
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setAllInclusivePriceToggle(v),
                ),
                WizardCheckboxTile(
                  label: 'Tax & Govt Charges Included',
                  value: provider.taxGovtChargesIncluded,
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setTaxGovtChargesIncluded(v),
                ),
              ],
              // "Loan Available" itself is deliberately not offered here
              // (explicit product decision) — `loanAvailability` stays wired
              // end to end and simply keeps its default `false` for every
              // new listing.
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.handshake_outlined,
          title: 'Brokerage',
          child: WizardField(
            label: 'Brokerage (if applicable)',
            child: WizardTextField(
              controller: _brokerageController,
              hint: 'e.g., 1 Month Rent or 1% of Price',
              onChanged: (v) =>
                  context.read<PostPropertyProvider>().setBrokerage(v),
            ),
          ),
        ),
      ],
    );
  }
}

/// Unit for "rate per area".
///
/// React defaults this to `ratePerAreaUnit || areaUnit || 'sq_ft'` and offers
/// the same category-dependent set as the Dimensions step
/// (PricingStep.tsx:132), so a commercial listing cannot quote a rate in bigha.
class _RateUnitDropdown extends StatelessWidget {
  const _RateUnitDropdown({required this.provider});

  final PostPropertyProvider provider;

  @override
  Widget build(BuildContext context) {
    final stored = provider.text('ratePerAreaUnit');
    final value = stored.isNotEmpty
        ? stored
        : (provider.areaUnit.isNotEmpty
              ? provider.areaUnit
              : defaultAreaUnitFor(provider.category));
    final units = areaUnitsFor(provider.category, value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: units
              .map((u) => DropdownMenuItem(value: u.$1, child: Text(u.$2)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              context.read<PostPropertyProvider>().setText(
                'ratePerAreaUnit',
                v,
              );
            }
          },
        ),
      ),
    );
  }
}
