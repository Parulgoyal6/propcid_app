import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_constants.dart';

/// Step 4: property condition, building condition (Residential/Commercial),
/// available-from date and a read-only furnishing summary — plus a
/// PG-specific Food & Housekeeping block. Mirrors the React ConditionStep
/// (labelled "Condition" in the stepper).
class ConditionStep extends StatelessWidget {
  const ConditionStep({super.key});

  static const _mealOptions = ['Breakfast', 'Lunch', 'Dinner', 'Tea / Snacks'];

  // Per-meal item pickers, shown when that meal is ticked in Meals Included
  // (ConditionStep.tsx:254-337) — previously missing in Flutter entirely.
  static const _breakfastItems = [
    'Paratha',
    'Bread & Butter',
    'Eggs',
    'Omelette',
    'Poha',
    'Upma',
    'Idli',
    'Dosa',
    'Cereal',
    'Milk',
    'Tea',
    'Coffee',
    'Fruits',
    'Sandwich',
  ];

  static const _lunchItems = [
    'Rice',
    'Dal',
    'Roti/Chapati',
    'Vegetable Curry',
    'Dal Makhani',
    'Paneer',
    'Chicken',
    'Fish',
    'Curry',
    'Salad',
    'Yogurt',
    'Pickle',
  ];

  static const _dinnerItems = [
    'Rice',
    'Dal',
    'Roti/Chapati',
    'Vegetable Curry',
    'Dal Makhani',
    'Paneer',
    'Chicken',
    'Fish',
    'Curry',
    'Salad',
    'Yogurt',
    'Pickle',
    'Soup',
  ];

  static const _teaSnacksItems = [
    'Tea',
    'Coffee',
    'Biscuits',
    'Cookies',
    'Chips',
    'Namkeen',
    'Samosa',
    'Pakora',
    'Sandwich',
    'Maggi',
    'Fruits',
    'Juice',
    'Milk',
  ];

  static const _cleaningFrequencies = [
    'Daily',
    'Alternate Days',
    'Weekly',
    'On Demand',
  ];

