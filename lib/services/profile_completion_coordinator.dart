import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/rbac_service.dart';

/// ProfileCompletionCoordinator
/// Manages profile completeness checking and redirects users to appropriate completion screens
class ProfileCompletionCoordinator {
  final AuthProvider _authProvider;
  final AuthService _authService;

  ProfileCompletionCoordinator(this._authProvider, this._authService);

  /// Check if user needs to complete profile
  /// Returns true if profile is incomplete and user should be redirected
  Future<bool> shouldCompleteProfile(BuildContext context) async {
    final userType = _authProvider.userType;

    if (userType == null) {
      return false;
    }

    if (userType != 'builder' &&
        userType != 'broker' &&
        userType != 'influencer') {
      return false;
    }

    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        return false;
      }

      final profileData = await _authService.getUserProfile(userId);

      if (profileData == null) {
        // No profile exists - should complete
        return true;
      }

      // Check if profile is complete
      final isComplete = RBACService.isProfileComplete(profileData);

      return !isComplete;
    } catch (e) {
      debugPrint('Error checking profile completeness: $e');
      return false;
    }
  }

  /// Navigate to appropriate profile completion screen based on user type
  Future<void> navigateToCompletionScreen(BuildContext context) async {
    final userType = _authProvider.userType;

    late final String routeName;

    switch (userType) {
      case 'builder':
        routeName = '/builder-profile';
        break;
      case 'broker':
        routeName = '/broker-profile';
        break;
      case 'influencer':
        routeName = '/influencer-profile';
        break;
      default:
        // Unknown user type - don't redirect.
        return;
    }

    await Navigator.of(context).pushNamed(routeName);
  }

  /// Check and redirect if profile is incomplete
  Future<void> checkAndRedirect(BuildContext context) async {
    final shouldComplete = await shouldCompleteProfile(context);

    if (!context.mounted) return;

    if (shouldComplete) {
      await navigateToCompletionScreen(context);
    }
  }

  /// Get profile completeness percentage
  Future<int> getProfileCompleteness() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        return 0;
      }

      final profileData = await _authService.getUserProfile(userId);

      if (profileData == null) {
        return 0;
      }

      return RBACService.calculateProfileCompleteness(profileData);
    } catch (e) {
      debugPrint('Error getting profile completeness: $e');
      return 0;
    }
  }

  /// Get missing required fields for profile completion
  Future<List<String>> getMissingFields() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        return [];
      }

      final profileData = await _authService.getUserProfile(userId);

      if (profileData == null) {
        return RBACService.getRequiredFields(
          _authProvider.userRole ?? '',
          _authProvider.userType ?? '',
        );
      }

      final requiredFields = RBACService.getRequiredFields(
        _authProvider.userRole ?? '',
        _authProvider.userType ?? '',
      );

      final missingFields = <String>[];

      for (final field in requiredFields) {
        final value = profileData[field];
        if (value == null || value.toString().trim().isEmpty) {
          missingFields.add(field);
        }
      }

      return missingFields;
    } catch (e) {
      debugPrint('Error getting missing fields: $e');
      return [];
    }
  }

  /// Show profile completion prompt dialog
  Future<bool> showCompletionPrompt(BuildContext context) async {
    final completeness = await getProfileCompleteness();
    final missingFields = await getMissingFields();

    if (!context.mounted) return false;

    if (completeness >= 100 || missingFields.isEmpty) {
      return false;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Complete Your Profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your profile is ${completeness}% complete',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: completeness / 100),
                const SizedBox(height: 16),
                const Text('Missing information:'),
                const SizedBox(height: 8),
                ...missingFields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6),
                        const SizedBox(width: 8),
                        Text(_formatFieldName(field)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Complete your profile to unlock all features and improve visibility.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Complete Now'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _formatFieldName(String fieldName) {
    // Convert snake_case to Title Case
    return fieldName
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

/// Mixin for widgets that need profile completion checking
mixin ProfileCompletionChecker<T extends StatefulWidget> on State<T> {
  late ProfileCompletionCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    final authService = AuthService();
    _coordinator = ProfileCompletionCoordinator(authProvider, authService);
  }

  Future<void> checkProfileCompletion() {
    return _coordinator.checkAndRedirect(context);
  }

  Future<bool> showProfileCompletionPrompt() {
    return _coordinator.showCompletionPrompt(context);
  }
}
