import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/animations/page_transitions.dart';
import '../../providers/auth_provider.dart';
import '../stubs/coming_soon_screen.dart';

/// The once-per-user deferred load every module's leaf screen performs.
///
/// Factored into a mixin because all six repeat the identical lifecycle fix:
/// a section's `load()` raises its loading flag and notifies before its first
/// `await`, and `didChangeDependencies` runs inside the build phase, so calling
/// it directly marks the element dirty while it is still building and trips
/// `assert(!_dirty)`. Deferring to the end of the frame lets the first build
/// complete against the initial state.
///
/// Same fix as Profile, Messages and Subscription. Promoted out of the Social
/// module in Phase 9 so the Network leaves share the one copy.
mixin DeferredSectionLoader<T extends StatefulWidget> on State<T> {
  String? _loadedUserId;

  /// Internal de-dup key. Equal to [_loadedUserId] for every existing caller
  /// (default [reloadOnRoleChange] is false) — kept separate so
  /// [reloadSection] can still hand [loadSection] a bare user id even when
  /// [reloadOnRoleChange] folds the resolved role into this key instead.
  String? _loadedKey;

  /// The user the section was loaded for, so a Refresh control can re-run the
  /// same fetch without looking the id up again.
  String? get loadedUserId => _loadedUserId;

  /// Kick off the section's fetch. Called at most once per user id (or once
  /// per user+role, see [reloadOnRoleChange]), always after the current
  /// frame.
  void loadSection(String userId);

  /// Override to `true` for a section whose [loadSection] branches on
  /// `AuthProvider.userType` (builder vs. non-builder).
  ///
  /// `AuthProvider.userId` becomes non-null as soon as a session exists, but
  /// `userType` only lands later, once the `profiles` fetch resolves
  /// (`AuthProvider.isResolving` is true for that whole window). The default
  /// (`false`) guard here is keyed on `userId` alone, so a role-branching
  /// section that happens to run its very first load during that window gets
  /// permanently cached against the wrong branch — a genuine builder can load
  /// once as a non-builder and never reload, because `userId` alone never
  /// changes again.
  ///
  /// Setting this to `true` makes the guard also wait for
  /// `!AuthProvider.isResolving` and fold the resolved `userType` into the
  /// de-dup key, so a section reloads exactly once more if the role that was
  /// available on first load (there isn't one, since resolution isn't done)
  /// differs from the role that lands once resolution completes — while
  /// still loading at most once per stable `(userId, userType)` pair, same as
  /// before for every other caller.
  bool get reloadOnRoleChange => false;

  /// Re-runs [loadSection] for the already-resolved user. No-op before the
  /// first load.
  void reloadSection() {
    final userId = _loadedUserId;
    if (userId == null) return;
    loadSection(userId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) return;
    if (reloadOnRoleChange && auth.isResolving) return;

    final key = reloadOnRoleChange ? '$userId::${auth.userType ?? ''}' : userId;
    if (key == _loadedKey) return;
    _loadedKey = key;
    _loadedUserId = userId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      loadSection(userId);
    });
  }
}

/// Opens the shared placeholder for an action a phase does not implement, so a
/// control never dead-ends.
void openSectionPlaceholder(BuildContext context, String title) {
  Navigator.of(
    context,
  ).push(PremiumPageRoute(builder: (_) => ComingSoonScreen(title: title)));
}
