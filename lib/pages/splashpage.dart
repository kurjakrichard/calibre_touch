import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'pages.dart';

class SplashPage extends StatefulWidget {
  static SplashPage builder(
    BuildContext context,
    GoRouterState state,
  ) =>
      const SplashPage();
  const SplashPage({super.key});

  @override
  SplashPageState createState() => SplashPageState();
}

class SplashPageState extends State<SplashPage> {
  startTimeout() {
    if (Platform.isWindows || Platform.isLinux) {
      return Timer(const Duration(seconds: 2), changeScreen);
    }

    changeScreen();
  }

  void changeScreen() {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const HomePage(),
        ));
  }

  @override
  void initState() {
    super.initState();
    startTimeout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(28, 47, 67, 1),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              'assets/logo.png',
              height: 400.0,
              width: 400.0,
            ),
          ],
        ),
      ),
    );
  }
}
