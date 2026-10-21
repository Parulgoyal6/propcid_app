# RBAC & Profile Completion Implementation Guide

## Overview

This document explains the role-based access control (RBAC) and profile completion system implemented for the Flutter app.

## Architecture

### 1. RBAC Service (`lib/services/rbac_service.dart`)

Central service for all role-based access control logic.

**Key Methods:**
- `isBuyer` - Check if user is a buyer
- `isSeller` - Check if user is a seller
- `isBuilder` - Check if user is a builder
- `isBroker` - Check if user is a broker
- `isInfluencer` - Check if user is an influencer
- `canPostProperty` - Check if user can post properties
- `canManageAgency` - Check if user can manage agency
- `isValidRoleCombination()` - Validate role/type combinations
- `calculateProfileCompleteness()` - Calculate profile completion percentage
- `isProfileComplete()` - Check if profile is complete
- `getRequiredFields()` - Get required fields for a role
- `getProfileCompletionRoute()` - Get appropriate completion screen route

**Usage:**
```dart
final authProvider = context.read<AuthProvider>();
final rbacService = RBACService(authProvider);

if (rbacService.canPostProperty) {
  // Show post property button
}

if (rbacService.isBuilder) {
  // Show builder-specific features
}
```

### 2. Profile Completion Screens

#### Builder Profile Screen (`lib/screens/profile_completion/builder_profile_screen.dart`)
Collects builder-specific information:
- Company name
- RERA number
- Years of experience
- Website URL
- Company description
- Office address
- City, state, pincode
- Social media links

**Required fields for 100% completion:**
- company_name
- rera_number
- city
- state

#### Broker Profile Screen (`lib/screens/profile_completion/broker_profile_screen.dart`)
Collects broker-specific information:
- Agency name
- License number
- Years of experience
- Specialization
- Agency address
- City, state, pincode
- Operating cities (multi-select)
- Property types (multi-select)

**Required fields for 100% completion:**
- agency_name
- license_number
- city

#### Influencer Profile Screen (`lib/screens/profile_completion/influencer_profile_screen.dart`)
Collects influencer-specific information:
- Bio (min 50 characters)
- Website
- Social media links
- City, state

**Required fields for 100% completion:**
- bio
- city

### 3. Role Guard Widget (`lib/widgets/role_guard.dart`)

Reusable widgets for conditionally showing/hiding UI based on user role.

**Basic Usage:**
```dart
RoleGuard(
  allowedRoles: ['seller'],
  child: MyWidget(),
)
```

**Convenience Widgets:**
```dart
// Show only for buyers
BuyerOnly(child: MyWidget())

// Show only for sellers
SellerOnly(child: MyWidget())

// Show only for builders
BuilderOnly(child: MyWidget())

// Show only for brokers
BrokerOnly(child: MyWidget())

// Show only for influencers
InfluencerOnly(child: MyWidget())

// Hide from buyers
HideFromBuyers(child: MyWidget())

// Permission-based
CanPostProperty(child: MyWidget())
CanManageAgency(child: MyWidget())
```

### 4. Profile Completion Coordinator (`lib/services/profile_completion_coordinator.dart`)

Manages profile completeness checking and redirects users to appropriate completion screens.

**Key Methods:**
- `shouldCompleteProfile()` - Check if user needs to complete profile
- `navigateToCompletionScreen()` - Navigate to appropriate screen
- `checkAndRedirect()` - Check and redirect in one call
- `getProfileCompleteness()` - Get completion percentage
- `getMissingFields()` - Get list of missing required fields
- `showCompletionPrompt()` - Show completion prompt dialog

**Usage in Widgets:**
```dart
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> with ProfileCompletionChecker {
  @override
  void initState() {
    super.initState();
    // Check profile completion on init
    checkProfileCompletion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        onPressed: () => showProfileCompletionPrompt(),
        child: Text('Check Profile'),
      ),
    );
  }
}
```

**Usage Standalone:**
```dart
final authProvider = context.read<AuthProvider>();
final authService = AuthService();
final coordinator = ProfileCompletionCoordinator(authProvider, authService);

// Check and redirect
await coordinator.checkAndRedirect(context);

// Get completeness
final completeness = await coordinator.getProfileCompleteness();

// Show prompt
final shouldComplete = await coordinator.showCompletionPrompt(context);
if (shouldComplete) {
  await coordinator.navigateToCompletionScreen(context);
}
```

### 5. Updated Auth Service (`lib/services/auth_service.dart`)

Added new method:
- `updateProfileFields(userId, profileData)` - Update profile with additional fields

**Usage:**
```dart
final authService = AuthService();
await authService.updateProfileFields(
  user.id,
  {
    'company_name': 'My Company',
    'rera_number': '12345',
    'city': 'Mumbai',
    'state': 'Maharashtra',
  },
);
```

## Role Structure

### Buyer
- **user_role:** `buyer`
- **user_type:** `individual`
- **Profile completion:** Not required
- **Can:** View listings, search, save properties, create inquiries
- **Cannot:** Post properties, manage listings

