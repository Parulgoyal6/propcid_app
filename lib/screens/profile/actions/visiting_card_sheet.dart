import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/profile_link.dart';
import 'share_profile_sheet.dart' show copyProfileLink;

/// The Digital Visiting Card preview — a mobile port of the portal's
/// `ProfileShareModal.tsx` (`propcid/src/features/profile/ProfileShareModal.tsx`).
///
/// The portal draws this card on an off-screen `<canvas>` so it can be
/// exported as a PNG; there is no canvas API on Flutter, so the equivalent
/// here is a real widget tree captured via [RepaintBoundary.toImage], which
/// produces the same result (a flat PNG of just the card, not the sheet's
/// buttons). Every field, the share URL, the QR endpoint and the share
/// message all come from [profileShareUrl]/[profileQrImageUrl]/
/// [profileShareMessage] in `core/utils/profile_link.dart` — the same
/// ported source of truth the existing Share/QR sheets already use — so
/// nothing here invents a new URL scheme or QR value.
///
/// Colours were originally the portal's own literal canvas crimson
/// (`#C41230`), independent of the app's theme. Retinted to PropCid's real
/// brand orange (and the header now shows the actual logo asset instead of
/// a hand-styled wordmark) per an explicit request to bring this card in
/// line with the rest of the app's branding.
void showDigitalVisitingCard(
  BuildContext context, {
  required String? userId,
  required String name,
  String? companyName,
  required String? userType,
  String? avatarUrl,
  String? city,
  int? experience,
  double? rating,
  int? reviewsCount,
  String? phone,
  String? reraNumber,
  String? email,
  String? address,
}) {
  final shareUrl = profileShareUrl(userId: userId, name: name, role: userType);
  final qrUrl = profileQrImageUrl(shareUrl, size: 400);
  final displayName = (companyName != null && companyName.trim().isNotEmpty)
      ? companyName.trim()
      : name;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _VisitingCardSheet(
      shareUrl: shareUrl,
      qrUrl: qrUrl,
      name: name,
      displayName: displayName,
      userType: userType,
      avatarUrl: avatarUrl,
      city: city,
      experience: experience,
      rating: rating,
      reviewsCount: reviewsCount,
      phone: phone,
      reraNumber: reraNumber,
      email: email,
      address: address,
    ),
  );
}

/// Originally the portal's literal canvas colours (`ProfileShareModal.tsx`).
/// `red`/`redSoftBg`/`redSoftBorder` are kept under their original names —
/// so the ~15 call sites below didn't need touching individually — but now
/// hold PropCid's actual brand orange instead of the portal's crimson.
class _CardPalette {
  _CardPalette._();

  static const Color red = AppColors.primary;
  static const Color redSoftBg = AppColors.primaryLight;
  static const Color redSoftBorder = Color(0xFFFFD3A8);
  static const Color emerald = Color(0xFF10B981);
  // The address row's pin icon — the reference design's teal/blue accent,
  // distinct from the phone/email rows' brand-red icons so the three contact
  // rows aren't all one flat colour.
  static const Color info = Color(0xFF0EA5E9);
  static const Color emeraldSoftBg = Color(0xFFECFDF5);
  static const Color emeraldSoftBorder = Color(0xFFD1FAE5);
  static const Color star = Color(0xFFF59E0B);
  static const Color starEmpty = Color(0xFFD1D5DB);
  static const Color textDark = Color(0xFF111827);
  static const Color textBody = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color textFaint = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color avatarBgStart = Color(0xFFF3F4F6);
  static const Color avatarBgEnd = Color(0xFFE5E7EB);
  static const Color cardBgEnd = Color(0xFFF9FAF8);
}

class _VisitingCardSheet extends StatefulWidget {
  final String shareUrl;
  final String qrUrl;
  final String name;
  final String displayName;
  final String? userType;
  final String? avatarUrl;
  final String? city;
  final int? experience;
  final double? rating;
  final int? reviewsCount;
  final String? phone;
  final String? reraNumber;
  final String? email;
  final String? address;

  const _VisitingCardSheet({
    required this.shareUrl,
    required this.qrUrl,
    required this.name,
    required this.displayName,
    required this.userType,
    this.avatarUrl,
    this.city,
    this.experience,
    this.rating,
    this.reviewsCount,
    this.phone,
    this.reraNumber,
    this.email,
    this.address,
  });

