import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';

// ─────────────────────────────────────────────
//  Data model for each floating orbital icon
// ─────────────────────────────────────────────
class _OrbitalIcon {
  final IconData icon;
  final double orbitRadius; // distance from centre
  final double startAngle; // radians – where on the orbit it begins
  final double orbitSpeed; // radians per second (positive = CCW)
  final double size; // icon box side length
  final Color glowColor;
  final Duration entryDelay;

  const _OrbitalIcon({
    required this.icon,
    required this.orbitRadius,
    required this.startAngle,
    required this.orbitSpeed,
    required this.size,
    required this.glowColor,
    required this.entryDelay,
  });
}

// ─────────────────────────────────────────────
//  Particle data – tiny ambient glowing dots
// ─────────────────────────────────────────────
class _Particle {
  final double x; // 0-1 fraction of screen width
  final double y; // 0-1 fraction of screen height
  final double radius;
  final double opacity;
  final Duration delay;
  final Duration duration;

  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.delay,
    required this.duration,
  });
}

// ─────────────────────────────────────────────
//  Main SplashScreen widget
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controllers
  late AnimationController _orbitController; // drives continuous orbit loop
  late AnimationController _pulseController; // drives logo glow pulse
  late AnimationController _exitController; // drives fade-out before navigate

  // Fixed orbital icon definitions
  static const List<_OrbitalIcon> _icons = [
    _OrbitalIcon(
      icon: Icons.house_rounded,
      orbitRadius: 118,
      startAngle: -math.pi / 2, // top
      orbitSpeed: 0.28,
      size: 46,
      glowColor: Color(0xFFF97316), // PropCid orange
      entryDelay: Duration(milliseconds: 400),
    ),
    _OrbitalIcon(
      icon: Icons.apartment_rounded,
      orbitRadius: 118,
      startAngle: math.pi / 2, // bottom
      orbitSpeed: 0.28,
      size: 44,
      glowColor: Color(0xFFFB923C), // medium orange
      entryDelay: Duration(milliseconds: 550),
    ),
    _OrbitalIcon(
      icon: Icons.location_on_rounded,
      orbitRadius: 118,
      startAngle: 0, // right
      orbitSpeed: 0.28,
      size: 42,
      glowColor: Color(0xFFC2410C), // deep rust orange
      entryDelay: Duration(milliseconds: 700),
    ),
    _OrbitalIcon(
      icon: Icons.vpn_key_rounded,
      orbitRadius: 118,
      startAngle: math.pi, // left
      orbitSpeed: 0.28,
      size: 42,
      glowColor: Color(0xFFFDBA74), // light warm orange
      entryDelay: Duration(milliseconds: 850),
    ),
  ];

  // Ambient particles – deterministic positions (no Random to keep
  // the build pure and reproducible on hot restart)
  static const List<_Particle> _particles = [
    _Particle(
      x: 0.08,
      y: 0.12,
      radius: 2.5,
      opacity: 0.6,
      delay: Duration.zero,
      duration: Duration(milliseconds: 2200),
    ),
    _Particle(
      x: 0.85,
      y: 0.18,
      radius: 2.0,
      opacity: 0.5,
      delay: Duration(milliseconds: 300),
      duration: Duration(milliseconds: 2800),
    ),
    _Particle(
      x: 0.22,
      y: 0.78,
      radius: 3.0,
      opacity: 0.4,
      delay: Duration(milliseconds: 600),
      duration: Duration(milliseconds: 2400),
    ),
    _Particle(
      x: 0.91,
      y: 0.82,
      radius: 2.2,
      opacity: 0.55,
      delay: Duration(milliseconds: 900),
      duration: Duration(milliseconds: 2600),
    ),
    _Particle(
      x: 0.15,
      y: 0.45,
      radius: 1.8,
      opacity: 0.4,
      delay: Duration(milliseconds: 200),
      duration: Duration(milliseconds: 3000),
    ),
    _Particle(
      x: 0.78,
      y: 0.55,
      radius: 2.8,
      opacity: 0.5,
      delay: Duration(milliseconds: 750),
      duration: Duration(milliseconds: 2500),
    ),
    _Particle(
      x: 0.50,
      y: 0.08,
      radius: 2.0,
      opacity: 0.45,
      delay: Duration(milliseconds: 400),
      duration: Duration(milliseconds: 2700),
    ),
    _Particle(
      x: 0.55,
      y: 0.92,
      radius: 2.4,
      opacity: 0.5,
      delay: Duration(milliseconds: 1100),
      duration: Duration(milliseconds: 2300),
    ),
    _Particle(
      x: 0.35,
      y: 0.22,
      radius: 1.6,
      opacity: 0.35,
      delay: Duration(milliseconds: 500),
      duration: Duration(milliseconds: 2900),
    ),
    _Particle(
      x: 0.70,
      y: 0.30,
      radius: 2.2,
      opacity: 0.45,
      delay: Duration(milliseconds: 800),
      duration: Duration(milliseconds: 2100),
    ),
    _Particle(
      x: 0.12,
      y: 0.65,
      radius: 1.9,
      opacity: 0.4,
      delay: Duration(milliseconds: 1000),
      duration: Duration(milliseconds: 2600),
    ),
    _Particle(
      x: 0.88,
      y: 0.45,
      radius: 2.6,
      opacity: 0.5,
      delay: Duration(milliseconds: 150),
      duration: Duration(milliseconds: 2400),
    ),
  ];

  bool _iconsVisible = false;

  @override
  void initState() {
    super.initState();

    // Immersive full-screen: hide system UI during splash
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Orbit: continuous, loops forever until exit
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(
        seconds: 12,
      ), // one full revolution = 12 s (slow, elegant)
    )..repeat();

    // Logo glow pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // Exit fade-out
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Show icons after entry animations settle
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _iconsVisible = true);
    });

    // Navigate after 3 s total
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) _beginExit();
    });
  }

  Future<void> _beginExit() async {
    // Restore system UI before navigating
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _exitController.forward();
    if (mounted) _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    final prefs = await SharedPreferences.getInstance();

    final seenOnboarding = prefs.getBool('onboarding_done') ?? false;

    if (!mounted) return;

    if (!seenOnboarding) {
      Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    // From here on, AuthProvider is the single owner of where the user
    // goes: it has been resolving (or has already resolved) the session
    // and profile in the background since it was constructed in `main()`,
    // via the same `BehaviorSubject`-backed auth stream that fires
    // `initialSession` on cold start — typically well before this 3-second
    // animation even finishes. If a destination is already known,
    // `enableNavigation()` acts on it immediately; otherwise this
    // screen's own looping animation is the "still resolving" loader until
    // the profile fetch lands and AuthProvider navigates on its own.
    //
    // Deliberately not called until onboarding is confirmed seen — a
    // genuinely first launch must show onboarding regardless of whatever
    // auth destination might otherwise resolve to.
    context.read<AuthProvider>().enableNavigation();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _orbitController.dispose();
    _pulseController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  // ─── BUILD ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF17110A),
      body: AnimatedBuilder(
        animation: _exitController,
        builder: (context, child) {
          return Opacity(opacity: 1.0 - _exitController.value, child: child);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 – background gradient
            _buildBackground(),

            // Layer 2 – ambient particles
            ..._buildParticles(size),

            // Layer 3 – large diffuse glow rings behind everything
            _buildAmbientRings(size),

            // Layer 4 – orbital icons
            if (_iconsVisible) _buildOrbitingIcons(size),

            // Layer 5 – center logo + text
            _buildCenterContent(),

            // Layer 6 – bottom tagline strip
            _buildBottomTagline(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LAYER 1: Background
  // ─────────────────────────────────────────────
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.45, 0.75, 1.0],
          colors: [
            Color(0xFF17110A), // near-black warm charcoal
            Color(0xFF241A0E),
            Color(0xFF2E1F0F),
            Color(0xFF120D07),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LAYER 2: Ambient glowing particles
  // ─────────────────────────────────────────────
  List<Widget> _buildParticles(Size size) {
    return _particles.map((p) {
      return Positioned(
        left: p.x * size.width,
        top: p.y * size.height,
        child:
            Container(
                  width: p.radius * 2,
                  height: p.radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(p.opacity),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(p.opacity * 0.8),
                        blurRadius: p.radius * 4,
                      ),
                    ],
                  ),
                )
                .animate(delay: p.delay)
                .fadeIn(duration: 800.ms)
                .then()
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(
                  begin: p.opacity * 0.3,
                  duration: p.duration,
                  curve: Curves.easeInOut,
                ),
      );
    }).toList();
  }

  // ─────────────────────────────────────────────
  // LAYER 3: Ambient diffuse glow rings
  // ─────────────────────────────────────────────
  Widget _buildAmbientRings(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value; // 0→1→0
        return Stack(
          children: [
            // Outer large diffuse ring
            Positioned(
              left: cx - 220,
              top: cy - 220,
              child: Container(
                width: 440,
                height: 440,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.08 + 0.04 * pulse),
                      AppColors.primary.withOpacity(0.03 + 0.02 * pulse),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            // Inner tighter glow
            Positioned(
              left: cx - 130,
              top: cy - 130,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.18 + 0.08 * pulse),
                      AppColors.primary.withOpacity(0.06 + 0.03 * pulse),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Subtle orbit track ring (thin circle outline)
            Positioned(
              left: cx - 118,
              top: cy - 118,
              child: Opacity(
                opacity: 0.08 + 0.04 * pulse,
                child: Container(
                  width: 236,
                  height: 236,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.5),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // LAYER 4: Orbiting property icons
  // ─────────────────────────────────────────────
  Widget _buildOrbitingIcons(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    return AnimatedBuilder(
      animation: _orbitController,
      builder: (context, _) {
        final elapsedAngle = _orbitController.value * 2 * math.pi;

        return Stack(
          children: _icons.asMap().entries.map((entry) {
            final icon = entry.value;
            final angle =
                icon.startAngle + (elapsedAngle * icon.orbitSpeed / 0.28);
            final dx = cx + icon.orbitRadius * math.cos(angle) - icon.size / 2;
            final dy = cy + icon.orbitRadius * math.sin(angle) - icon.size / 2;

            return Positioned(
              left: dx,
              top: dy,
              child:
                  _OrbitalIconWidget(
                        icon: icon,
                        pulseController: _pulseController,
                      )
                      .animate(delay: icon.entryDelay)
                      .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                      .scale(
                        begin: const Offset(0, 0),
                        end: const Offset(1, 1),
                        duration: 700.ms,
                        curve: Curves.easeOutBack,
                      ),
            );
          }).toList(),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // LAYER 5: Center logo + text stack
  // ─────────────────────────────────────────────
  Widget _buildCenterContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Logo container ──────────────────
          _buildLogoContainer()
              .animate()
              .fadeIn(duration: 700.ms, delay: 100.ms, curve: Curves.easeOut)
              .scale(
                begin: const Offset(0.0, 0.0),
                end: const Offset(1.0, 1.0),
                duration: 900.ms,
                delay: 100.ms,
                curve: Curves.easeOutBack,
              ),

          const SizedBox(height: 36),

          // ── App name glass pill ─────────────
          _buildAppNamePill()
              .animate()
              .fadeIn(duration: 600.ms, delay: 600.ms, curve: Curves.easeOut)
              .slideY(
                begin: 0.4,
                end: 0.0,
                duration: 700.ms,
                delay: 600.ms,
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: 14),

          // ── Tagline ─────────────────────────
          Text(
                'Find Your Perfect Property',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w300,
                ),
              )
              .animate()
              .fadeIn(duration: 600.ms, delay: 900.ms, curve: Curves.easeOut)
              .slideY(
                begin: 0.5,
                end: 0.0,
                duration: 700.ms,
                delay: 900.ms,
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }

  Widget _buildLogoContainer() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFDBA74), // lighter orange
                Color(0xFFF97316), // brand primary
                Color(0xFFC2410C), // deep orange
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              // Inner tight glow
              BoxShadow(
                color: AppColors.primary.withOpacity(0.55 + 0.15 * pulse),
                blurRadius: 24 + 12 * pulse,
                spreadRadius: 2,
              ),
              // Outer diffuse glow
              BoxShadow(
                color: AppColors.primary.withOpacity(0.25 + 0.10 * pulse),
                blurRadius: 48 + 16 * pulse,
                spreadRadius: 6,
              ),
              // Subtle dark shadow for depth
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      },
      child: const Icon(Icons.home_work_rounded, size: 44, color: Colors.white),
    );
  }

  // The real PropCid wordmark (862×203 px, transparent, already
  // brand-orange) — reads clearly on the dark splash background as-is, so
  // no recolouring shader is applied over it; that would just repaint the
  // actual artwork rather than presenting it.
  static const double _wordmarkAspectRatio = 862 / 203;

  Widget _buildAppNamePill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Semantics(
          label: 'PropCid',
          image: true,
          child: SizedBox(
            height: 42,
            child: AspectRatio(
              aspectRatio: _wordmarkAspectRatio,
              child: Image.asset(
                'assets/branding/propcid_logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LAYER 6: Bottom strip — powered-by / version
  // ─────────────────────────────────────────────
  Widget _buildBottomTagline() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child:
          Column(
            children: [
              // Thin divider line
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 100),
                child: Container(
                  height: 0.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Premium Real Estate Experience',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ).animate().fadeIn(
            duration: 700.ms,
            delay: 1200.ms,
            curve: Curves.easeOut,
          ),
    );
  }
}

// ─────────────────────────────────────────────
//  Individual orbital icon widget
//  (separated to keep build() clean)
// ─────────────────────────────────────────────
class _OrbitalIconWidget extends StatelessWidget {
  final _OrbitalIcon icon;
  final AnimationController pulseController;

  const _OrbitalIconWidget({required this.icon, required this.pulseController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final pulse = pulseController.value;
        return Container(
          width: icon.size,
          height: icon.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.06),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.18 + 0.06 * pulse),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: icon.glowColor.withOpacity(0.35 + 0.15 * pulse),
                blurRadius: 14 + 6 * pulse,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            icon.icon,
            size: icon.size * 0.46,
            color: Colors.white.withOpacity(0.88),
          ),
        );
      },
    );
  }
}
