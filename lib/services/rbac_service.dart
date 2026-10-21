import '../providers/auth_provider.dart';

/// RBAC Service for role-based access control
/// Uses existing userRole and userType from AuthProvider
class RBACService {
  final AuthProvider _authProvider;

  RBACService(this._authProvider);

  // ========== ROLE CHECKS ==========

  /// Check if current user is a buyer
  bool get isBuyer => _authProvider.userRole == 'buyer';

  /// Check if current user is a seller
  bool get isSeller => _authProvider.userRole == 'seller';

  /// Check if current user is a builder
  bool get isBuilder =>
      _authProvider.userRole == 'seller' && _authProvider.userType == 'builder';

  /// Check if current user is a broker
  bool get isBroker =>
      _authProvider.userRole == 'seller' && _authProvider.userType == 'broker';

  /// Check if current user is an influencer
  bool get isInfluencer =>
      _authProvider.userRole == 'seller' &&
      _authProvider.userType == 'influencer';

  /// Check if current user is an individual buyer
  bool get isIndividual =>
      _authProvider.userRole == 'buyer' &&
      _authProvider.userType == 'individual';

  // ========== PERMISSION CHECKS ==========

  /// Can post property (sellers only)
  bool get canPostProperty => isSeller;

  /// Can manage agency (brokers only)
  bool get canManageAgency => isBroker;

  /// Can access builder-specific features
  bool get canAccessBuilderFeatures => isBuilder;

  /// Can access broker-specific features
  bool get canAccessBrokerFeatures => isBroker;

  /// Can access influencer-specific features
  bool get canAccessInfluencerFeatures => isInfluencer;

  /// Can view seller analytics (all sellers)
  bool get canViewAnalytics => isSeller;

  /// Can manage team (builders and brokers)
  bool get canManageTeam => isBuilder || isBroker;

  // ========== VALIDATION ==========

  /// Validate role and user type combination
  static bool isValidRoleCombination(String userRole, String userType) {
    // Valid combinations:
    // buyer + individual
    // seller + builder
    // seller + broker
    // seller + influencer

    if (userRole == 'buyer' && userType == 'individual') {
      return true;
    }

    if (userRole == 'seller') {
      return ['builder', 'broker', 'influencer'].contains(userType);
    }

    return false;
  }

  /// Get required fields for profile completeness based on role
  static List<String> getRequiredFields(String userRole, String userType) {
    if (userRole == 'buyer') {
      return ['display_name', 'email'];
    }

    if (userRole == 'seller') {
      switch (userType) {
        case 'builder':
          return ['company_name', 'rera_number', 'city', 'state'];
        case 'broker':
          return ['agency_name', 'license_number', 'city'];
        case 'influencer':
          return ['bio', 'city'];
        default:
          return [];
      }
    }

    return [];
  }

  /// Calculate profile completeness percentage
  static int calculateProfileCompleteness(Map<String, dynamic> profileData) {
    final userRole = profileData['user_role'] as String?;
    final userType = profileData['user_type'] as String?;

    if (userRole == null || userType == null) return 0;

    final requiredFields = getRequiredFields(userRole, userType);
    if (requiredFields.isEmpty) return 100;

    int filledFields = 0;

    for (final field in requiredFields) {
      final value = profileData[field];
      if (value != null && value.toString().trim().isNotEmpty) {
        filledFields++;
      }
    }

    return ((filledFields / requiredFields.length) * 100).round();
  }

  /// Check if profile is complete
  static bool isProfileComplete(Map<String, dynamic> profileData) {
    return calculateProfileCompleteness(profileData) >= 100;
  }

  /// Get profile completion screen route based on role
  static String? getProfileCompletionRoute(String userRole, String userType) {
    if (userRole == 'buyer') {
      return null; // Buyers don't need profile completion
    }

    if (userRole == 'seller') {
      switch (userType) {
        case 'builder':
          return '/builder-profile';
        case 'broker':
          return '/broker-profile';
        case 'influencer':
          return '/influencer-profile';
        default:
          return null;
      }
    }

    return null;
  }

  @override
  String toString() {
    return 'RBACService(role: ${_authProvider.userRole}, type: ${_authProvider.userType})';
  }
}
