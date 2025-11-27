import 'package:calibre_touch/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'pages.dart';

class FirstRun extends StatefulWidget {
  static FirstRun builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const FirstRun();
  const FirstRun({super.key});

  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  int currentPage = 0;
  final _pageController = PageController(initialPage: 0);

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
                          duration: const Duration(microseconds: 500),
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
            TextButton(
              onPressed: () {
                _pageController.nextPage(
                    duration: const Duration(microseconds: 500),
                    curve: Curves.easeInOut);
              },
              child: const Text(
                'Next',
                style: TextStyle(color: Colors.white),
              ),
            )
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

  Widget secondPage() {
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
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(40.0),
          child: Wrap(children: [
            Center(
              child: Text(
                'Calibre touch can work as a standalone e-book library manager. This is not compatible Calibre.',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ]),
        ),
      ],
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
              'Welcome to Calibre Touch',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 20.0),
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: const Center(
            child: Text(
              'Calibre library reader',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: const Center(
            child: Text(
              'for touchscreen devices',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
