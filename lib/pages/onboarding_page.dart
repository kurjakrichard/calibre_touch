import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  static OnboardingPage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const OnboardingPage();

  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => OnboardingPageState();
}

class OnboardingPageState extends ConsumerState<OnboardingPage> {
  int currentPage = 0;
  final _pageController = PageController(initialPage: 0);
  static const int _lastPage = 2;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() {
        currentPage = _pageController.page!.toInt();
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finishOnboarding() {
    ref.read(sharedUtilityProvider).setIsFirstRun(complete: true);
    context.goNamed(Routes.home.name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      bottomSheet: Container(
        color: buttonColor,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 80,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            currentPage > 0
                ? TextButton(
                    onPressed: () {
                      _pageController.previousPage(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut);
                    },
                    child: Text(
                      l10n.back,
                      style: const TextStyle(color: splashTextColor),
                    ))
                : Text(
                    '  ${l10n.back}     ',
                    style: const TextStyle(color: buttonColor),
                  ),
            Center(
              child: SmoothPageIndicator(
                controller: _pageController,
                count: 3,
                effect:
                    const WormEffect(spacing: 16, activeDotColor: splashTextColor),
                onDotClicked: (index) => _pageController.animateToPage(index,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut),
              ),
            ),
            currentPage < _lastPage
                ? TextButton(
                    onPressed: () {
                      _pageController.nextPage(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut);
                    },
                    child: Text(
                      l10n.next,
                      style: const TextStyle(color: splashTextColor),
                    ),
                  )
                : TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      l10n.getStarted,
                      style: const TextStyle(color: splashTextColor),
                    ),
                  ),
          ],
        ),
      ),
      body: Container(
        padding: const EdgeInsets.only(bottom: 80),
        child: PageView(controller: _pageController, children: [
          firstPage(),
          secondPage(),
          thirdPage(),
        ]),
      ),
    );
  }

  Widget firstPage() {
    final l10n = context.l10n;
    return ListView(
      children: [
        Container(
          color: splashBackgroundColor,
          child: Center(
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.fitHeight,
              height: 300,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 40.0),
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Center(
            child: Text(
              l10n.welcome,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20),
          child: Wrap(alignment: WrapAlignment.center, children: [
            Text(
              l10n.onboardingIntro,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Wrap(alignment: WrapAlignment.center, children: [
            Text(
              l10n.onboardingStandalone,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ]),
        ),
      ],
    );
  }

  /// Second onboarding page: the library-folder picker ([SettingsForm]),
  /// embedded directly so first-time setup doubles as the settings screen.
  Widget secondPage() {
    return const SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: SettingsForm(),
    );
  }

  Widget thirdPage() {
    final l10n = context.l10n;
    return ListView(
      children: [
        Container(
          color: splashBackgroundColor,
          child: Center(
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.fitHeight,
              height: 300,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 40.0),
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Center(
            child: Text(
              l10n.allSet,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
          child: Center(
            child: Text(
              l10n.allSetDetails,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
