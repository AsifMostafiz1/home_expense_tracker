import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../utils/app_constant.dart';
import '../../../utils/app_theme.dart';
import '../controller/splash_controller.dart';

/// The splash keeps the background quiet — near-white lavender in light mode,
/// deep calm violet in dark mode — and lets one element carry the brand: a
/// vivid gradient tile that glows softly while the copy eases in beneath it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Staggered entrance. Finishes comfortably inside the controller's own
  /// 2 second delay, so nothing is cut off mid-animation.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Slow breathing halo behind the logo; also drives the loading shuttle.
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  late final Animation<double> _logoScale = Tween<double>(
    begin: 0.84,
    end: 1,
  ).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
    ),
  );

  // Built once — the mark rebuilds every frame, so it must not allocate.
  late final Animation<double> _markFade = _step(0, 0.55);
  late final Animation<double> _nameFade = _step(0.30, 0.75);
  late final Animation<double> _taglineFade = _step(0.45, 0.90);
  late final Animation<double> _footerFade = _step(0.60, 1);

  @override
  void initState() {
    super.initState();
    Get.put(SplashController());
    _intro.forward();
    _halo.repeat(reverse: true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _halo.dispose();
    super.dispose();
  }

  Animation<double> _step(double begin, double end) => CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  /// The brand gradient every accent on this screen is cut from.
  static final List<Color> _brand = [
    Color.lerp(AppTheme.primaryLight, AppTheme.primaryColor, 0.25)!,
    AppTheme.primaryColor,
  ];

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // Quiet field: barely-tinted white, or a violet-black that keeps the
    // brand hue without shouting it.
    final Color bgTop = dark ? const Color(0xFF130D1D) : Colors.white;
    final Color bgBottom =
        dark ? const Color(0xFF1F1332) : const Color(0xFFF2ECFD);
    final Color title = dark ? Colors.white : const Color(0xFF1A1425);
    final Color tagline =
        dark ? Colors.white.withOpacity(0.68) : const Color(0xFF6E6580);
    final Color version =
        dark ? Colors.white.withOpacity(0.38) : const Color(0xFFA29BB1);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: bgBottom,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, bgBottom],
            ),
          ),
          child: Stack(
            children: [
              // Soft brand-tinted light pooling in opposite corners.
              Positioned(
                top: -160,
                right: -120,
                child: _Orb(
                  size: 380,
                  color: AppTheme.primaryLight.withOpacity(dark ? 0.16 : 0.22),
                ),
              ),
              Positioned(
                bottom: -180,
                left: -140,
                child: _Orb(
                  size: 430,
                  color: AppTheme.primaryLight.withOpacity(dark ? 0.12 : 0.30),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    _buildMark(dark),
                    const SizedBox(height: 36),
                    _RiseIn(
                      animation: _nameFade,
                      child: Text(
                        'app_name'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: title,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _RiseIn(
                      animation: _taglineFade,
                      offset: 14,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          'app_tagline'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                            color: tagline,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 4),
                    _RiseIn(
                      animation: _footerFade,
                      offset: 10,
                      child: Column(
                        children: [
                          _LoadingBar(
                            animation: _halo,
                            trackColor: dark
                                ? Colors.white.withOpacity(0.14)
                                : AppTheme.primaryColor.withOpacity(0.10),
                            shuttleColors: dark
                                ? [
                                    Colors.white.withOpacity(0.25),
                                    Colors.white,
                                    Colors.white.withOpacity(0.25),
                                  ]
                                : [
                                    _brand.first.withOpacity(0.25),
                                    AppTheme.primaryColor,
                                    _brand.first.withOpacity(0.25),
                                  ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'v${AppConstant.appVersion.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: version,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The logo mark: a brand-gradient squircle inside a faint ring, lit by a
  /// halo that breathes on its own controller.
  Widget _buildMark(bool dark) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _halo]),
      builder: (context, child) {
        final double glow = 0.22 + (_halo.value * 0.26);

        return Opacity(
          opacity: _markFade.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _logoScale.value,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark
                      ? Colors.white.withOpacity(0.10)
                      : AppTheme.primaryColor.withOpacity(0.10),
                  width: 1.5,
                ),
              ),
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _brand,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor
                          .withOpacity(dark ? glow : glow * 0.65),
                      blurRadius: 48,
                      spreadRadius: 4,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A radial pool of light that fades out to nothing at its edge.
class _Orb extends StatelessWidget {
  final double size;
  final Color color;

  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

/// Fade + lift, driven by an already-curved [animation].
class _RiseIn extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double offset;

  const _RiseIn({
    required this.animation,
    required this.child,
    this.offset = 18,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, offset * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A slim shuttle that slides back and forth — quieter than a spinner and it
/// reads as progress rather than as a stall.
class _LoadingBar extends StatelessWidget {
  final Animation<double> animation;
  final Color trackColor;
  final List<Color> shuttleColors;

  const _LoadingBar({
    required this.animation,
    required this.trackColor,
    required this.shuttleColors,
  });

  @override
  Widget build(BuildContext context) {
    const double width = 132;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: width,
        height: 4,
        color: trackColor,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final double t =
                Curves.easeInOut.transform(animation.value) * 2 - 1;
            return Align(alignment: Alignment(t, 0), child: child);
          },
          child: Container(
            width: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: shuttleColors),
            ),
          ),
        ),
      ),
    );
  }
}
