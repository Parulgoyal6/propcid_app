import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/compare_toggle_handler.dart';
import '../../providers/compare_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/property_provider.dart';
import '../../services/notification_alert_preference.dart';
import '../../widgets/property_card_compact.dart';
import '../../widgets/bottom_nav_bar.dart';

class ShortlistScreen extends StatefulWidget {
  const ShortlistScreen({super.key});

  @override
  State<ShortlistScreen> createState() => _ShortlistScreenState();
}

class _ShortlistScreenState extends State<ShortlistScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Edit mode: each saved property shows a remove button.
  bool _isEditing = false;

  /// Mirrors the existing Settings "Notification Alerts" preference.
  bool _alertsEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    NotificationAlertPreference.isEnabled().then((value) {
      if (mounted) setState(() => _alertsEnabled = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<NavigationProvider>(context, listen: false).setIndex(2);
      }
    });
  }

  /// "Enable Alerts" reuses the app's existing alert preference
  /// ([NotificationAlertPreference], the same switch as Settings →
  /// Notification Alerts). Once on, the button opens the Notifications
  /// screen instead.
  Future<void> _onAlertsPressed() async {
    if (_alertsEnabled) {
      Navigator.pushNamed(context, AppConstants.notificationsScreen);
      return;
    }
    await NotificationAlertPreference.setEnabled(true);
    if (!mounted) return;
    setState(() => _alertsEnabled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification alerts turned on')),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildPropertiesTab(), _buildProjectsTab()],
              ),
            ),
            _buildPromoBanner(),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.pop(context);
                } else {
                  Provider.of<NavigationProvider>(
                    context,
                    listen: false,
                  ).setIndex(0);
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 16),
          // Named "Saved": this page lists `saved_properties` — the same list
          // Profile → Saved and My Activity → Saved show. Likes live in My
          // Activity → Liked.
          Text(
            'Saved',
            style: AppTextStyles.heading1.copyWith(fontSize: 20),
          ),
          const Spacer(),
          Consumer<PropertyProvider>(
            builder: (context, propertyProvider, _) {
              final hasItems = propertyProvider
                  .getShortlistedProperties()
                  .isNotEmpty;
              return TextButton(
                // Toggles remove mode; disabled when there is nothing saved.
                onPressed: hasItems
                    ? () => setState(() => _isEditing = !_isEditing)
                    : null,
                child: Text(_isEditing && hasItems ? 'Done' : 'Edit'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Consumer<PropertyProvider>(
      builder: (context, propertyProvider, child) {
        final count = propertyProvider.getShortlistedProperties().length;
        return Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: AppTextStyles.body,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Properties ($count)'),
              const Tab(text: 'Projects (0)'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPropertiesTab() {
    final compareProvider = context.watch<CompareProvider>();
    return Consumer<PropertyProvider>(
      builder: (context, propertyProvider, child) {
        final shortlistedProperties = propertyProvider
            .getShortlistedProperties();

        if (shortlistedProperties.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bookmark_border_rounded,
                  size: 64,
                  color: AppColors.textHint,
                ),
                const SizedBox(height: 16),
                Text(
                  'No saved properties',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: shortlistedProperties.length,
          itemBuilder: (context, index) {
            return PropertyCardCompact(
              property: shortlistedProperties[index],
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppConstants.propertyDetailScreen,
                  arguments: {'propertyId': shortlistedProperties[index].id},
                );
              },
              onFavoriteToggle: () {
                propertyProvider.toggleShortlist(
                  shortlistedProperties[index].id,
                );
              },
              // Edit mode: the card's existing remove button, removing the
              // property from Saved via the same toggleShortlist call.
              onDelete: _isEditing
                  ? () => propertyProvider.toggleShortlist(
                      shortlistedProperties[index].id,
                    )
                  : null,
              isInCompare: compareProvider.isSelected(
                shortlistedProperties[index].id,
              ),
              onCompareToggle: () =>
                  handleCompareToggle(context, shortlistedProperties[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildProjectsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.apartment, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No saved projects',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Don't miss out!",
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Get alerts for new properties',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _onAlertsPressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_alertsEnabled ? 'Alerts On' : 'Enable Alerts'),
          ),
        ],
      ),
    );
  }
}
