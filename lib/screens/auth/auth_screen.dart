import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../app_navigator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/validation/validators.dart';
import '../../core/widgets/scale_tap.dart';
import '../../providers/auth_provider.dart';
import '../../voice_agent/floating_ai_orb_visibility.dart';
import '../../voice_agent/widgets/voice_agent_panel.dart';
import '../../config/launch_features.dart';

/// The real, official Google "G" mark (Google's own multi-colour logo, as
/// used on every standard "Sign in with Google" button) — inlined as raw SVG
/// so it renders pixel-accurately via the app's existing `flutter_svg`
/// dependency, with no new package and no new asset file. Replaces the
/// earlier hand-painted 4-arc approximation, which read as an approximation
/// rather than the real logo.
const String _googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z"/>
  <path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z"/>
  <path fill="#FBBC05" d="M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z"/>
  <path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z"/>
</svg>
''';

enum _EmailMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _headerController;
  late Animation<double> _logoAnimation;
  late Animation<double> _text1Animation;
  late Animation<double> _text2Animation;

  // Login controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginPasswordVisible = false;

  // Focus traversal: Email's keyboard "next" action moves here explicitly
  // (see `_buildLoginForm`) rather than relying on implicit tab order.
  // Password keeps the default `TextInputAction.done`, which only dismisses
  // the keyboard — it must never itself trigger `_handleLogin`.
  final _loginEmailFocus = FocusNode();
  final _loginPasswordFocus = FocusNode();

  // Sign Up — email only, portal parity. No name/password/role/type here:
  // Supabase's own `signInWithOtp(shouldCreateUser: true)` both creates the
  // account (if new) and signs in (if existing) with a magic link, and Full
  // Name + User Type are collected afterwards, once the link is confirmed
  // and a real session exists — see AccountTypeScreen.
  final _signUpEmailCtrl = TextEditingController();
  bool _signUpEmailSent = false;
  String? _signUpSentTo;

  // Phone controllers
  final _phoneCtrl = TextEditingController();

  // Which form the Email tab shows. There is no longer a dedicated Sign Up
  // tab — portal parity means two top-level tabs (Mobile/Email), with Sign
  // Up living as a mode switch inside Email, matching SignIn.tsx.
  _EmailMode _emailMode = _EmailMode.signIn;

  bool _isLoading = false;
  bool _googleOAuthStarting = false;

  @override
  void initState() {
    super.initState();
    // Index 0 = Mobile, index 1 = Email — Mobile is selected by default,
    // matching the portal's `<Tabs defaultValue="phone">`.
    _tabController = TabController(length: 2, vsync: this);
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _text1Animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    _text2Animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerController,
        curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
      ),
    );

    _headerController.forward();

    // The floating assistant orb otherwise sits on top of the Sign In
    // button on this screen. It stays fully intact (same tap/long-press,
    // same drag/edge-snap, same VoiceAgentProvider) everywhere else — this
    // only stops *this* screen's build from painting it, and the inline
    // "Need help?" action (`_openHelpPanel`) opens the identical panel.
    if (LaunchFeatures.voiceAssistant) {
      floatingAiOrbVisible.value = false;
    }

    // A blocked-account sign-out (AuthProvider.handleBlockedAccount) lands
    // here — surface its message through the same snackbar every other
    // auth failure already uses, rather than a new screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final blockedMessage = AuthProvider.consumeBlockedMessage();
      if (blockedMessage != null && mounted) {
        _showSnackBar(blockedMessage, isError: true);
      }
    });
  }

  @override
  void dispose() {
    // Restores the process-wide default for every other screen.
    if (LaunchFeatures.voiceAssistant) {
      floatingAiOrbVisible.value = true;
    }
    _tabController.dispose();
    _headerController.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _loginEmailFocus.dispose();
    _loginPasswordFocus.dispose();
    _signUpEmailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────

  Future<void> _handleForgotPassword() async {
    final email = _loginEmailCtrl.text.trim();
    if (email.isEmpty) {
      _showSnackBar(
        'Enter your email address above, then tap Forgot password.',
        isError: true,
      );
      return;
    }
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().resetPassword(email);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (error != null) {
      _showSnackBar('Could not send reset email: $error', isError: true);
    } else {
      _showSnackBar(
        'Password reset email sent. Check your inbox.',
        isError: false,
      );
    }
  }

  String? _validateLogin() {
    // Email or username only — phone sign-in lives on the Phone tab and is
    // never password-based (see AuthService.loginWithIdentifier).
    final idErr = Validators.required(_loginEmailCtrl.text);
    if (idErr != null) return idErr;
    if (_loginPasswordCtrl.text.isEmpty) return 'Password is required.';
    if (_loginPasswordCtrl.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  String? _validatePhoneForm() {
    return Validators.required(_phoneCtrl.text) ??
        Validators.phone(_phoneCtrl.text);
  }

  String? _validateSignUpEmail() {
    return Validators.required(_signUpEmailCtrl.text) ??
        Validators.email(_signUpEmailCtrl.text);
  }

  // ─── Handlers ─────────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    // Stops double taps and simultaneous authentication actions.
    if (_isLoading || _googleOAuthStarting) return;

    setState(() => _googleOAuthStarting = true);
    debugPrint('[GOOGLE_OAUTH] Google sign-in requested');

    final error = await context.read<AuthProvider>().signInWithGoogle();

    if (!mounted) return;

    setState(() => _googleOAuthStarting = false);

    if (error != null) {
      _showSnackBar(error, isError: true);
    }
  }

  Future<void> _handleLogin() async {
    final validationError = _validateLogin();
    if (validationError != null) {
      _showSnackBar(validationError, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().login(
      _loginEmailCtrl.text.trim(),
      _loginPasswordCtrl.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      _showSnackBar(error, isError: true);
    }
    // On success, AuthProvider's own auth-stream listener resolves the
    // destination and navigates — this screen does not decide where to go.
  }

  Future<void> _handleSendOtp() async {
    final validationError = _validatePhoneForm();
    if (validationError != null) {
      _showSnackBar(validationError, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().sendOtp(
      _phoneCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (error != null) {
      _showSnackBar(error, isError: true);
      return;
    }
    if (!mounted) return;
    // No name collected here anymore (portal parity) — a new phone account
    // gets its full name on AccountTypeScreen after sign-in, same as every
    // Email/Google sign-up already does. OtpScreen's own `name` handling
    // stays intact for that case; this call site just never supplies one.
    await Navigator.pushNamed(
      context,
      '/auth-otp',
      arguments: {'phone': Validators.toE164(_phoneCtrl.text.trim())},
    );
  }

  Future<void> _handleSignUp() async {
    final validationError = _validateSignUpEmail();
    if (validationError != null) {
      _showSnackBar(validationError, isError: true);
      return;
    }
    final email = _signUpEmailCtrl.text.trim();
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().signUpWithEmail(email);
    setState(() => _isLoading = false);
    if (error != null) {
      _showSnackBar(error, isError: true);
      return;
    }
    setState(() {
      _signUpEmailSent = true;
      _signUpSentTo = email;
    });
  }

  Future<void> _handleResendSignUpEmail() async {
    final email = _signUpSentTo;
    if (email == null) return;
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().signUpWithEmail(email);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (error != null) {
      _showSnackBar(error, isError: true);
    } else {
      _showSnackBar('Confirmation email resent.', isError: false);
    }
  }

  /// Opens the same assistant panel `FloatingAiOrb._openPanel` does — that
  /// widget's own `_openPanel` is private, so this mirrors its two-line body
  /// (same `appNavigatorKey` overlay context, same `VoiceAgentPanel`, same
  /// `VoiceAgentProvider` underneath) rather than reaching into its private
  /// state. This is an inline, auth-route-local trigger for the identical
  /// assistant functionality — not a second assistant.
  ///
  /// `floating_ai_orb.dart` and `app.dart` are both untouched: this screen
  /// has no way to also suppress the *floating* orb's global presentation
  /// without editing one of those two files, which is out of scope here
  /// (global overlay infrastructure) — see the redesign report for that
  /// reported gap.
  void _openHelpPanel() {
    final overlayContext = appNavigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) return;
    showModalBottomSheet(
      context: overlayContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceAgentPanel(),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.shade700
            : AppColors.verifiedBadge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Root Build ───────────────────────────────────────────

  /// Same premium house photo already used elsewhere in this app (the
  /// second slide of the Home hero carousel, `HeroBannerSection`) — reused
  /// verbatim rather than a new, unrelated image; only the crop query
  /// params below select a different region of that same photo.
  ///
  /// This is the one piece of hero artwork this redesign could not source
  /// exactly: no local "modern white property" photograph (or any local
  /// hero image at all) exists in this checkout — every hero photo across
  /// the app, this one included, is already a remote Unsplash URL. Reusing
  /// this exact existing URL is a reported fallback, not a claim that it is
  /// a specific reference photograph.
  ///
  /// `crop=left,top` (Unsplash's own imgix-backed crop API — no new
  /// dependency) biases the served frame toward the villa's glass frontage
  /// and away from the large foreground shrub, which the original
  /// center-right crop put front and center. Verified by fetching and
  /// visually inspecting several crop candidates before picking this one.
  static const String _backgroundImageUrl =
      'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=960&h=920&fit=crop&crop=left,top&q=80';

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    // Bottom safe-area inset (home indicator / gesture bar).
    final bottomInset = mediaQuery.padding.bottom;
    // > 0 exactly while the software keyboard is showing — Scaffold's own
    // `resizeToAvoidBottomInset` (left at its default `true`) already
    // shrinks `body`'s available height for this; this flag is read only to
    // decide *what* to show in the shrunk space, never to add more padding
    // on top of what Scaffold already resized, which would double-count it.
    final keyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Explicit even though it's the default — this whole restructure
      // depends on it staying enabled.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        // ONE coordinated scroll view for the header and the form, replacing
        // the previous non-scrolling hero stacked above a separately
        // scrolling form card. That structure reserved a fixed hero height
        // no matter how little room the keyboard left the form; this way,
        // scrolling (and the hero's own collapse below) both come from the
        // same source of truth, and a focused field's own built-in
        // "scroll ancestor into view on focus" behavior has just the one
        // scrollable to work with.
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: 24 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A short, restrained resize between the full hero and the
              // compact logo-only bar — no focus is ever inside this
              // subtree, so collapsing it cannot itself steal focus or
              // jump the scroll position other than the natural reflow of
              // the space it frees up for the form below.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: keyboardOpen ? _buildCompactLogoBar() : _buildHero(),
              ),
              ClipRRect(
                key: const Key('authFormCard'),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTabBar(),
                        const SizedBox(height: 22),
                        // Use AnimatedBuilder to rebuild tab content on tab switch
                        AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, _) {
                            switch (_tabController.index) {
                              case 0:
                                return _buildPhoneForm();
                              default:
                                return _emailMode == _EmailMode.signUp
                                    ? _buildSignUpForm()
                                    : _buildLoginForm();
                            }
                          },
                        ),
                        if (LaunchFeatures.voiceAssistant) ...[
                          const SizedBox(height: 20),
                          _buildHelpFooter(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Fills the leftover grey space below the form card on
              // taller viewports (where hero + card together are shorter
              // than the screen) with a small branded trust footer instead
              // of leaving it visibly bare. Purely decorative — no new
              // interaction, no layout change to the card/hero above.
              const SizedBox(height: 28),
              _buildBottomBrandFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Bottom brand footer ──────────────────────────────────

  Widget _buildBottomBrandFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 8,
            children: const [
              _TrustBadge(
                icon: Icons.verified_outlined,
                label: 'Verified Listings',
              ),
              _TrustBadge(icon: Icons.lock_outline, label: 'Secure & Private'),
              _TrustBadge(
                icon: Icons.support_agent_rounded,
                label: '24/7 Support',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '© ${DateTime.now().year} PropCid · All rights reserved',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11.5,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────
  //
  // Compact by design now (per explicit direction superseding the earlier,
  // taller mockup-literal pass): a small right-side photo accent — never
  // full-bleed, so it cannot dominate the screen the way the previous
  // pass's cover photo did — a strong white wash over the whole hero, and a
  // height that scales gently with the viewport instead of the previous
  // 230–340px range.

  // `propcid_logo_trimmed.png` (referenced here previously) does not exist
  // in this checkout — only `propcid_logo.png` does, and it's the one the
  // rest of the app's branding (Home header, splash) already uses. Pointed
  // at that file instead so this screen actually builds.
  static const String _logoAssetPath = 'assets/branding/propcid_logo.png';
  // Real pixel size of that asset (862×203 px) — used to size the logo by
  // width alone via `AspectRatio`, so both call sites below stay
  // pixel-faithful to the source file without hand-tuned height numbers.
  static const double _logoAspectRatio = 862 / 203;

  /// `Image.asset` with a real accessible label, matching the "PropCid"
  /// name a screen-reader user would expect — a bare decorative image would
  /// otherwise announce nothing at all.
  Widget _logoImage({required double width}) {
    return Semantics(
      label: 'PropCid',
      image: true,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: _logoAspectRatio,
          child: Image.asset(_logoAssetPath, fit: BoxFit.contain),
        ),
      ),
    );
  }

  /// What's left of the hero once the keyboard is open — see `build`'s
  /// `AnimatedSize`. No photo, no headline, no tagline, just the wordmark,
  /// so the form below gets essentially all of the space the keyboard
  /// didn't take.
  Widget _buildCompactLogoBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        // ~130px wide at a ~4:1 aspect ratio is a ~32px-tall logo; with the
        // 14px padding above and below that lands the whole bar in the
        // "approximately 44–56px" compact-header range this is meant to hit.
        child: _logoImage(width: 130),
      ),
    );
  }

  Widget _buildHero() {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    // Compact per explicit direction: was `(screenHeight * 0.36).clamp(230,
    // 340)`; the whole point of this pass is that the hero must never again
    // reserve that much space out from under the form.
    final double heroHeight = (screenHeight * 0.22).clamp(160.0, 190.0);
    // The text column no longer shares the hero with a separate photo box
    // (that hard-edged strip was the seam) — it just needs to stay clear of
    // where the gradient below has fully revealed the photo, so it keeps
    // roughly the same width the old strip-based layout left it.
    final double maxTextWidth = screenWidth * 0.66 - 24;

    return AnimatedBuilder(
      animation: _headerController,
      builder: (context, child) {
        // A `minHeight`, not a fixed height: enlarged text scaling can make
        // the wordmark/headline/subtitle column taller than `heroHeight` —
        // a fixed `SizedBox` would rather overflow than yield, so this lets
        // the hero grow to fit instead.
        return SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: heroHeight),
            child: Stack(
              // Anchors the (non-positioned) text block to the *bottom* of
              // this min-height box. Its own `Column` always sizes to fit
              // its content (`mainAxisSize.min`), so without this the block
              // would sit at the Stack's default top-left instead — any
              // slack between `heroHeight` and the content's real height
              // now collects above the logo rather than below the tagline,
              // which is what keeps the gap before the form card fixed at
              // this padding's own 22px instead of growing with that slack.
              alignment: Alignment.bottomLeft,
              children: [
                // The photo now sits behind the *entire* header — the
                // gradient below is what hides/reveals it, so there is no
                // box edge left for a seam to appear at. Alignment keeps
                // the crop on the villa's facade/windows, above the pool
                // and shrub lower in the frame.
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: _backgroundImageUrl,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.5),
                    placeholder: (context, url) =>
                        Container(color: AppColors.primaryLight),
                    errorWidget: (context, url, error) =>
                        Container(color: AppColors.primaryLight),
                  ),
                ),
                // A single smooth horizontal fade, not a flat wash: fully
                // opaque behind the text so it reads as a clean surface,
                // then a gradual reveal (not a uniform opacity drop, which
                // would just wash the photo out everywhere) down to fully
                // transparent, so the photo shows at full colour on the
                // right rather than looking faded.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFFF8F8FC),
                          Color(0xFFF8F8FC),
                          Color(0x40F8F8FC),
                          Color(0x00F8F8FC),
                        ],
                        stops: [0.0, 0.5, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxTextWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      // No effect on spacing (the column always sizes to
                      // its own content) — the actual bottom-anchoring is
                      // the enclosing `Stack`'s `alignment` above; this is
                      // just its natural default.
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FadeTransition(
                          opacity: _logoAnimation,
                          // Targets the 130–150px visible-width range.
                          child: _logoImage(width: 140),
                        ),
                        const SizedBox(height: 12),
                        FadeTransition(
                          opacity: _text1Animation,
                          child: Text(
                            'Your next home',
                            style: AppTextStyles.heading1.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.2,
                            ),
                          ),
                        ),
                        FadeTransition(
                          opacity: _text2Animation,
                          child: Text(
                            'starts here.',
                            style: AppTextStyles.heading1.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        FadeTransition(
                          opacity: _text2Animation,
                          child: Text(
                            'Discover. Explore. Own.',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Tab Bar ──────────────────────────────────────────────
  //
  // A compact custom segmented control matching the portal's two-tab
  // Mobile/Email `SignIn.tsx` layout (Mobile selected by default). Sign Up
  // is no longer a separate tab — it's a mode switch inside Email (see
  // `_emailMode`), matching the portal's Email-tab Sign up link.

  Widget _buildTabBar() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryLight, width: 1.2),
          ),
          child: Row(
            children: [
              _buildTabSegment(
                index: 0,
                icon: Icons.phone_outlined,
                label: 'Mobile',
              ),
              _buildTabSegment(
                index: 1,
                icon: Icons.email_outlined,
                label: 'Email',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabSegment({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tabController.animateTo(index)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected ? AppColors.primaryActionShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inline "Need help?" — shared chrome under every tab, matching the
  /// reference's persistent footer rather than being Sign-In-specific.
  /// Terms/Privacy links are deliberately not reproduced alongside it: no
  /// genuine destination for either exists yet (checked — every other
  /// "Terms"/"Privacy" mention in this app is plain checkbox-label text,
  /// never an actual route or URL), and a non-functional link was
  /// explicitly ruled out.
  Widget _buildHelpFooter() {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openHelpPanel,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.support_agent_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Need help?',
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Login Form ───────────────────────────────────────────

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back',
          style: AppTextStyles.heading1.copyWith(fontSize: 21),
        ),
        const SizedBox(height: 5),
        Text(
          'Sign in to continue your property journey.',
          style: AppTextStyles.body.copyWith(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _loginEmailCtrl,
          label: 'Email or username',
          hint: 'Enter your email or username',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.text,
          focusNode: _loginEmailFocus,
          // "Next" moves straight to Password — explicit `requestFocus`
          // rather than relying on implicit traversal order, so it's
          // deterministic (and directly testable). Password itself keeps
          // the default `done`, which only dismisses the keyboard.
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _loginPasswordFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _loginPasswordCtrl,
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          isPassword: true,
          passwordVisible: _loginPasswordVisible,
          onTogglePassword: () =>
              setState(() => _loginPasswordVisible = !_loginPasswordVisible),
          focusNode: _loginPasswordFocus,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _handleForgotPassword,
            child: const Text(
              'Forgot password?',
              style: TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildPrimaryButton(
          label: 'Sign In',
          onPressed: _isLoading ? null : _handleLogin,
        ),
        const SizedBox(height: 20),
        _buildDivider(),
        const SizedBox(height: 16),
        _buildGoogleButton(),
        const SizedBox(height: 20),
        // Switches the Email tab's own mode in place — no new route, no tab
        // change. A `Wrap`, not a `Row`: at 320px width or with enlarged
        // text scaling the two pieces need to be able to fall onto separate
        // lines rather than force an unbounded-width overflow.
        //
        // The `Center` is load-bearing, not decorative: this `Column` uses
        // `crossAxisAlignment.start`, so a bare `Wrap` shrink-wraps to its
        // own content width and sits flush left regardless of its own
        // `WrapAlignment.center` — that param only centers content *within*
        // whatever width the Wrap already has, and without `Center` giving
        // it the full row width, there is no slack left to center into.
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'New to PropCid? ',
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _emailMode = _EmailMode.signUp),
                child: Text(
                  'Sign up',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Sign Up Form ─────────────────────────────────────────
  // Portal parity: email only, shown as a mode inside the Email tab (not a
  // separate tab). Full Name + User Type are collected after the magic link
  // is confirmed and a session exists (AccountTypeScreen) — there is no
  // role/type choice here, and never a Buyer/Seller one.

  Widget _buildSignUpForm() {
    if (_signUpEmailSent) {
      return _buildSignUpConfirmationState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          controller: _signUpEmailCtrl,
          label: 'Email',
          hint: 'you@example.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 22),
        _buildPrimaryButton(
          label: 'Create Account',
          onPressed: _isLoading ? null : _handleSignUp,
        ),
        const SizedBox(height: 20),
        _buildDivider(),
        const SizedBox(height: 16),
        _buildGoogleButton(),
        const SizedBox(height: 20),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _emailMode = _EmailMode.signIn),
                child: Text(
                  'Sign in',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpConfirmationState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        const Text(
          'Check your email',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a confirmation link to ${_signUpSentTo ?? ''}. Tap it on this device to continue.',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _isLoading ? null : _handleResendSignUpEmail,
            child: Text(
              _isLoading ? 'Sending…' : 'Resend email',
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Phone Form ───────────────────────────────────────────
  // One unified entry point regardless of sign-in vs sign-up: the backend
  // creates the account if the phone is new, or logs the user in if it
  // already exists — there is no separate "phone sign up" step.

  Widget _buildPhoneForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          controller: _phoneCtrl,
          label: 'Phone number',
          hint: '10-digit mobile number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 4),
        const Text(
          'We will text you a 6-digit code.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'Send OTP',
          onPressed: _isLoading ? null : _handleSendOtp,
        ),
        const SizedBox(height: 20),
        _buildDivider(),
        const SizedBox(height: 16),
        _buildGoogleButton(),
      ],
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool passwordVisible = false,
    VoidCallback? onTogglePassword,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    // `done` on every field except where a call site opts into `next` —
    // `done`'s Enter/Return never submits anything on its own; only the
    // Sign In button calls `_handleLogin`.
    TextInputAction textInputAction = TextInputAction.done,
    ValueChanged<String>? onSubmitted,
  }) {
    // Matches the reference: a persistent label above the field, and a
    // separate (usually more specific) hint painted inside it once it's
    // empty. Previously `hint` was accepted but never used — `label` was
    // painted as the visible hintText instead, so the two arguments always
    // showed the same string no matter what `hint` actually said. Fixed
    // here in presentation only: same controller, same keyboardType, same
    // obscureText/onTogglePassword wiring, same validation (nothing here
    // participates in it either before or after).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: isPassword && !passwordVisible,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
            prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
            suffixIcon: isPassword
                ? IconButton(
                    onPressed: onTogglePassword,
                    icon: Icon(
                      passwordVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryLight,
                width: 1.2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryLight,
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.6,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  /// Delegates to [_AuthPrimaryButton] rather than the shared `PremiumButton`
  /// — same call signature as before (label/onPressed/icon), so every call
  /// site above is untouched, but `PremiumButton` itself (used across the
  /// rest of the app) is never modified. The reference's CTA reads "Sign
  /// In →" — label, then a trailing arrow — which `PremiumButton` cannot
  /// produce: it always renders its `icon` *before* the label. Building a
  /// small auth-local widget for the trailing-icon layout was the
  /// alternative explicitly allowed over changing `PremiumButton` globally.
  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon = Icons.arrow_forward_rounded,
  }) {
    return _AuthPrimaryButton(
      label: label,
      onPressed: onPressed,
      isLoading: _isLoading,
      icon: icon,
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.hairline)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: (_isLoading || _googleOAuthStarting)
            ? null
            : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: const BorderSide(color: AppColors.primaryLight, width: 1.2),
          backgroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceMuted,
        ),
        // Explicit centered Row rather than `.icon()`'s own layout, so the
        // icon+label group is guaranteed centered as a unit — matching the
        // target rather than relying on the constructor's default padding.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _googleOAuthStarting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SvgPicture.string(_googleLogoSvg, width: 20, height: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _googleOAuthStarting
                    ? 'Opening Google…'
                    : 'Continue with Google',
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 14,
                  // Stronger than the previous w500, matching the target.
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auth-local primary CTA. Reproduces `PremiumButton`'s gradient/glow/
/// loading treatment (that file is untouched and still used everywhere
/// else), but with the label truly centered in the button regardless of
/// the icon — `PremiumButton` centers the icon-and-label *group* as one
/// unit, which visually off-centers the label whenever an icon is present.
/// The target centers "Sign In" on its own and pins the arrow near the
/// button's right inset instead.
class _AuthPrimaryButton extends StatelessWidget {
  const _AuthPrimaryButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.primaryGlow,
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  // Centered independently of the arrow, not as a group
                  // with it — this is the whole point of the `Stack`
                  // instead of `PremiumButton`'s single centered `Row`.
                  Center(child: Text(label, style: AppTextStyles.button)),
                  if (icon != null)
                    Positioned(
                      right: 18,
                      child: Icon(icon, size: 18, color: Colors.white),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One small icon+label pair used in the bottom brand footer's trust row.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textHint),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 11.5,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}
