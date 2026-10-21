import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/rbac_service.dart';

/// RoleGuard widget - conditionally shows/hides children based on user role
///
/// Usage examples:
///
/// Show only for buyers:
/// ```dart
/// RoleGuard(
///   allowedRoles: ['buyer'],
///   child: MyWidget(),
/// )
/// ```
///
/// Show only for sellers:
/// ```dart
/// RoleGuard(
///   allowedRoles: ['seller'],
///   child: MyWidget(),
/// )
/// ```
///
/// Show only for builders:
/// ```dart
/// RoleGuard(
///   allowedUserTypes: ['builder'],
///   child: MyWidget(),
/// )
/// ```
///
/// Show for multiple roles:
/// ```dart
/// RoleGuard(
///   allowedRoles: ['buyer', 'seller'],
///   child: MyWidget(),
/// )
/// ```
///
/// Show fallback when not allowed:
/// ```dart
/// RoleGuard(
///   allowedRoles: ['seller'],
///   child: SellerWidget(),
///   fallback: AccessDeniedWidget(),
/// )
/// ```
class RoleGuard extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  final List<String>? allowedRoles;
  final List<String>? allowedUserTypes;
  final bool invert;

  const RoleGuard({
    super.key,
    required this.child,
    this.fallback,
    this.allowedRoles,
    this.allowedUserTypes,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    bool isAllowed = true;

    // Check role restrictions
    if (allowedRoles != null && allowedRoles!.isNotEmpty) {
      final userRole = authProvider.userRole;
      isAllowed = isAllowed && allowedRoles!.contains(userRole);
    }

    // Check user type restrictions
    if (allowedUserTypes != null && allowedUserTypes!.isNotEmpty) {
      final userType = authProvider.userType;
      isAllowed = isAllowed && allowedUserTypes!.contains(userType);
    }

    // Invert if specified
    if (invert) {
      isAllowed = !isAllowed;
    }

    if (isAllowed) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Convenience widgets for common role checks

/// Show only for buyers
class BuyerOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const BuyerOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(allowedRoles: ['buyer'], child: child, fallback: fallback);
  }
}

/// Show only for sellers
class SellerOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const SellerOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedRoles: ['seller'],
      child: child,
      fallback: fallback,
    );
  }
}

/// Show only for builders
class BuilderOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const BuilderOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedUserTypes: ['builder'],
      child: child,
      fallback: fallback,
    );
  }
}

/// Show only for brokers
class BrokerOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const BrokerOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedUserTypes: ['broker'],
      child: child,
      fallback: fallback,
    );
  }
}

/// Show only for influencers
class InfluencerOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const InfluencerOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedUserTypes: ['influencer'],
      child: child,
      fallback: fallback,
    );
  }
}

/// Hide from buyers
class HideFromBuyers extends StatelessWidget {
  final Widget child;

  const HideFromBuyers({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(allowedRoles: ['buyer'], child: child, invert: true);
  }
}

/// Hide from sellers
class HideFromSellers extends StatelessWidget {
  final Widget child;

  const HideFromSellers({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RoleGuard(allowedRoles: ['seller'], child: child, invert: true);
  }
}

/// Show based on RBAC permission
class PermissionBased extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  final bool Function(RBACService) permissionCheck;

  const PermissionBased({
    super.key,
    required this.child,
    this.fallback,
    required this.permissionCheck,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final rbacService = RBACService(authProvider);

    if (permissionCheck(rbacService)) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Show only if user can post property
class CanPostProperty extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const CanPostProperty({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return PermissionBased(
      permissionCheck: (rbac) => rbac.canPostProperty,
      child: child,
      fallback: fallback,
    );
  }
}

/// Show only if user can manage agency
class CanManageAgency extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const CanManageAgency({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return PermissionBased(
      permissionCheck: (rbac) => rbac.canManageAgency,
      child: child,
      fallback: fallback,
    );
  }
}
