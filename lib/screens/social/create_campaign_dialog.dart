import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/launch_features.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/social_models.dart';
import '../../services/social_service.dart';

/// Per-currency minimum + starting daily budget (major units) and INR
/// conversion rate — a direct port of `CreateCampaignDialog.tsx`'s
/// `CUR_MIN`/`CUR_DEFAULT`/`INR_PER` tables.
const Map<String, double> _curMin = {
  'USD': 2,
  'INR': 120,
  'AED': 8,
  'GBP': 2,
  'EUR': 2,
};
const Map<String, double> _curDefault = {
  'USD': 5,
  'INR': 400,
  'AED': 20,
  'GBP': 5,
  'EUR': 5,
};
const Map<String, double> _inrPer = {
  'USD': 83,
  'AED': 22.6,
  'GBP': 105,
  'EUR': 90,
  'INR': 1,
};

const GeoSearchResult _india = GeoSearchResult(
  key: 'IN',
  name: 'India',
  type: 'country',
  countryCode: 'IN',
  countryName: 'India',
);

class _Objective {
  final String value;
  final String label;
  final String hint;
  const _Objective(this.value, this.label, this.hint);
}

const List<_Objective> _objectives = [
  _Objective('OUTCOME_TRAFFIC', 'Traffic', 'Send people to the listing page'),
  _Objective('OUTCOME_ENGAGEMENT', 'Engagement', 'Maximise post interactions'),
  _Objective(
    'OUTCOME_LEADS',
    'Leads',
    'Collect contact details via a Meta form',
  ),
];

const List<String> _ctaOptions = [
  'LEARN_MORE',
  'CONTACT_US',
  'GET_QUOTE',
  'SIGN_UP',
  'BOOK_TRAVEL',
  'SUBSCRIBE',
];

/// Shows "Create campaign" for one already-eligible piece of content — a
/// direct port of `CreateCampaignDialog.tsx`. The portal opens this after its
/// own content picker (`CampaignsPanel.tsx`'s `ContentPicker`); this dialog
/// itself has no picker step, matching that split.
Future<void> showCreateCampaignDialog(
  BuildContext context, {
  required String userId,
  required String contentType,
  required String contentId,
  List<String> mediaUrls = const [],
  String? title,
  ValueChanged<AdCampaign>? onCreated,
}) async {
  if (!LaunchFeatures.metaPublishing) return;
  return showDialog<void>(
    context: context,
    builder: (_) => CreateCampaignDialog(
      userId: userId,
      contentType: contentType,
      contentId: contentId,
      mediaUrls: mediaUrls,
      title: title,
      onCreated: onCreated,
    ),
  );
}

/// Offers to boost just-created content as a Meta ad campaign — the mobile
/// equivalent of the portal's `RunAdButton`, which sits next to
/// `PublishToSocialButton` on the article and reel success cards and opens
/// `CreateCampaignDialog` directly, independent of (and not gated by) the
/// Campaigns tab's role-based content picker.
///
/// A confirm step first, rather than opening [showCreateCampaignDialog]
/// immediately: campaigns are always created paused either way, but *opening
/// the creation form* itself should still be something the user asked for,
/// not a second modal that appears unprompted right after Publish Everywhere.
Future<void> offerBoostDialog(
  BuildContext context, {
  required String userId,
  required String contentType,
  required String contentId,
  List<String> mediaUrls = const [],
  String? title,
}) async {
  if (!LaunchFeatures.metaPublishing) return;
  final wantsBoost = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Boost on Meta ads?'),
      content: Text(
        title != null && title.isNotEmpty
            ? 'Run a paid ad for "$title" on Facebook & Instagram to reach '
                  'more people. You can always do this later from Social ▸ '
                  'Campaigns.'
            : 'Run a paid ad for this post on Facebook & Instagram to reach '
                  'more people. You can always do this later from Social ▸ '
                  'Campaigns.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Boost'),
        ),
      ],
    ),
  );
  if (wantsBoost != true || !context.mounted) return;
  await showCreateCampaignDialog(
    context,
    userId: userId,
    contentType: contentType,
    contentId: contentId,
    mediaUrls: mediaUrls,
    title: title,
  );
}

