import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
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
    ref.read(sharedUtilityProvider).setOnboardingComplete(complete: true);
    context.goNamed(Routes.home.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomSheet: Container(
        color: buttoncolor,
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
                    child: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white),
                    ))
                : const Text(
                    '  Back     ',
                    style: TextStyle(color: buttoncolor),
                  ),
            Center(
              child: SmoothPageIndicator(
                controller: _pageController,
                count: 3,
                effect:
                    const WormEffect(spacing: 16, activeDotColor: Colors.white),
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
                    child: const Text(
                      'Next',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : TextButton(
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'Get Started',
                      style: TextStyle(color: Colors.white),
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
    return ListView(
      children: [
        Container(
          color: const Color.fromRGBO(28, 47, 67, 1),
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
          child: const Center(
            child: Text(
              'Welcome to Calibre Touch',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 20),
          child: Wrap(alignment: WrapAlignment.center, children: [
            Text(
              'Calibre library reader for touchscreen devices.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.0),
          child: Wrap(alignment: WrapAlignment.center, children: [
            Text(
              'Calibre touch can work as a standalone e-book library manager. This is not compatible Calibre.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ]),
        ),
      ],
    );
  }

  /// Second onboarding page: the settings form (library folder + theme),
  /// embedded directly so first-time setup doubles as the settings screen.
  Widget secondPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: const SettingsForm(),
    );
  }

  Widget thirdPage() {
    return ListView(
      children: [
        Container(
          color: const Color.fromRGBO(28, 47, 67, 1),
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
          child: const Center(
            child: Text(
              "You're all set!",
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
          child: const Center(
            child: Text(
              'Your library and appearance are ready to go. You can always revisit these from the menu.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