  static const _linenFrequencies = [
    'Daily',
    'Alternate Days',
    'Weekly',
    'Fortnightly',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final isPg = provider.category == PropertyCategory.pg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Building condition — residential and commercial, both required by
        // the portal for these two categories (ConditionStep.tsx's
        // BuildingCondition() renders for isResidential || isCommercial).
        if (provider.category == PropertyCategory.commercial ||
            provider.category == PropertyCategory.residential) ...[
          const _BuildingConditionCard(),
          const SizedBox(height: 20),
        ],

        WizardCard(
          icon: Icons.fact_check_outlined,
          title: 'Condition & Availability',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WizardField(
                label: 'Property Condition *',
                child: WizardChipGroup(
                  options: kPropertyConditions,
                  selected: provider.propertyCondition,
                  onSelected: (v) => context
                      .read<PostPropertyProvider>()
                      .setPropertyCondition(v),
                ),
              ),
              const WizardDivider(),
              // React renders <AvailableFrom> in every ConditionStep branch
              // (ConditionStep.tsx:365-445). This step is only visible for
              // commercial, PG and others — land and residential answer the
              // same question on the Dimensions step — so without it those
              // three categories had a required field with no input anywhere
              // and could never leave this step.
              const _AvailableFromField(),
            ],
          ),
        ),
        if (isPg) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.restaurant_outlined,
            title: 'Food & Services',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Veg Food Available',
                      value: provider.boolVal('vegFoodPg'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('vegFoodPg', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Non-Veg Food Available',
                      value: provider.boolVal('nonVegFoodPg'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('nonVegFoodPg', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Self-Cooking Allowed',
                      value: provider.boolVal('selfCookingAllowed'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('selfCookingAllowed', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Shared Kitchen',
                      value: provider.boolVal('sharedKitchen'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('sharedKitchen', v),
                    ),
                  ],
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Meals Included',
                  child: WizardMultiChipGroup(
                    options: _mealOptions,
                    selected: provider.listVal('mealsIncluded'),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setListVal('mealsIncluded', v),
                  ),
                ),
                if (provider
                    .listVal('mealsIncluded')
                    .contains('Breakfast')) ...[
                  const SizedBox(height: 12),
                  WizardField(
                    label: 'Breakfast Items',
                    child: WizardMultiChipGroup(
                      options: _breakfastItems,
                      selected: provider.listVal('breakfastItems'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setListVal('breakfastItems', v),
                    ),
                  ),
                ],
                if (provider.listVal('mealsIncluded').contains('Lunch')) ...[
                  const SizedBox(height: 12),
                  WizardField(
                    label: 'Lunch Items',
                    child: WizardMultiChipGroup(
                      options: _lunchItems,
                      selected: provider.listVal('lunchItems'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setListVal('lunchItems', v),
                    ),
                  ),
                ],
                if (provider.listVal('mealsIncluded').contains('Dinner')) ...[
                  const SizedBox(height: 12),
                  WizardField(
                    label: 'Dinner Items',
                    child: WizardMultiChipGroup(
                      options: _dinnerItems,
                      selected: provider.listVal('dinnerItems'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setListVal('dinnerItems', v),
                    ),
                  ),
                ],
                if (provider
                    .listVal('mealsIncluded')
                    .contains('Tea / Snacks')) ...[
                  const SizedBox(height: 12),
                  WizardField(
                    label: 'Tea / Snacks Items',
                    child: WizardMultiChipGroup(
                      options: _teaSnacksItems,
                      selected: provider.listVal('teaSnacksItems'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setListVal('teaSnacksItems', v),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.cleaning_services_outlined,
            title: 'Housekeeping',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Laundry Service',
                      value: provider.boolVal('laundryService'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('laundryService', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Cleaning Service',
                      value: provider.boolVal('cleaningService'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('cleaningService', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Daily Cleaning',
                      value: provider.boolVal('dailyCleaning'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('dailyCleaning', v),
                    ),
                  ],
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Room Cleaning Frequency',
                  child: WizardChipGroup(
                    options: _cleaningFrequencies,
                    selected: provider.text('roomCleaningFrequency').isEmpty
                        ? null
                        : provider.text('roomCleaningFrequency'),
                    onSelected: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('roomCleaningFrequency', v),
                  ),
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Linen Change Frequency',
                  child: WizardChipGroup(
                    options: _linenFrequencies,
                    selected: provider.text('linenChangeFrequency').isEmpty
                        ? null
                        : provider.text('linenChangeFrequency'),
                    onSelected: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('linenChangeFrequency', v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Building condition (residential + commercial). Separate stateful widget so
/// [ConditionStep] can stay stateless while Building Age still gets a proper
/// controller.
class _BuildingConditionCard extends StatefulWidget {
  const _BuildingConditionCard();

  @override
  State<_BuildingConditionCard> createState() => _BuildingConditionCardState();
}

class _BuildingConditionCardState extends State<_BuildingConditionCard> {
  /// Verbatim from the ownershipTypeBuilding select in ConditionStep.tsx —
  /// three options, NOT the four the property-condition select offers.
  static const List<String> _kBuildingOwnershipTypes = [
    'Freehold',
    'Leasehold',
    'Co-ownership',
  ];

  late final TextEditingController _buildingAgeController;

  @override
  void initState() {
    super.initState();
    _buildingAgeController = TextEditingController(
      text: context.read<PostPropertyProvider>().buildingInventoryText(
        'buildingAge',
      ),
    );
  }

  @override
  void dispose() {
    _buildingAgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();

    return WizardCard(
      icon: Icons.apartment_outlined,
      title: 'Building Condition',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardField(
            // This card renders for residential too (see the `isCommercial
            // || isResidential` gate below), but the validation rule for
            // both these fields is `applies: isCommercial` only
            // (listing_validation_rules.dart) — residential is never
            // actually required to fill them in, so the asterisk is
            // conditional rather than baked into the label unconditionally.
            label: provider.category == PropertyCategory.commercial
                ? 'Building Age *'
                : 'Building Age',
            child: WizardTextField(
              controller: _buildingAgeController,
              hint: 'e.g., 5 years',
              onChanged: (v) => context
                  .read<PostPropertyProvider>()
                  .setBuildingInventoryValue('buildingAge', v),
            ),
          ),
          const WizardDivider(),
          WizardField(
            label: provider.category == PropertyCategory.commercial
                ? 'Ownership Type *'
                : 'Ownership Type',
            child: WizardChipGroup(
              options: _kBuildingOwnershipTypes,
              selected:
                  provider
                      .buildingInventoryText('ownershipTypeBuilding')
                      .isEmpty
                  ? null
                  : provider.buildingInventoryText('ownershipTypeBuilding'),
              onSelected: (v) => context
                  .read<PostPropertyProvider>()
                  .setBuildingInventoryValue('ownershipTypeBuilding', v),
            ),
          ),
          const WizardDivider(),
          WizardCheckboxTile(
            label: 'Corner Property',
            value:
                (provider.buildingInventoryValue('cornerPropertyBuilding')
                    as bool?) ??
                false,
            onChanged: (v) => context
                .read<PostPropertyProvider>()
                .setBuildingInventoryValue('cornerPropertyBuilding', v),
          ),
        ],
      ),
    );
  }
}

/// "Available From *" — the checkbox/date pair React uses identically on the
/// Dimensions and Condition steps: ticking Immediately stores the literal
/// `'Immediately'`, otherwise a date is picked, and the date box is hidden
/// while Immediately is set.
class _AvailableFromField extends StatelessWidget {
  const _AvailableFromField();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PostPropertyProvider>();
    final d = p.availableFrom;
    final text = d == null
        ? 'Select a date'
        : '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';

    return WizardField(
      label: 'Available From *',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardCheckboxTile(
            label: 'Immediately',
            value: p.availableImmediately,
            onChanged: (v) =>
                context.read<PostPropertyProvider>().setAvailableImmediately(v),
          ),
          if (!p.availableImmediately) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: d ?? now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 20),
                );
                if (picked != null && context.mounted) {
                  context.read<PostPropertyProvider>().setAvailableFrom(picked);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: AppTextStyles.body.copyWith(
                        color: d == null
                            ? AppColors.textHint
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