class CreateCampaignDialog extends StatefulWidget {
  final String userId;
  final String contentType;
  final String contentId;
  final List<String> mediaUrls;
  final String? title;
  final ValueChanged<AdCampaign>? onCreated;

  const CreateCampaignDialog({
    super.key,
    required this.userId,
    required this.contentType,
    required this.contentId,
    this.mediaUrls = const [],
    this.title,
    this.onCreated,
  });

  @override
  State<CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<CreateCampaignDialog> {
  final _service = SocialService();

  bool _loading = true;
  bool _loadFailed = false;
  bool _generating = false;
  bool _creating = false;
  bool _confirmSpend = false;
  SocialAccount? _account;

  String _objective = 'OUTCOME_TRAFFIC';
  bool _enterInInr = false;
  late final TextEditingController _budgetController;
  final _durationController = TextEditingController(text: '7');

  List<GeoSearchResult> _locations = const [_india];
  final _locQueryController = TextEditingController();
  List<GeoSearchResult> _locResults = const [];
  bool _locSearching = false;
  Timer? _debounce;

  late final TextEditingController _headlineController;
  final _messageController = TextEditingController();
  String _ctaType = 'LEARN_MORE';
  late bool _useVideo;

  @override
  void initState() {
    super.initState();
    _budgetController = TextEditingController(
      text: _numText(_curDefault['USD']!),
    );
    _headlineController = TextEditingController(text: widget.title ?? '');
    _useVideo = widget.contentType == 'video' || widget.contentType == 'reel';
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _budgetController.dispose();
    _durationController.dispose();
    _locQueryController.dispose();
    _headlineController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  static String _numText(double n) =>
      n == n.truncateToDouble() ? n.toInt().toString() : '$n';

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final account = await _service.getAccount(widget.userId);
      if (!mounted) return;
      final currency = account?.adAccountCurrency ?? 'USD';
      setState(() {
        _account = account;
        _budgetController.text = _numText(_curDefault[currency] ?? 5);
        _enterInInr = false;
        _loading = false;
      });
      _draftMessage();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _draftMessage() async {
    setState(() => _generating = true);
    try {
      final res = await _service.generateCaption(
        contentType: widget.contentType,
        contentId: widget.contentId,
        platform: 'facebook',
      );
      if (!mounted) return;
      final caption = '${res['caption'] ?? ''}';
      final hashtags = (res['hashtags'] as List? ?? const [])
          .map((h) => '$h')
          .toList();
      final cta = res['cta'] as String?;
      final composed = composeCaption(caption, hashtags, cta);
      if (_messageController.text.isEmpty && composed.isNotEmpty) {
        _messageController.text = composed;
      }
    } catch (_) {
      // Leave the field empty — matches the portal's silent-fail draft.
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _onLocQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _locResults = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _locSearching = true);
      try {
        final results = await _service.searchTargeting(q);
        if (!mounted) return;
        setState(() => _locResults = results);
      } catch (_) {
        if (mounted) setState(() => _locResults = const []);
      } finally {
        if (mounted) setState(() => _locSearching = false);
      }
    });
  }

  void _addLocation(GeoSearchResult r) {
    final exists = _locations.any((l) => l.key == r.key && l.type == r.type);
    setState(() {
      if (!exists) _locations = [..._locations, r];
      _locQueryController.clear();
      _locResults = const [];
    });
  }

  void _removeLocation(GeoSearchResult r) {
    setState(() {
      _locations = _locations
          .where((l) => !(l.key == r.key && l.type == r.type))
          .toList();
    });
  }

  Map<String, dynamic> _buildGeo() {
    final countries = <String>[];
    final regions = <Map<String, dynamic>>[];
    final cities = <Map<String, dynamic>>[];
    for (final l in _locations) {
      if (l.type == 'country') {
        countries.add(
          (l.countryCode?.isNotEmpty ?? false) ? l.countryCode! : l.key,
        );
      } else if (l.type == 'region') {
        regions.add({'key': l.key});
      } else {
        cities.add({'key': l.key, 'radius': 25, 'distance_unit': 'mile'});
      }
    }
    return {
      if (countries.isNotEmpty) 'countries': countries,
      if (regions.isNotEmpty) 'regions': regions,
      if (cities.isNotEmpty) 'cities': cities,
    };
  }

