import 'package:flutter/foundation.dart';

/// Holds one screen section's asynchronously-loaded value, plus its loading and
/// failure flags.
///
/// Promoted from Phase 8's `SocialSection<T>` when the Network leaf screens
/// turned out to need exactly the same plumbing: each fetches one thing and
/// needs a value, a loading flag, a failure flag and dispose-safe notification.
/// One implementation rather than a second copy per module.
///
/// The failure contract matters: on error the previous value is kept and
/// [failed] is raised, so a screen can render an explicit error state. It never
/// substitutes an empty value, which would read as "you have nothing yet".
class AsyncSection<T> extends ChangeNotifier {
  AsyncSection(this._value);

  T _value;
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;

  T get value => _value;
  bool get loading => _loading;
  bool get failed => _failed;

  Future<void> load(Future<T> Function() fetch) async {
    _loading = true;
    _failed = false;
    _notify();

    try {
      _value = await fetch();
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
