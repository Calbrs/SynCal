import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_routes.dart';

const double _kBottomPanelHeightFraction = 0.25;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();

  // Drives the staggered "in" animation when the screen first appears.
  late final AnimationController _entranceController;

  // Drives the "out" animation right before we leave the screen.
  late final AnimationController _exitController;

  double _page = 0;

  final List<_OnboardItem> _pages = [
    _OnboardItem(
      imagePath: 'assets/images/onboarding_contacts.jpg',
      fallbackIcon: Icons.contacts_rounded,
      title: 'Sync Contacts',
      subtitle:
          'Organize and synchronize your contacts effortlessly across your workflow.',
    ),
    _OnboardItem(
      imagePath: 'assets/images/onboarding_sms.jpg',
      fallbackIcon: Icons.sms_rounded,
      title: 'Schedule SMS',
      subtitle:
          'Create and schedule messages to be delivered exactly when needed.',
    ),
    _OnboardItem(
      imagePath: 'assets/images/onboarding_security.jpg',
      fallbackIcon: Icons.security_rounded,
      title: 'Private & Secure',
      subtitle:
          'Your information remains under your control with transparent permissions.',
    ),
  ];

  int get _currentPage => _page.round();

  @override
  void initState() {
    super.initState();

    _pageController.addListener(() {
      setState(() {
        _page = _pageController.page ?? _pageController.initialPage.toDouble();
      });
    });

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  // Small helper to build a staggered fade + slide animation out of the
  // shared entrance controller, so each element appears in sequence.
  Animation<double> _stagger(double start, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _fadeSlideIn({
    required Animation<double> animation,
    required Widget child,
    double offset = 24,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offset * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Future<void> _finishOnboarding() async {
    if (_exitController.isAnimating || _exitController.isCompleted) return;

    await _exitController.forward();

    final settings = Hive.box('settings');
    await settings.put('hasSeenOnboarding', true);

    if (!mounted) return;
    context.go(AppRoutes.auth);
  }

  void _onContinuePressed() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPanelHeight = screenHeight * _kBottomPanelHeightFraction;

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: AnimatedBuilder(
        animation: _exitController,
        builder: (context, child) {
          final exitValue = _exitController.value;
          return Opacity(
            opacity: 1 - exitValue,
            child: Transform.scale(
              scale: 1 - (exitValue * 0.05),
              child: child,
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed image, occupying the ~75% above the bottom panel.
            // (It technically extends the full screen height; the opaque
            // bottom panel below simply paints over the last 25% of it.)
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                itemBuilder: (_, index) {
                  final item = _pages[index];

                  // Distance from this page to the current scroll position
                  // drives a subtle parallax scale + fade as you swipe.
                  final distance = (index - _page).abs().clamp(0.0, 1.0);
                  final scale = 1 + (distance * 0.08);
                  final opacity = 1 - (distance * 0.5);

                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: _OnboardBackgroundImage(item: item),
                    ),
                  );
                },
              ),
            ),

            // ── Top scrim + logo + welcome message, floating over the image.
            // A blurred, fading gradient sits behind the text so it stays
            // legible no matter what the underlying photo looks like.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _fadeSlideIn(
                animation: _stagger(0.0, 0.5),
                offset: -20,
                child: _TopScrim(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 28),
                      child: Center(
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              'assets/icons/syncal.png',
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Welcome to SynCal',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Stay in Sync. Seamlessly.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Blurred fade band bridging the image into the bottom panel.
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPanelHeight,
              height: 130,
              child: const IgnorePointer(child: _BottomBlendScrim()),
            ),

            // ── Fixed bottom panel: page title/subtitle, dots, and button.
            // Always exactly 25% of the screen height.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomPanelHeight,
              child: _fadeSlideIn(
                animation: _stagger(0.35, 0.9),
                offset: 30,
                child: Container(
                  decoration: const BoxDecoration(color: Color(0xFF1C1C1E)),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(height: 6),

                          // Title + subtitle for the current page, cross-fading
                          // as you swipe between onboarding items.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.15),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              key: ValueKey(_currentPage),
                              children: [
                                Text(
                                  _pages[_currentPage].title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _pages[_currentPage].subtitle,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Dot indicator.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _pages.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: _currentPage == index ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _currentPage == index
                                      ? Colors.white
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ),

                          // Continue / Get Started button.
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _onContinuePressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Text(
                                  isLastPage ? 'Get Started' : 'Continue',
                                  key: ValueKey(isLastPage),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A frosted, fading scrim used behind the logo + welcome text so it stays
/// readable over any photo. Blur intensity and darkness both fade out
/// toward the bottom edge of the band, via a gradient-masked BackdropFilter.
class _TopScrim extends StatelessWidget {
  final Widget child;

  const _TopScrim({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.black.withValues(alpha: 0.01)),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The blurred fade band that visually blends the full-bleed image into the
/// solid bottom panel, so the transition feels soft instead of a hard cut.
class _BottomBlendScrim extends StatelessWidget {
  const _BottomBlendScrim();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(color: Colors.black.withValues(alpha: 0.01)),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1C1C1E).withValues(alpha: 0.0),
                  const Color(0xFF1C1C1E),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-bleed background image for a single onboarding page, loaded from a
/// bundled asset. Fades + scales in the first time it's built, and falls
/// back to a centered icon on the theme color if the asset is missing
/// (e.g. the file wasn't added to pubspec.yaml yet).
class _OnboardBackgroundImage extends StatefulWidget {
  final _OnboardItem item;

  const _OnboardBackgroundImage({required this.item});

  @override
  State<_OnboardBackgroundImage> createState() =>
      _OnboardBackgroundImageState();
}

class _OnboardBackgroundImageState extends State<_OnboardBackgroundImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: _controller.value,
            child: Transform.scale(
              scale: 1.05 - (0.05 * _controller.value),
              child: Image.asset(
                widget.item.imagePath,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      widget.item.fallbackIcon,
                      size: 72,
                      color: Colors.white24,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OnboardItem {
  final String imagePath;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;

  const _OnboardItem({
    required this.imagePath,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
  });
}