  bool get _isLeads => _objective == 'OUTCOME_LEADS';

  bool get _isHousing =>
      widget.contentType == 'property' || widget.contentType == 'project';

  String get _currency => _account?.adAccountCurrency ?? 'USD';

  double get _rate => _inrPer[_currency] ?? 83;

  double get _minMajor => _curMin[_currency] ?? 1;

  double get _budgetInput => double.tryParse(_budgetController.text) ?? 0;

  double get _accountMajor => _enterInInr ? _budgetInput / _rate : _budgetInput;

  double get _inrEquivalent =>
      _enterInInr ? _budgetInput : _budgetInput * _rate;

  int get _durationDays =>
      (int.tryParse(_durationController.text) ?? 7).clamp(1, 3650);

  bool get _notReady =>
      !_loading &&
      !_loadFailed &&
      (_account?.connected != true ||
          _account?.adsCapable != true ||
          !(_account?.adAccountName?.isNotEmpty ?? false));

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleCreate() async {
    if (_locations.isEmpty) {
      _showError('Add at least one location to target.');
      return;
    }
    final accountMajor = _accountMajor;
    if (!accountMajor.isFinite || accountMajor < _minMajor) {
      _showError(
        'Daily budget must be at least ${_fmtMajor(_minMajor, _currency)}.',
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final now = DateTime.now().toUtc();
      final body = <String, dynamic>{
        'content_type': widget.contentType,
        'content_id': widget.contentId,
        'objective': _objective,
        'daily_budget_minor': (accountMajor * 100).round(),
        'start_time': now.toIso8601String(),
        'end_time': now.add(Duration(days: _durationDays)).toIso8601String(),
        'targeting_overrides': {'geo_locations': _buildGeo()},
        'creative_overrides': {
          if (_messageController.text.isNotEmpty)
            'message': _messageController.text,
          if (_headlineController.text.isNotEmpty)
            'headline': _headlineController.text,
          'cta_type': _ctaType,
          'use_video': _useVideo,
        },
      };
      final campaign = await _service.createCampaign(body);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated?.call(campaign);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Campaign created — it's paused. Add a payment method in Meta, "
            'then Launch.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  static String _fmtMajor(double major, String currency) =>
      formatMinorAmount((major * 100).round(), currency: currency);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.title != null && widget.title!.isNotEmpty
                  ? 'Boost "${widget.title}"'
                  : 'Boost this content',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Create a Meta ad from this post. It's created paused — "
              'nothing spends until you add a payment method and launch it.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            if (_loadFailed)
              _LoadErrorPanel(onRetry: _load)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_notReady)
              _NotReadyPanel(account: _account)
            else
              _buildForm(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_notReady && !_loadFailed)
          ElevatedButton.icon(
            onPressed: (_creating || _loading || !_confirmSpend)
                ? null
                : _handleCreate,
            icon: _creating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rocket_launch, size: 16),
            label: const Text('Create campaign (paused)'),
          ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Objective ──────────────────────────────────────────────────
        const Text(
          'Campaign goal',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _objective,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: [
            for (final o in _objectives)
              DropdownMenuItem(
                value: o.value,
                child: Text(
                  '${o.label} — ${o.hint}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
          onChanged: (v) => setState(() => _objective = v ?? _objective),
        ),
        if (_isLeads) ...[
          const SizedBox(height: 4),
          const Text(
            'A Meta lead form (name, email, phone + privacy policy) is '
            'created on your Page. Submissions appear in the Leads tab.',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 16),

        // ── Locations ──────────────────────────────────────────────────
        const Text(
          'Where to run the ad',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in _locations)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  '${l.name} · ${l.type}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onDeleted: () => _removeLocation(l),
              ),
            if (_locations.isEmpty)
              const Text(
                'No locations — add at least one.',
                style: TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _locQueryController,
          onChanged: _onLocQueryChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'Search country, state or city…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (_locQueryController.text.trim().length >= 2 &&
            (_locSearching || _locResults.isNotEmpty)) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E2EA)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _locSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Searching…', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _locResults.length,
                    itemBuilder: (context, i) {
                      final r = _locResults[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          r.displayLabel,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        trailing: Text(
                          r.type,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                        onTap: () => _addLocation(r),
                      );
                    },
                  ),
          ),
        ],
        if (_isHousing) ...[
          const SizedBox(height: 6),
          const Text(
            "Real-estate ads reaching US/Canada run under Meta's Housing "
            "category (targeting restricted). For other countries this "
            "doesn't apply.",
            style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
          ),
        ],
        const SizedBox(height: 16),

        // ── Budget + duration ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                'Daily budget (${_enterInInr ? '₹' : _currency})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            const Text(
              'Enter in ₹',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            Switch(
              value: _enterInInr,
              onChanged: (v) => setState(() => _enterInInr = v),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _budgetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Days',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_enterInInr ? '≈ ${_fmtMajor(_accountMajor, _currency)}/day (billed in $_currency). ' : '≈ ${_fmtMajor(_inrEquivalent, 'INR')}/day. '}'
          'Runs $_durationDays day${_durationDays == 1 ? '' : 's'} · up to '
          '${_fmtMajor(_accountMajor * _durationDays, _currency)} total.'
          '${_accountMajor < _minMajor ? ' Min ${_fmtMajor(_minMajor, _currency)}/day.' : ''}',
          style: TextStyle(
            fontSize: 11,
            color: _accountMajor < _minMajor ? Colors.red : Colors.black54,
          ),
        ),
        const SizedBox(height: 16),

        // ── Creative ───────────────────────────────────────────────────
        const Text(
          'Headline',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _headlineController,
          maxLength: 240,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Primary text',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: _generating ? null : _draftMessage,
              icon: _generating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 14),
              label: const Text('AI', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        TextField(
          controller: _messageController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write ad copy or tap AI to generate it…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        if (!_isLeads) ...[
          const Text(
            'Button',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _ctaType,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: [
              for (final c in _ctaOptions)
                DropdownMenuItem(
                  value: c,
                  child: Text(
                    c.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _ctaType = v ?? _ctaType),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Switch(
              value: _useVideo,
              onChanged: (v) => setState(() => _useVideo = v),
            ),
            const Expanded(
              child: Text(
                "Use the post's video if it has one (otherwise an image is used)",
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        Text(
          widget.mediaUrls.isNotEmpty
              ? 'Post images/videos are pulled in automatically.'
              : "No image found on this post — it'll run Facebook-only with a link preview.",
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
        const SizedBox(height: 16),

        // ── Payment-method note ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3E2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE0A8)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.credit_card, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB45309),
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'To actually go live you need a payment method on ',
                      ),
                      TextSpan(
                        text: _account?.adAccountName ?? 'your ad account',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(
                        text:
                            ' in Meta Ads Manager (Billing → Payment Settings). Without it '
                            "the campaign stays paused and won't deliver.",
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Spend disclaimer ───────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _confirmSpend = !_confirmSpend),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _confirmSpend,
                  onChanged: (v) => setState(() => _confirmSpend = v ?? false),
                ),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 12),
                      children: [
                        TextSpan(text: 'I understand this creates a '),
                        TextSpan(
                          text: 'paused',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' campaign on my Meta ad account and I\'m responsible '
                              'for the ad spend once I launch it.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NotReadyPanel extends StatelessWidget {
  final SocialAccount? account;

  const _NotReadyPanel({required this.account});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (account?.connected != true) {
      message = 'Connect your Facebook Page to run ads.';
    } else if (account?.adsCapable != true) {
      message =
          'Reconnect to enable Ads & Leads (extra Meta permissions needed).';
    } else {
      message = 'Choose an ad account before creating campaigns.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2EA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.amber, size: 24),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppConstants.socialAccountsScreen);
            },
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Open Social ▸ Accounts'),
          ),
        ],
      ),
    );
  }
}

class _LoadErrorPanel extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadErrorPanel({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2EA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.amber, size: 24),
          const SizedBox(height: 10),
          const Text(
            "Couldn't check your ad account status.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