  @override
  State<_VisitingCardSheet> createState() => _VisitingCardSheetState();
}

class _VisitingCardSheetState extends State<_VisitingCardSheet> {
  final GlobalKey _cardKey = GlobalKey();

  bool _imagesReady = false;
  bool _isSharing = false;
  bool _isDownloading = false;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadImages());
  }

  Future<void> _preloadImages() async {
    final urls = <String>[
      widget.qrUrl,
      if (widget.avatarUrl != null && widget.avatarUrl!.trim().isNotEmpty)
        widget.avatarUrl!,
    ];
    try {
      // Bounded wait: the QR image is fetched from a third-party endpoint
      // (api.qrserver.com), and a slow/unreachable network must not leave
      // Share/Download disabled forever — after the timeout the buttons still
      // unlock and simply capture whatever has painted so far (the QR block's
      // own placeholder/error state already handles that gracefully).
      await Future.wait(
        urls.map(
          (url) => precacheImage(CachedNetworkImageProvider(url), context)
              .catchError(
                (Object e) =>
                    debugPrint('Visiting card: image preload failed: $e'),
              ),
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Visiting card: image preload timed out: $e');
    }
    // toImage() reads the last painted frame; give the tree one more frame to
    // paint the now-cached images before anything tries to capture it.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _imagesReady = true);
  }

  String get _shareMessage => profileShareMessage(
    name: widget.displayName,
    userType: widget.userType,
    shareUrl: widget.shareUrl,
    city: widget.city,
    rating: widget.rating,
    reviewsCount: widget.reviewsCount,
  );

  String get _fileStem {
    final cleaned = widget.displayName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${cleaned.isEmpty ? 'PropCID_User' : cleaned}_PropCID_Card';
  }

  Future<Uint8List?> _capturePng() async {
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final pixelRatio = MediaQuery.of(
        context,
      ).devicePixelRatio.clamp(2.0, 3.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Visiting card: capture failed: $e');
      return null;
    }
  }

  /// `path_provider`'s temp-file write (Share) and the `gal` gallery plugin
  /// (Download) have no web implementation — calling either throws a
  /// `MissingPluginException` from the native channel. Both are mobile/desktop
  /// features by design (§ blueprint scope), so on web this fails fast with an
  /// honest message instead of surfacing that low-level channel error.
  bool _blockedOnWeb() {
    if (!kIsWeb) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'This action needs the Android/iOS app — it is not available in the web preview.',
          ),
        ),
      );
    return true;
  }

  Future<void> _handleShare() async {
    if (_isSharing) return;
    if (_blockedOnWeb()) return;
    setState(() => _isSharing = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw Exception('card capture failed');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileStem.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: _shareMessage,
        subject: '${widget.displayName} PropCID Card',
      );
    } catch (e) {
      debugPrint('Visiting card: share failed: $e');
      // Mirrors ProfileShareModal.tsx's handleNativeShareClick fallback: if
      // sharing the card fails, fall back to copying the link.
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: widget.shareUrl));
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Sharing failed, copied link to clipboard instead.',
                ),
              ),
            );
        }
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;
    if (_blockedOnWeb()) return;
    setState(() => _isDownloading = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw Exception('card capture failed');

      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) throw Exception('gallery access denied');

      await Gal.putImageBytes(bytes, name: _fileStem);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Visiting card saved to gallery')),
          );
      }
    } on GalException catch (e) {
      debugPrint(
        'Visiting card: save failed: ${e.type} ${e.platformException}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.type.message)));
      }
    } catch (e) {
      debugPrint('Visiting card: save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text("Couldn't save the card. Please try again."),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _handleCopyLink() async {
    if (_isCopying) return;
    setState(() => _isCopying = true);
    await copyProfileLink(context, widget.shareUrl);
    if (mounted) setState(() => _isCopying = false);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    // Split into a scrollable region (drag handle/title/card preview) and a
    // fixed footer (the Share button + Download/Copy row) that is NEVER
    // part of that scroll view. Previously everything shared one
    // `SingleChildScrollView`, so on a short-enough phone screen the whole
    // sheet's 90%-of-height cap could end while the footer buttons were only
    // partially scrolled into view — they were reachable by scrolling, but
    // landed right at the sheet's edge with no obvious affordance that more
    // was below, reading as a cut-off/broken layout instead of "scroll for
    // more". Pinning the footer outside the scroll area means the two most
    // important actions on this sheet are always fully visible regardless of
    // screen height; only the card preview itself scrolls if it doesn't fit.
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDEDF2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Share Digital Visiting Card',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _CardPalette.textDark,
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'Close',
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 22,
                                color: _CardPalette.textFaint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    RepaintBoundary(
                      key: _cardKey,
                      child: _VisitingCardFace(
                        name: widget.name,
                        displayName: widget.displayName,
                        userType: widget.userType,
                        avatarUrl: widget.avatarUrl,
                        city: widget.city,
                        experience: widget.experience,
                        rating: widget.rating,
                        reviewsCount: widget.reviewsCount,
                        phone: widget.phone,
                        reraNumber: widget.reraNumber,
                        email: widget.email,
                        address: widget.address,
                        qrUrl: widget.qrUrl,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A premium gradient CTA (matching the rest of the app's
                  // primary buttons) in place of the previous flat fill —
                  // same enabled/disabled condition, same `_handleShare`
                  // call, same loading-spinner swap.
                  Builder(
                    builder: (context) {
                      final enabled = !_isSharing && _imagesReady;
                      return SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: enabled ? _handleShare : null,
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: enabled
                                    ? AppColors.primaryGradient
                                    : LinearGradient(
                                        colors: [
                                          AppColors.primary.withOpacity(0.55),
                                          AppColors.primary.withOpacity(0.4),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: enabled
                                    ? AppColors.primaryGlow
                                    : null,
                              ),
                              child: Center(
                                child: _isSharing
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const FittedBox(
                                        // Scales the icon+label down together
                                        // on a narrow screen instead of
                                        // ellipsis-truncating the text — the
                                        // button always reads in full, just
                                        // smaller when it has to be.
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.ios_share_rounded,
                                              size: 19,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Share Visiting Card + Link',
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _OutlinedCardAction(
                          icon: Icons.download_rounded,
                          label: 'Download PNG',
                          isBusy: _isDownloading,
                          enabled: !_isDownloading && _imagesReady,
                          onTap: _handleDownload,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OutlinedCardAction(
                          icon: Icons.copy_rounded,
                          label: 'Copy Link',
                          isBusy: _isCopying,
                          enabled: !_isCopying,
                          onTap: _handleCopyLink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedCardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onTap;

  const _OutlinedCardAction({
    required this.icon,
    required this.label,
    required this.isBusy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _CardPalette.border),
          foregroundColor: _CardPalette.textBody,
          // Tighter than the default (which left too little room for the
          // label on a narrow phone) so the icon+label below has more space
          // to work with before it ever needs to shrink.
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FittedBox(
                // Scales the icon+label down together on a narrow screen
                // instead of ellipsis-truncating the text (the reported
                // "Download P…" clipping) — the label always reads in full.
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The visiting card face itself — the part captured to PNG.
///
/// Mirrors `ShareOptions`' card markup in ProfileShareModal.tsx: header
/// (wordmark + RERA badge), avatar + identity + rating + location +
/// experience alongside the QR block, then a contact footer. Below ~340
/// logical px wide the QR block drops under the identity column instead of
/// beside it, so the card never clips on narrow phones.
class _VisitingCardFace extends StatelessWidget {
  final String name;
  final String displayName;
  final String? userType;
  final String? avatarUrl;
  final String? city;
  final int? experience;
  final double? rating;
  final int? reviewsCount;
  final String? phone;
  final String? reraNumber;
  final String? email;
  final String? address;
  final String qrUrl;

  const _VisitingCardFace({
    required this.name,
    required this.displayName,
    required this.userType,
    required this.avatarUrl,
    required this.city,
    required this.experience,
    required this.rating,
    required this.reviewsCount,
    required this.phone,
    required this.reraNumber,
    required this.email,
    required this.address,
    required this.qrUrl,
  });

  String get _initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'U';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  bool get _hasRera => reraNumber != null && reraNumber!.trim().isNotEmpty;
  bool get _hasExperience => experience != null && experience! > 0;
  bool get _hasPhone => phone != null && phone!.trim().isNotEmpty;
  bool get _hasEmail => email != null && email!.trim().isNotEmpty;
  bool get _hasAddress => address != null && address!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, _CardPalette.cardBgEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _CardPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The actual PropCid wordmark asset — replaces the
                          // previous hand-styled "PropCID" text, sized by
                          // height only via its real aspect ratio (862×203)
                          // so it can never stretch or distort.
                          Semantics(
                            label: 'PropCid',
                            image: true,
                            child: SizedBox(
                              height: 22,
                              child: AspectRatio(
                                aspectRatio: 862 / 203,
                                child: Image.asset(
                                  'assets/branding/propcid_logo.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'YOUR REAL ESTATE PARTNER',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: _CardPalette.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_hasRera)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _CardPalette.emeraldSoftBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _CardPalette.emeraldSoftBorder,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 13,
                              color: _CardPalette.emerald,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'RERA VERIFIED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: _CardPalette.emerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: _CardPalette.border),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = _IdentityBlock(
                      displayName: displayName,
                      userType: userType,
                      avatarUrl: avatarUrl,
                      initials: _initials,
                      city: city,
                      rating: rating,
                      reviewsCount: reviewsCount,
                      hasExperience: _hasExperience,
                      experience: experience,
                    );
                    final qr = _QrBlock(qrUrl: qrUrl);

                    if (constraints.maxWidth < 330) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 14),
                          Align(alignment: Alignment.centerLeft, child: qr),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        qr,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: _CardPalette.border),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_hasPhone)
                      Flexible(
                        child: _buildContactRow(
                          Icons.phone_rounded,
                          _CardPalette.red,
                          phone!,
                        ),
                      ),
                    const Spacer(),
                    const Text(
                      'propcid.com',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _CardPalette.red,
                      ),
                    ),
                  ],
                ),
                if (_hasEmail) ...[
                  const SizedBox(height: 8),
                  _buildContactRow(
                    Icons.email_rounded,
                    _CardPalette.red,
                    email!,
                  ),
                ],
                if (_hasAddress) ...[
                  const SizedBox(height: 8),
                  _buildContactRow(
                    Icons.location_on_rounded,
                    _CardPalette.info,
                    address!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One contact line — icon, then the value, wrapping onto a second line
  /// rather than ellipsizing (an address is the one value here long enough
  /// to need it).
  Widget _buildContactRow(IconData icon, Color iconColor, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _CardPalette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  final String displayName;
  final String? userType;
  final String? avatarUrl;
  final String initials;
  final String? city;
  final double? rating;
  final int? reviewsCount;
  final bool hasExperience;
  final int? experience;

  const _IdentityBlock({
    required this.displayName,
    required this.userType,
    required this.avatarUrl,
    required this.initials,
    required this.city,
    required this.rating,
    required this.reviewsCount,
    required this.hasExperience,
    required this.experience,
  });

  @override
  Widget build(BuildContext context) {
    final filledStars = (rating ?? 0).round().clamp(0, 5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(avatarUrl: avatarUrl, initials: initials),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: _CardPalette.textDark,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _CardPalette.redSoftBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _CardPalette.redSoftBorder),
                ),
                child: Text(
                  formattedUserType(userType).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _CardPalette.red,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < filledStars ? Icons.star_rounded : Icons.star_rounded,
                      size: 14,
                      color: i < filledStars
                          ? _CardPalette.star
                          : _CardPalette.starEmpty,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${reviewsCount ?? 0})',
                    style: const TextStyle(
                      fontSize: 10,
                      color: _CardPalette.textFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 13,
                    color: _CardPalette.textFaint,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      (city != null && city!.trim().isNotEmpty)
                          ? city!.trim()
                          : 'Delhi NCR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _CardPalette.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasExperience) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.work_outline_rounded,
                      size: 13,
                      color: _CardPalette.textFaint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$experience+ Years Exp.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _CardPalette.textFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;

  const _Avatar({required this.avatarUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    const width = 76.0;
    const height = 94.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => _initialsFallback(),
              errorWidget: (_, _, _) => _initialsFallback(),
            )
          : _initialsFallback(),
    );
  }

  Widget _initialsFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_CardPalette.avatarBgStart, _CardPalette.avatarBgEnd],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: _CardPalette.textFaint,
        ),
      ),
    );
  }
}

class _QrBlock extends StatelessWidget {
  final String qrUrl;

  const _QrBlock({required this.qrUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _CardPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: CachedNetworkImage(
              imageUrl: qrUrl,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, _, _) => const Icon(
                Icons.qr_code_2_rounded,
                size: 36,
                color: _CardPalette.textFaint,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'SCAN PROFILE',
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: _CardPalette.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
