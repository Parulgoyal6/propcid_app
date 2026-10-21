// core/navigation/post_property_route_gate.dart
//
// Role gates for the three content-creation wizards, at the route rather than in
// the components that link to them.
//
// WHY CENTRALLY
// -------------
// An audit found **eleven** places that navigate to `/post-property`. Six were
// reachable by a builder with no role check at all, and three of those are shared,
// role-blind components:
//
//   * `BottomNavBar`'s centre "+" button — no role awareness anywhere in that
//     file, and it appears on thirteen screens including the builder's own
//     dashboard;
//   * Home's "Post Property" quick action — a `static const` tile;
//   * the Profile screen's "Add Property" tile in both Create Content and My
//     Content — the screen computes `isBuilder` but uses it only for a different
//     control.
//
// Making each of those role-aware would mean threading `AuthProvider` through
// three shared widgets and keeping them in step forever. Both wizards funnel
// through `onGenerateRoute`, so one gate per route covers every caller including
// the voice agent, which reaches them by path.
//
// ALL THREE GATES LIVE HERE
// -------------------------
// They are three faces of one rule — `permissions.dart`'s `canCreate`, which
// already says `property → userType != 'builder'`, `project → userType ==
// 'builder'` and `video → userType == 'influencer'`. Splitting them across files
// would let one drift.
//
// WHAT IS NOT GATED
// -----------------
// Edit mode, ever. Reopening an existing row is not creating one, and a builder
// with legacy `properties` rows must be able to edit them — `MyListingsSection`
// depends on it. Note the edit callers construct `PostPropertyScreen` directly
// through a `MaterialPageRoute` and never touch this route, so the edit branch
// below is a guard for a future caller rather than a live path.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/project_model.dart';
import '../../providers/auth_provider.dart';
import '../../screens/add_project/add_project_screen.dart';
import '../../screens/influencer/influencer_video_form_screen.dart';
import '../../screens/post_property/post_property_screen.dart';
import '../../services/property_service.dart' show PropertyEditBundle;
import '../../voice_agent/tools/permissions.dart';
import '../theme/app_colors.dart';

/// Shown while `AuthProvider.userType` is still resolving.
///
/// Not cosmetic. `userType` is populated asynchronously by
/// `AuthProvider._fetchUserProfile()`, and `canCreate(property, null)` evaluates
/// `null != 'builder'` — **true** — so a builder who taps the "+" button in the
/// first frames after launch would sail straight past the gate. Waiting is what
/// `ManageDashboardDispatcher` already does for the same reason.
class _ResolvingRole extends StatelessWidget {
  const _ResolvingRole();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: Center(child: CircularProgressIndicator()),
  );
}

/// `/post-property` — the property listing wizard.
///
/// A builder is sent to the project wizard instead of being shown an error: they
/// asked to create something, and the thing they can create is a project. The
/// screen is **returned**, not pushed, so there is no frame of the wrong wizard
/// and Back still pops once.
class PostPropertyRouteGate extends StatelessWidget {
  const PostPropertyRouteGate({
    super.key,
    this.editPropertyId,
    this.editBundle,
  });

  /// Present for an edit. Both are needed — `PostPropertyScreen` only enters edit
  /// mode when it has the id *and* the bundle.
  final String? editPropertyId;
  final PropertyEditBundle? editBundle;

  @override
  Widget build(BuildContext context) {
    // Editing is never gated, and is decided before the role is even read.
    if (editPropertyId != null && editBundle != null) {
      return PostPropertyScreen(
        editPropertyId: editPropertyId,
        editBundle: editBundle,
      );
    }

    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn && auth.userType == null) return const _ResolvingRole();

    if (!canCreate(CreatableContent.property, auth.userType)) {
      return const AddProjectScreen();
    }
    return const PostPropertyScreen();
  }
}

/// `/add-project` — the builder project wizard.
///
/// The mirror of the gate above, and not optional: the voice agent's route index
/// now resolves "create a project" to this path for any authenticated user, and
/// `AddProjectScreen` has no role check of its own. RLS would not stop a broker
/// either — `builder_projects` INSERT is `WITH CHECK (builder_id = auth.uid())`
/// and a broker inserting their own id satisfies it. Without this gate, adding
/// that route entry would hand every role a way into `builder_projects`.
class AddProjectRouteGate extends StatelessWidget {
  const AddProjectRouteGate({super.key, this.editingProject});

  /// Present for an edit.
  final ProjectModel? editingProject;

  @override
  Widget build(BuildContext context) {
    if (editingProject != null) {
      return AddProjectScreen(editingProject: editingProject);
    }

    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn && auth.userType == null) return const _ResolvingRole();

    if (!canCreate(CreatableContent.project, auth.userType)) {
      // A non-builder who wanted to create something gets the wizard for what
      // they can create, symmetrically with the gate above.
      return const PostPropertyScreen();
    }
    return const AddProjectScreen();
  }
}

/// `/influencer-video` — the influencer video form, in create mode.
///
/// Added with Spec A, when `post_content(video)` and a `route_index` entry made
/// this path reachable by intent for any authenticated user. Unlike the two gates
/// above, RLS would in fact stop a wrong-role write here: `influencer_videos`'
/// policy is `auth.uid() = user_id AND EXISTS (SELECT 1 FROM profiles WHERE
/// user_id = auth.uid() AND user_type = 'influencer')`. But it would stop it at the
/// *end* — after the user filled in the form and uploaded a video to storage. The
/// gate turns a wasted upload and an opaque failure into landing on the right
/// wizard in the first place.
///
/// Editing is not routed through here: `MyVideosSection` pushes the screen
/// directly with the row, the same way `MyListingsSection` pushes the listing
/// wizard with its edit bundle. There is deliberately no edit branch to bypass.
class InfluencerVideoRouteGate extends StatelessWidget {
  const InfluencerVideoRouteGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn && auth.userType == null) return const _ResolvingRole();

    if (!canCreate(CreatableContent.video, auth.userType)) {
      // Same courtesy the other two gates extend: someone who asked to create
      // something gets the wizard for what they *can* create. A builder cannot
      // create a property either, so the fallback has to branch rather than
      // assume PostPropertyScreen.
      return canCreate(CreatableContent.project, auth.userType)
          ? const AddProjectScreen()
          : const PostPropertyScreen();
    }
    return const InfluencerVideoFormScreen();
  }
}
