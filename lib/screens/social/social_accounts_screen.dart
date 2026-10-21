import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/social_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/social_provider.dart';
import '../../services/meta_oauth_service.dart';
import '../../services/social_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import 'widgets/social_screen_shell.dart';
import '../shared/section_loader.dart';

/// Social ▸ Accounts — the design's `isSocialAccounts` screen.
///
/// Shows whether a Facebook Page and an Instagram Business account are
/// linked (read from the token-free `social_accounts_safe` view), and now
/// actually connects one: opens Facebook's OAuth dialog in the external
/// browser, waits for the `propcid://meta-callback` redirect
/// ([MetaOAuthService.connect]), then lets the user pick which Page (and,
/// once ads-capable, which ad account) to link — the same
/// exchange/select-page/select-ad-account Edge Functions the portal calls.
class SocialAccountsScreen extends StatelessWidget {
  const SocialAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialAccountSection(),
      child: const _AccountsView(),
    );
  }
}

class _AccountsView extends StatefulWidget {
  const _AccountsView();

  @override
  State<_AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<_AccountsView>
    with DeferredSectionLoader<_AccountsView> {
  final _oauth = MetaOAuthService();
  final _service = SocialService();
  bool _busy = false;

  @override
  void loadSection(String userId) =>
      context.read<SocialAccountSection>().loadFor(userId);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _connect() async {
    if (!_oauth.isConfigured) {
      _showError('Social connections are not set up on this build yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      final pages = await _oauth.connect();
      if (!mounted) return;
      if (pages.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('No Facebook Page found'),
            content: const Text(
              "You need a Facebook Page to connect. Create one at "
              "facebook.com/pages/create, then reconnect here.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      final pageId = await _showPagePicker(pages);
      if (pageId == null) return;
      await _oauth.selectPage(pageId);
      if (!mounted) return;
      // Best-effort, matching the portal's post-connect behaviour.
      try {
        await _service.syncFollowers(loadedUserId!);
      } catch (_) {}
      reloadSection();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showPagePicker(List<AvailablePage> pages) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select a Facebook Page'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: pages.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final page = pages[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: page.picture != null
                      ? NetworkImage(page.picture!)
                      : null,
                  child: page.picture == null
                      ? const Icon(Icons.facebook)
                      : null,
                ),
                title: Text(page.name),
                subtitle: page.hasInstagram
                    ? Text('Instagram: @${page.instagramUsername}')
                    : const Text('No Instagram Business account linked'),
                onTap: () => Navigator.pop(dialogContext, page.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Meta account?'),
        content: const Text(
          "You'll need to reconnect to publish or run campaigns again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _oauth.disconnect();
      reloadSection();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshStats() async {
    setState(() => _busy = true);
    try {
      await _service.syncFollowers(loadedUserId!);
      reloadSection();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoRefresh(bool value) async {
    setState(() => _busy = true);
    try {
      await _service.setAutoRefresh(loadedUserId!, value);
      reloadSection();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseAdAccount() async {
    setState(() => _busy = true);
    List<MetaAdAccount> accounts = const [];
    try {
      accounts = await _service.listAdAccounts();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (accounts.isEmpty) {
      _showError('No ad accounts found for this Facebook login.');
      return;
    }

    final accountId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select an ad account'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = accounts[i];
              return ListTile(
                title: Text(a.name),
                subtitle: Text('${a.currency ?? ''} · ${a.statusLabel}'),
                onTap: () => Navigator.pop(dialogContext, a.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (accountId == null) return;

    setState(() => _busy = true);
    try {
      await _service.selectAdAccount(accountId);
      reloadSection();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialAccountSection>();

    return SocialAccountsBody(
      account: section.value,
      loading: section.loading,
      failed: section.failed,
      busy: _busy,
      onConnect: _connect,
      onReconnect: _connect,
      onDisconnect: _disconnect,
      onRefreshStats: _refreshStats,
      onToggleAutoRefresh: _toggleAutoRefresh,
      onChooseAdAccount: _chooseAdAccount,
    );
  }
}

/// The visuals, split from the provider so the layout is testable without an
/// [AuthProvider] (which needs a live Supabase client).
class SocialAccountsBody extends StatelessWidget {
  final SocialAccount? account;
  final bool loading;
  final bool failed;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRefreshStats;
  final ValueChanged<bool> onToggleAutoRefresh;
  final VoidCallback onChooseAdAccount;

  const SocialAccountsBody({
    super.key,
    required this.account,
    required this.loading,
    required this.failed,
    this.busy = false,
    required this.onConnect,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onRefreshStats,
    required this.onToggleAutoRefresh,
    required this.onChooseAdAccount,
  });

  @override
  Widget build(BuildContext context) {
    final connected = !loading && (account?.connected ?? false);
    final needsReconnectForAds = connected && !(account?.adsCapable ?? false);

    return SocialScreenShell(
      title: 'Accounts',
      subtitle: 'Connect Facebook & Instagram once',
      children: [
        const SizedBox(height: AppConstants.spacingXL),
        if (failed)
          const _StatusCard(
            icon: Icons.error_outline,
            title: 'Facebook Page',
            badge: 'Unavailable',
            description:
                "Couldn't read your connection status. Try again in a moment.",
          )
        else ...[
          _StatusCard(
            icon: Icons.facebook,
            title: 'Facebook Page',
            badge: loading
                ? 'Checking…'
                : (account?.hasFacebookPage ?? false)
                ? 'Connected'
                : 'Not connected',
            connected: !loading && (account?.hasFacebookPage ?? false),
            description: (account?.hasFacebookPage ?? false)
                ? account!.pageName!
                : 'Connect your Facebook Page to publish listings, projects '
                      'and updates automatically.',
          ),
          const SizedBox(height: AppConstants.spacingM),
          _StatusCard(
            icon: Icons.camera_alt_outlined,
            title: 'Instagram Business',
            badge: loading
                ? 'Checking…'
                : (account?.hasInstagram ?? false)
                ? 'Linked'
                : 'Not linked',
            connected: !loading && (account?.hasInstagram ?? false),
            description: (account?.hasInstagram ?? false)
                ? '@${account!.instagramUsername!}'
                : 'Instagram publishing uses the Instagram Business account '
                      'linked to your Facebook Page. Link one in Meta, then '
                      'reconnect.',
          ),
          if (connected) ...[
            const SizedBox(height: AppConstants.spacingM),
            _StatusCard(
              icon: Icons.campaign_outlined,
              title: 'Ad Account',
              badge: (account?.adAccountName?.isNotEmpty ?? false)
                  ? 'Selected'
                  : (account?.adsCapable ?? false)
                  ? 'Not selected'
                  : 'Unavailable',
              connected: account?.adAccountName?.isNotEmpty ?? false,
              description: (account?.adAccountName?.isNotEmpty ?? false)
                  ? '${account!.adAccountName} (${account!.adAccountCurrency ?? ''})'
                  : (account?.adsCapable ?? false)
                  ? 'Choose which ad account to run campaigns from.'
                  : 'Reconnect and grant Ads access to run campaigns.',
            ),
            if (account?.adsCapable ?? false) ...[
              const SizedBox(height: AppConstants.spacingS),
              AppActionButton(
                label: (account?.adAccountName?.isNotEmpty ?? false)
                    ? 'Change ad account'
                    : 'Choose ad account',
                height: 40,
                fontSize: 12.5,
                variant: AppActionButtonVariant.outline,
                onTap: busy ? null : onChooseAdAccount,
              ),
            ],
          ],
        ],
        if (!loading &&
            !failed &&
            (account?.lastError?.isNotEmpty ?? false)) ...[
          const SizedBox(height: AppConstants.spacingM),
          _NoticeCard(text: account!.lastError!),
        ],
        // A token nearing expiry is the one piece of connection health worth
        // surfacing — React's `daysUntilExpiry`.
        if (!loading && !failed && _expiryWarning(account) != null) ...[
          const SizedBox(height: AppConstants.spacingM),
          _NoticeCard(text: _expiryWarning(account)!),
        ],
        if (needsReconnectForAds) ...[
          const SizedBox(height: AppConstants.spacingM),
          _NoticeCard(
            text:
                'Reconnect to enable Ads & Leads — Facebook needs extra '
                'permission for that.',
          ),
        ],
        if (connected) ...[
          const SizedBox(height: AppConstants.spacingL),
          DashboardCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Keep my token refreshed automatically',
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                  ),
                ),
                Switch(
                  value: account?.autoRefresh ?? false,
                  onChanged: busy ? null : onToggleAutoRefresh,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppConstants.spacingL),
        if (!connected)
          AppActionButton(
            label: busy ? 'Connecting…' : 'Connect Facebook & Instagram',
            height: 48,
            icon: Icons.link,
            elevated: true,
            onTap: busy ? null : onConnect,
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: AppActionButton(
                  label: 'Refresh stats',
                  height: 44,
                  icon: Icons.refresh,
                  variant: AppActionButtonVariant.outline,
                  onTap: busy ? null : onRefreshStats,
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: AppActionButton(
                  label: 'Reconnect',
                  height: 44,
                  icon: Icons.link,
                  variant: AppActionButtonVariant.outline,
                  onTap: busy ? null : onReconnect,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingM),
          AppActionButton(
            label: 'Disconnect',
            height: 44,
            icon: Icons.link_off,
            onTap: busy ? null : onDisconnect,
          ),
        ],
      ],
    );
  }

  static String? _expiryWarning(SocialAccount? account) {
    if (account == null || !account.connected) return null;
    final days = account.daysUntilExpiry;
    if (days == null || days > 14) return null;
    if (days < 0)
      return 'Your Meta access has expired. Reconnect to resume publishing.';
    return 'Your Meta access expires in $days ${days == 1 ? 'day' : 'days'}. '
        'Reconnect to avoid interruption.';
  }
}

/// White card: glyph + title with a status pill, then supporting copy.
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String badge;
  final String description;
  final bool connected;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    this.connected = false,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Dark pill when disconnected, matching the design; green
                  // once a real connection exists.
                  color: connected ? AppColors.success : AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
                child: Text(
                  badge,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingS),
          Text(
            description,
            style: AppTextStyles.caption.copyWith(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;

  const _NoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3E2),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                fontSize: 11.5,
                height: 1.45,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
