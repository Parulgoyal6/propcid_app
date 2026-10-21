import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

/// Never-null string. Mirrors the portal's `dbText` (`dbSafe.ts:25-29`) so a
/// field left blank lands as `''`, not `NULL`.
String _dbText(String? value, [String fallback = '']) {
  final v = value?.trim() ?? '';
  return v.isEmpty ? fallback : v;
}

/// Never-null integer. Mirrors `dbInt` (`dbSafe.ts:39-42`).
int _dbInt(String? value, [int fallback = 0]) {
  return int.tryParse((value ?? '').trim()) ?? fallback;
}

/// Never-null array with blank entries dropped. Mirrors `dbArray` (`dbSafe.ts:53-56`).
List<String> _dbArray(List<String>? value) {
  if (value == null) return const [];
  return value.where((e) => e.trim().isNotEmpty).toList();
}

/// Service responsible for reading and writing user profile data
/// to the `profiles` table in Supabase.
class ProfileService {
  final AuthService _authService = AuthService();

  /// Saves a Builder profile for the currently authenticated user.
  ///
  /// Upserts `profiles` directly instead of going through
  /// `AuthService.updateProfileFields` (a plain `.update()`) — this mirrors
  /// `BuilderRegistration.tsx:944-1000` exactly, including its own comment:
  /// a bare UPDATE silently matches zero rows when the `handle_new_user`
  /// trigger has not yet created the row for a brand-new signup, and the
  /// builder role would never be saved.
  ///
  /// [data]'s keys mirror the portal's `BuilderFormData` field-for-field —
  /// see the builder registration screen for the exact keys it sends. This is
  /// a transcription of the portal's `handleSubmit` payload, not a
  /// reinterpretation of it.
  ///
  /// Throws an [Exception] if the user is not authenticated or if the write
  /// fails for any reason.
  Future<void> saveBuilderProfile(Map<String, dynamic> data) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found. Please log in again.');
    }

    // A JWT cached from before an admin deleted this account can still look
    // valid locally — the upsert below would otherwise proceed and hit
    // profiles_user_id_fkey. Confirmed live before this identity-owned write.
    await _authService.requireLiveUser(user.id);

    String? str(String key) => data[key] as String?;
    List<String>? list(String key) => data[key] as List<String>?;

    final companyName = _dbText(str('companyName'));
    final officeAddress = _dbText(str('officeAddress'));
    final city = _dbText(str('city'));
    final reraNumber = _dbText(str('reraNumber'));
    final aboutCompany = _dbText(str('aboutCompany'));
    final websiteUrl = _dbText(str('websiteUrl'));
    final expertise = _dbArray(list('areasOfExpertise'));
    final fullMobile =
        '${_dbText(str('countryCode'), '+91')}${_dbText(str('mobileNumber'))}';
    final altMobileDigits = _dbText(str('alternateMobileNumber'));
    final alternateMobile = altMobileDigits.isEmpty
        ? null
        : '${_dbText(str('alternateCountryCode'), '+91')}$altMobileDigits';

    final payload = <String, dynamic>{
      'user_id': user.id,
      'display_name': companyName,
      'company_name': companyName,
      'agency_name': companyName,
      'user_type': 'builder',
      'rera_number': reraNumber,
      'license_number': reraNumber,
      'years_experience': _dbInt(str('yearsOfExperience')),
      'years_of_experience': _dbInt(str('yearsOfExperience')),
      'company_description': aboutCompany,
      'bio': aboutCompany,
      'specialization': expertise,
      'office_address': officeAddress,
      'agency_address': officeAddress,
      'city': city,
      'work_city': city,
      'state': _dbText(str('state')),
      'pincode': _dbText(str('pincode')),
      'phone': fullMobile,
      'mobile_number': fullMobile,
      'email': _dbText(str('email')),
      'website_url': websiteUrl,
      'website': websiteUrl,
      'avatar_url': _dbText(str('avatarUrl')),
      'company_logo_url': _dbText(str('companyLogoUrl')),
      'username': _dbText(str('username')),
      'social_media': {
        'facebook': _dbText(str('facebookUrl')),
        'instagram': _dbText(str('instagramUrl')),
        'linkedin': _dbText(str('linkedinUrl')),
        'youtube': _dbText(str('youtubeUrl')),
        'whatsapp': _dbText(str('whatsappNumber')),
        'telegram': _dbText(str('telegramUrl')),
        'company_type': _dbText(str('companyType')),
        'gst_number': _dbText(str('gstNumber')),
        'pan_number': _dbText(str('panNumber')),
        'rera_certificate_url': _dbText(str('reraCertificateUrl')),
        'gst_certificate_url': _dbText(str('gstCertificateUrl')),
        'pan_card_url': _dbText(str('panCardUrl')),
        'registration_proof_url': _dbText(str('registrationProofUrl')),
        'alternate_mobile': alternateMobile,
        'landmark': _dbText(str('landmark')),
        'gender': _dbText(str('gender')),
        'dob': _dbText(str('dob')),
        'areas_of_expertise': expertise,
        'languages_known': _dbArray(list('languagesKnown')),
      },
      'approval_status': 'pending',
      'profile_complete': true,
      'is_active': true,
    };

    try {
      await Supabase.instance.client
          .from('profiles')
          .upsert(payload, onConflict: 'user_id');
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error while saving builder profile: ${e.message}',
      );
    } on AuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error while saving builder profile: $e');
    }
  }

  /// Saves a Broker profile for the currently authenticated user.
  ///
  /// Mirrors `BrokerRegistration.tsx:857-943`'s two upserts exactly:
  /// `broker_profiles` first, then `profiles` — both `.upsert()`, not
  /// `.update()`, for the same reason as the builder flow (a brand-new
  /// signup's row may not exist yet).
  ///
  /// Four `social_media` keys — `price_range_min/max`, `buy_rent_both`,
  /// `commission_details`, `availability_timing_start/end` — and
  /// `broker_profiles.property_types`/`operating_cities` are written with
  /// the portal's fixed initial values ('0', 'Both', '', '09:00', '18:00',
  /// `[]`, `[]`). The portal's own wizard has no step that ever changes
  /// them — `BrokerFormData`'s "Step 4: Service Details" fields are declared
  /// and submitted but never rendered — so this is a byte-for-byte
  /// transcription of what every broker row actually gets today, not an
  /// omission.
  ///
  /// [data]'s keys mirror the portal's `BrokerFormData` field-for-field.
  Future<void> saveBrokerProfile(Map<String, dynamic> data) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found. Please log in again.');
    }

    // A JWT cached from before an admin deleted this account can still look
    // valid locally — the upsert below would otherwise proceed and hit
    // profiles_user_id_fkey. Confirmed live before this identity-owned write.
    await _authService.requireLiveUser(user.id);

    String? str(String key) => data[key] as String?;
    List<String>? list(String key) => data[key] as List<String>?;

    final fullName = _dbText(str('fullName'));
    final brokerFirmName = _dbText(str('brokerFirmName'));
    final reraNumber = _dbText(str('reraNumber'));
    final aboutBroker = _dbText(str('aboutBroker'));
    final officeAddress = _dbText(str('officeAddress'));
    final city = _dbText(str('city'));
    final state = _dbText(str('state'));
    final pincode = _dbText(str('pincode'));
    final email = _dbText(str('email'));
    final websiteUrl = _dbText(str('websiteUrl'));
    final avatarUrl = _dbText(str('avatarUrl'));
    final expertise = _dbArray(list('areasOfExpertise'));
    final yearsOfExperience = _dbInt(str('yearsOfExperience'));
    final fullMobile =
        '${_dbText(str('countryCode'), '+91')}${_dbText(str('mobileNumber'))}';
    final altMobileDigits = _dbText(str('alternateMobileNumber'));
    final alternateMobile = altMobileDigits.isEmpty
        ? null
        : '${_dbText(str('alternateCountryCode'), '+91')}$altMobileDigits';

    try {
      await Supabase.instance.client.from('broker_profiles').upsert({
        'user_id': user.id,
        'full_name': fullName,
        'rera_number': reraNumber,
        'license_number': reraNumber,
        'agency_name': brokerFirmName,
        'years_of_experience': yearsOfExperience,
        'company_description': aboutBroker,
        'office_address': officeAddress,
        'city': city,
        'state': state,
        'pincode': pincode,
        'mobile_number': fullMobile,
        'email': email,
        'website': websiteUrl,
        'property_types': const <String>[],
        'operating_cities': const <String>[],
        'approval_status': 'pending',
      }, onConflict: 'user_id');

      await Supabase.instance.client.from('profiles').upsert({
        'user_id': user.id,
        'display_name': fullName,
        'user_type': 'broker',
        'company_name': brokerFirmName,
        'rera_number': reraNumber,
        'license_number': reraNumber,
        'years_experience': yearsOfExperience,
        'years_of_experience': yearsOfExperience,
        'company_description': aboutBroker,
        'bio': aboutBroker,
        'phone': fullMobile,
        'mobile_number': fullMobile,
        'email': email,
        'city': city,
        'work_city': city,
        'state': state,
        'office_address': officeAddress,
        'agency_address': officeAddress,
        'agency_name': brokerFirmName,
        'specialization': expertise,
        'pincode': pincode,
        'website_url': websiteUrl,
        'website': websiteUrl,
        'avatar_url': avatarUrl,
        'company_logo_url': avatarUrl,
        'username': _dbText(str('username')),
        'social_media': {
          'website_url': websiteUrl,
          'whatsapp': _dbText(str('whatsappNumber')),
          'facebook': _dbText(str('facebookUrl')),
          'instagram': _dbText(str('instagramUrl')),
          'linkedin': _dbText(str('linkedinUrl')),
          'youtube': _dbText(str('youtubeUrl')),
          'telegram': _dbText(str('telegramUsername')),
          'gender': _dbText(str('gender')),
          'dob': _dbText(str('dob')),
          'alt_mobile_number': alternateMobile,
          'broker_type': _dbText(str('brokerType')),
          'areas_of_expertise': expertise,
          'languages_known': _dbArray(list('languagesKnown')),
          'price_range_min': '0',
          'price_range_max': '0',
          'buy_rent_both': 'Both',
          'commission_details': '',
          'availability_timing_start': '09:00',
          'availability_timing_end': '18:00',
          'aadhaar_card_url': _dbText(str('aadhaarCardUrl')),
          'pan_card_url': _dbText(str('panCardUrl')),
          'rera_certificate_url': _dbText(str('reraCertificateUrl')),
          'landmark': _dbText(str('landmark')),
        },
        'approval_status': 'pending',
        'profile_complete': true,
        'is_active': true,
      }, onConflict: 'user_id');
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error while saving broker profile: ${e.message}',
      );
    } on AuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error while saving broker profile: $e');
    }
  }

  /// Saves an Influencer profile for the currently authenticated user.
  /// Influencer data is stored entirely on the `profiles` table (no separate
  /// influencer_profiles table), mirroring `InfluencerRegistration.tsx:902-959`.
  ///
  /// Upserts, not updates, for the same reason as the other two registration
  /// flows: a brand-new signup's row may not exist yet.
  ///
  /// `social_media.portfolio_links`/`previous_brand_collaborations` and
  /// `areas_covered` are written as `[]` — the portal declares, restores from
  /// draft, and submits these three, but `renderStepContent` has no JSX for
  /// any of them, so no influencer row has ever had a non-empty value here.
  /// `latitude`/`longitude` come from `data['latitude']`/`data['longitude']`
  /// (the map picker's last tap), falling back to `0` when the user never
  /// tapped the map — same fallback the portal's own `dbNum` uses.
  ///
  /// [data]'s keys mirror the portal's `InfluencerFormData` field-for-field.
  Future<void> saveInfluencerProfile(Map<String, dynamic> data) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found. Please log in again.');
    }

    // A JWT cached from before an admin deleted this account can still look
    // valid locally — the upsert below would otherwise proceed and hit
    // profiles_user_id_fkey. Confirmed live before this identity-owned write.
    await _authService.requireLiveUser(user.id);

    String? str(String key) => data[key] as String?;
    List<String>? list(String key) => data[key] as List<String>?;

    final fullName = _dbText(str('fullName'));
    final city = _dbText(str('city'));
    final officeAddress = _dbText(str('officeAddress'));
    final bio = _dbText(str('bio'));
    final category = _dbText(str('category'));
    final websiteUrl = _dbText(str('websiteUrl'));
    final avatarUrl = _dbText(str('avatarUrl'));
    final yearsOfExperience = str('yearsOfExperience');
    final fullMobile =
        '${_dbText(str('countryCode'), '+91')}${_dbText(str('mobileNumber'))}';
    final altMobileDigits = _dbText(str('alternateMobileNumber'));
    final alternateMobile = altMobileDigits.isEmpty
        ? null
        : '${_dbText(str('alternateCountryCode'), '+91')}$altMobileDigits';

    try {
      await Supabase.instance.client.from('profiles').upsert({
        'user_id': user.id,
        'display_name': fullName,
        'user_type': 'influencer',
        'phone': fullMobile,
        'mobile_number': fullMobile,
        'email': _dbText(str('email')),
        'city': city,
        'work_city': city,
        'state': _dbText(str('state')),
        'office_address': officeAddress,
        'agency_address': officeAddress,
        'pincode': _dbText(str('pincode')),
        'bio': bio,
        'company_description': bio,
        'specialization': category.isEmpty ? const <String>[] : [category],
        'years_experience': _dbInt(yearsOfExperience),
        'years_of_experience': _dbInt(yearsOfExperience),
        'avatar_url': avatarUrl,
        'website': websiteUrl,
        'website_url': websiteUrl,
        'username': _dbText(str('username')),
        'approval_status': 'pending',
        'profile_complete': true,
        'is_active': true,
        'social_media': {
          'creator_name': _dbText(str('username')),
          'alternate_mobile': alternateMobile,
          'gender': _dbText(str('gender')),
          'dob': _dbText(str('dob')),
          'category': category,
          'languages_known': _dbArray(list('languagesKnown')),
          'areas_covered': const <String>[],
          'years_of_experience': _dbText(yearsOfExperience, '0'),
          'audience_type': _dbText(str('audienceType')),
          'primary_content_platform': _dbText(str('primaryContentPlatform')),
          'landmark': _dbText(str('landmark')),
          'latitude': (data['latitude'] as double?) ?? 0,
          'longitude': (data['longitude'] as double?) ?? 0,
          'instagram_username': _dbText(str('instagramUsername')),
          'instagram_followers': _dbText(str('instagramFollowers'), '0'),
          'youtube_channel_link': _dbText(str('youtubeChannelLink')),
          'youtube_subscribers': _dbText(str('youtubeSubscribers'), '0'),
          'facebook_page_link': _dbText(str('facebookPageLink')),
          'linkedin_profile_url': _dbText(str('linkedinProfileUrl')),
          'twitter_profile_url': _dbText(str('twitterProfileUrl')),
          'telegram_channel_link': _dbText(str('telegramChannelLink')),
          'whatsapp_number': _dbText(str('whatsappNumber')),
          'content_types': _dbArray(list('contentTypes')),
          'preferred_promotion_types': _dbArray(
            list('preferredPromotionTypes'),
          ),
          'portfolio_links': const <String>[],
          'previous_brand_collaborations': const <String>[],
          'aadhaar_card_url': _dbText(str('aadhaarCardUrl')),
          'pan_card_url': _dbText(str('panCardUrl')),
        },
      }, onConflict: 'user_id');
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error while saving influencer profile: ${e.message}',
      );
    } on AuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error while saving influencer profile: $e');
    }
  }
}
