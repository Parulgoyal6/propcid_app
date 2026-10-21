/// One checklist entry in the profile-completion calculation.
class ProfileCompletionItem {
  final String label;
  final String field;
  final bool completed;

  const ProfileCompletionItem({
    required this.label,
    required this.field,
    required this.completed,
  });
}

/// Result of evaluating a profile against its role's checklist.
class ProfileCompletion {
  final List<ProfileCompletionItem> items;

  const ProfileCompletion(this.items);

  static const ProfileCompletion empty = ProfileCompletion([]);

  int get completedCount => items.where((i) => i.completed).length;

  /// 0–100, rounded — matches React's
  /// `Math.round((done / completionItems.length) * 100)`.
  int get percentage {
    if (items.isEmpty) return 0;
    return ((completedCount / items.length) * 100).round();
  }

  bool get isDone => percentage >= 100;

  /// First unfinished entry, used to render the prototype's
  /// "Add … to reach 100%" hint. Null once complete.
  ProfileCompletionItem? get nextItem {
    for (final item in items) {
      if (!item.completed) return item;
    }
    return null;
  }
}

/// Pure client-side port of `getCompletionItems()` in
/// features/profile/ProfileCompletionWidget.tsx — see blueprint §9.
///
/// No new table, no new query: it reads the `profiles` row [AuthProvider]
/// already fetches. The four "core" entries are shared by every role, then
/// each role appends its own. Field checks mirror React's truthiness tests
/// exactly, including the fallbacks (`bio || company_description`,
/// `city || work_city`, `rera_number || license_number`) and the rule that a
/// display name containing "@" does not count as a real name.
ProfileCompletion calculateProfileCompletion(Map<String, dynamic>? profile) {
  if (profile == null) return ProfileCompletion.empty;

  final social = _asMap(profile['social_media']);

  bool has(String key) => _isPresent(profile[key]);
  bool hasSocial(String key) => _isPresent(social[key]);

  final displayName = profile['display_name'];
  final core = <ProfileCompletionItem>[
    ProfileCompletionItem(
      label: 'Profile photo',
      field: 'avatar',
      completed: has('avatar_url'),
    ),
    ProfileCompletionItem(
      label: 'Full name',
      field: 'name',
      completed:
          displayName is String &&
          displayName.isNotEmpty &&
          !displayName.contains('@'),
    ),
    ProfileCompletionItem(
      label: 'Phone number',
      field: 'phone',
      completed: has('phone'),
    ),
    ProfileCompletionItem(
      label: 'Bio / about',
      field: 'bio',
      completed: has('bio') || has('company_description'),
    ),
  ];

  switch ((profile['user_type'] as String?)?.toLowerCase()) {
    case 'broker':
      return ProfileCompletion([
        ...core,
        ProfileCompletionItem(
          label: 'Office address',
          field: 'address',
          completed: has('office_address'),
        ),
        ProfileCompletionItem(
          label: 'City / area',
          field: 'city',
          completed: has('city') || has('work_city'),
        ),
        ProfileCompletionItem(
          label: 'Business email',
          field: 'email',
          completed: has('email'),
        ),
        ProfileCompletionItem(
          label: 'RERA registration',
          field: 'rera',
          completed: has('rera_number') || has('license_number'),
        ),
        ProfileCompletionItem(
          label: 'Social link',
          field: 'social',
          completed:
              hasSocial('instagram') ||
              hasSocial('instagram_username') ||
              hasSocial('facebook') ||
              hasSocial('facebook_page_link') ||
              hasSocial('youtube') ||
              hasSocial('youtube_channel_link') ||
              hasSocial('linkedin') ||
              hasSocial('linkedin_profile_url'),
        ),
      ]);

    case 'builder':
      return ProfileCompletion([
        ...core,
        ProfileCompletionItem(
          label: 'Company name',
          field: 'company',
          completed: has('company_name'),
        ),
        ProfileCompletionItem(
          label: 'Office address',
          field: 'address',
          completed: has('office_address'),
        ),
        ProfileCompletionItem(
          label: 'Business email',
          field: 'email',
          completed: has('email'),
        ),
        ProfileCompletionItem(
          label: 'RERA registration',
          field: 'rera',
          completed: has('rera_number') || has('license_number'),
        ),
        ProfileCompletionItem(
          label: 'Social link',
          field: 'social',
          completed:
              hasSocial('instagram') ||
              hasSocial('facebook_page_link') ||
              hasSocial('youtube_channel_link') ||
              hasSocial('linkedin_profile_url'),
        ),
      ]);

    case 'influencer':
      return ProfileCompletion([
        ...core,
        ProfileCompletionItem(
          label: 'Influencer category',
          field: 'category',
          completed: hasSocial('category'),
        ),
        ProfileCompletionItem(
          label: 'Primary platform',
          field: 'platform',
          completed:
              hasSocial('primary_platform') ||
              hasSocial('primary_content_platform'),
        ),
        ProfileCompletionItem(
          label: 'Platform link',
          field: 'social',
          completed:
              hasSocial('instagram') ||
              hasSocial('instagram_username') ||
              hasSocial('youtube') ||
              hasSocial('youtube_channel_link'),
        ),
        ProfileCompletionItem(
          label: 'Verification doc',
          field: 'doc',
          completed: hasSocial('aadhaar_card_url') || hasSocial('pan_card_url'),
        ),
      ]);

    default:
      // individual / unknown
      return ProfileCompletion([
        ...core,
        ProfileCompletionItem(
          label: 'Gender',
          field: 'gender',
          completed: hasSocial('gender'),
        ),
        ProfileCompletionItem(
          label: 'Date of birth',
          field: 'dob',
          completed: hasSocial('dob'),
        ),
        ProfileCompletionItem(
          label: 'State / location',
          field: 'state',
          completed: has('state'),
        ),
        ProfileCompletionItem(
          label: 'Business email',
          field: 'email',
          completed: has('email'),
        ),
      ]);
  }
}

/// JS truthiness for the values these columns actually hold: null, empty
/// string, `false` and `0` are all falsy in React's `!!value` checks.
bool _isPresent(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}
