enum Intent {
  // Shared intents (all tiers)
  navigate,
  search_properties,
  compare_properties,
  confirm,
  unknown,
  ask_platform,

  // Unauthenticated only
  auth_required,
  suggest_signup,
  ask_about_platform,
  ask_property_info,

  // Authenticated — property
  create_listing,
  update_listing,
  delete_listing,
  publish_listing,
  save_draft,
  my_properties_summary,
  schedule_visit,
  add_images,

  // Authenticated — profile
  view_my_profile,
  update_profile,
  open_my_dashboard,
  open_manage_dashboard,
  show_notifications,
  show_my_network,
  open_chat,
  my_visit_bookings,
  post_content,
  delete_account,
  open_dashboard_action,

  // Authenticated — favorites
  show_saved_properties,

  // Authenticated — auth
  logout,
}

extension IntentExtension on Intent {
  static Intent fromString(String s) {
    for (final value in Intent.values) {
      if (value.name == s) return value;
    }
    return Intent.unknown;
  }
}
