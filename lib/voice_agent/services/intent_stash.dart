/// In-memory singleton replacing JavaScript's sessionStorage.setItem('va_*') pattern.
/// Cleared on sign-out by VoiceAgentProvider.
class IntentStash {
  static final Map<String, dynamic> _data = {};

  static void set(String key, dynamic value) => _data[key] = value;

  static T? get<T>(String key) {
    final val = _data[key];
    if (val is T) return val;
    return null;
  }

  static void remove(String key) => _data.remove(key);

  static void clear() => _data.clear();
}
