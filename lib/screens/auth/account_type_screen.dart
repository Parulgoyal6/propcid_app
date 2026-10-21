import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/premium_button.dart';
import '../../providers/auth_provider.dart';

/// The Full-Name-+-User-Type setup step — the portal counterpart is
/// `ProfileCompletion.tsx`'s base form (full name + role select, before any
/// role-specific sub-form). Reached whenever `AuthProvider.destination` is
/// `needsAccountType` or `profileMissing`: a brand-new confirmed-email,
/// Google, or phone-OTP sign-in with no `user_type` yet, or a legacy
/// authenticated user with no `profiles` row at all.
///
/// On submit, `AuthProvider.completeAccountSetup` narrowly upserts
/// `user_id`/`display_name`/`user_type`/`profile_complete: false` (never
/// `user_role`) and refreshes — this provider's own destination then
/// recomputes and its single navigation owner takes the user to the
/// matching registration screen. This screen never navigates itself.
class AccountTypeScreen extends StatefulWidget {
  final String userId;
  const AccountTypeScreen({required this.userId, super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  // Letters, spaces, hyphens and apostrophes only — no digits or other symbols.
  static final RegExp _namePattern = RegExp(r"^[a-zA-Z\s'-]+$");

  static const List<_TypeOption> _options = [
    _TypeOption(
      type: 'individual',
      icon: Icons.person_rounded,
      label: 'Individual',
      subtitle: 'Browse and save properties',
      color: Color(0xFF616161),
    ),
    _TypeOption(
      type: 'builder',
      icon: Icons.business_rounded,
      label: 'Builder',
      subtitle: 'List and manage your projects',
      // Matches the Builder badge colour used elsewhere (profile_role.dart).
      color: Color(0xFF3B82F6),
    ),
    _TypeOption(
      type: 'broker',
      icon: Icons.home_work_rounded,
      label: 'Broker',
      subtitle: 'List properties and find clients',
      color: Color(0xFF009688),
    ),
    _TypeOption(
      type: 'influencer',
      icon: Icons.play_circle_fill_rounded,
      label: 'Influencer',
      subtitle: 'Promote projects and earn',
      // Matches the Influencer badge colour used elsewhere (profile_role.dart,
      // the "Influencers" category tile).
      color: Color(0xFFDB2777),
    ),
  ];

  late final TextEditingController _nameCtrl;
  String? _selectedType;
  bool _isSaving = false;
  String? _nameError;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    final displayName = context.read<AuthProvider>().userName;
    // A name that "looks like an email" is a placeholder, not a real name
    // (e.g. a phone signup's auto-generated `u<phone>@propcid.app`) — same
    // guard `IndividualProfileDetailsScreen` uses for the same reason.
    final prefill = displayName.contains('@') ? '' : displayName;
    _nameCtrl = TextEditingController(text: prefill);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty
          ? 'Please enter your name.'
          : !_namePattern.hasMatch(name)
          ? 'Name can only contain letters, spaces and hyphens.'
          : null;
      _typeError = _selectedType == null
          ? 'Please select an account type.'
          : null;
    });
    if (_nameError != null || _typeError != null) return;

    setState(() => _isSaving = true);
    final error = await context.read<AuthProvider>().completeAccountSetup(
      fullName: name,
      userType: _selectedType!,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    // Success: AuthProvider's own destination has already recomputed and its
    // single navigation owner is taking the user to the matching
    // registration screen — nothing further to do here. _isSaving is left
    // true deliberately; this widget is about to be removed from the tree.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                Text(
                  'Tell us about yourself',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This helps us personalise your experience.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 28),
                Text(
                  'Full Name',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  // A name has no legitimate reason to contain digits.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Your full name',
                    errorText: _nameError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'What best describes you?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                if (_typeError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _typeError!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ],
                const SizedBox(height: 8),
                ..._options.map(
                  (option) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TypeTile(
                      option: option,
                      selected: _selectedType == option.type,
                      enabled: !_isSaving,
                      onTap: () => setState(() => _selectedType = option.type),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PremiumButton(
                  label: 'Continue',
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _submit,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeOption {
  final String type;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _TypeOption({
    required this.type,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });
}

class _TypeTile extends StatelessWidget {
  final _TypeOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _TypeTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? option.color : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(option.icon, color: option.color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? option.color : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