### Seller - Builder
- **user_role:** `seller`
- **user_type:** `builder`
- **Profile completion:** Required
- **Can:** All buyer permissions + post properties, manage listings
- **Features:** Builder-specific dashboard, project management

### Seller - Broker
- **user_role:** `seller`
- **user_type:** `broker`
- **Profile completion:** Required
- **Can:** All buyer permissions + post properties, manage listings, manage agency
- **Features:** Agency management, team management

### Seller - Influencer
- **user_role:** `seller`
- **user_type:** `influencer`
- **Profile completion:** Required
- **Can:** All buyer permissions + post properties, manage listings
- **Features:** Social media integration, content creation

## Integration Steps

### 1. After Login - Check Profile Completion

In your home screen or main screen after login:

```dart
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ProfileCompletionChecker {
  @override
  void initState() {
    super.initState();
    // Check profile completion after login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkProfileCompletion();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Your home screen content
    );
  }
}
```

### 2. Hide/Show Features Based on Role

```dart
// In any widget
@override
Widget build(BuildContext context) {
  return Column(
    children: [
      // Show to everyone
      Text('Welcome!'),
      
      // Show only to sellers
      SellerOnly(
        child: ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/post-property'),
          child: Text('Post Property'),
        ),
      ),
      
      // Show only to builders
      BuilderOnly(
        child: ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/builder-dashboard'),
          child: Text('Builder Dashboard'),
        ),
      ),
      
      // Show only to brokers
      BrokerOnly(
        child: ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/agency-management'),
          child: Text('Manage Agency'),
        ),
      ),
    ],
  );
}
```

### 3. Profile Completion Prompt

Add a profile completion indicator in your profile screen:

```dart
class ProfileScreen extends StatefulWidget {
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with ProfileCompletionChecker {
  int _completeness = 0;

  @override
  void initState() {
    super.initState();
    _loadCompleteness();
  }

  Future<void> _loadCompleteness() async {
    final completeness = await getProfileCompleteness();
    setState(() => _completeness = completeness);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_completeness < 100)
            IconButton(
              icon: const Icon(Icons.warning),
              onPressed: () => showProfileCompletionPrompt(),
            ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: _completeness / 100),
          Text('Profile $_completeness% complete'),
          // Rest of profile content
        ],
      ),
    );
  }
}
```

## Database Schema

All profile data is stored in the existing `profiles` table. No new tables are created.

### Fields Used by RBAC System:

**Common Fields:**
- `user_id` (UUID)
- `display_name` (String)
- `email` (String)
- `user_role` (Enum: buyer, seller)
- `user_type` (Enum: individual, builder, broker, influencer)
- `profile_completeness` (Integer: 0-100)

**Builder Fields:**
- `company_name`
- `rera_number`
- `years_experience`
- `website_url`
- `company_description`
- `office_address`
- `city`
- `state`
- `pincode`
- `social_media`

**Broker Fields:**
- `agency_name`
- `license_number`
- `years_experience`
- `specialization` (Array)
- `agency_address`
- `city`
- `state`
- `pincode`
- `operating_cities` (Array)
- `property_types` (Array)

**Influencer Fields:**
- `bio`
- `website`
- `social_media`
- `city`
- `state`

## Routes Added

- `/builder-profile` - Builder profile completion screen
- `/broker-profile` - Broker profile completion screen
- `/influencer-profile` - Influencer profile completion screen

## Validation Rules

### Valid Role Combinations:
- buyer + individual ✓
- seller + builder ✓
- seller + broker ✓
- seller + influencer ✓

### Invalid Combinations:
- buyer + builder ✗
- buyer + broker ✗
- buyer + influencer ✗
- seller + individual ✗

## Testing Checklist

- [ ] Buyer signup works and sets role/type correctly
- [ ] Seller signup works and allows type selection
- [ ] Builder profile completion saves data correctly
- [ ] Broker profile completion saves data correctly
- [ ] Influencer profile completion saves data correctly
- [ ] Profile completeness calculates correctly
- [ ] Buyers are not redirected to profile completion
- [ ] Sellers are redirected to appropriate completion screen
- [ ] RoleGuard widgets hide/show UI correctly
- [ ] RBACService methods return correct values
- [ ] Profile completion prompt shows missing fields
- [ ] Navigation to completion screens works

## Troubleshooting

### Profile not redirecting after signup
- Ensure user is logged in before checking profile completion
- Check that `userRole` and `userType` are set correctly in AuthProvider
- Verify that profile data is being fetched from Supabase

### Profile completeness always 0%
- Check that required fields match the database column names exactly
- Verify that profile data is being fetched correctly
- Ensure `profile_completeness` field is being updated in the database

### RoleGuard not hiding/showing correctly
- Verify that AuthProvider is properly initialized
- Check that `userRole` and `userType` are not null
- Ensure the widget is within a Provider tree

### Profile completion screen not saving data
- Check that user is logged in (`currentUser` is not null)
- Verify that `updateProfileFields` is being called with correct user ID
- Check Supabase RLS policies allow profile updates

## Notes

- All changes are backward compatible
- Existing buyers and sellers continue to work
- No database schema changes required
- Uses existing Supabase tables
- Follows existing app architecture and theme
- Uses Provider for state management
