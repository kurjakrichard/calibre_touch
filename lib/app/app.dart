import 'package:flutter/material.dart';

import '../pages/pages.dart';

class CalibreTouch extends StatelessWidget {
  const CalibreTouch({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Calibre Touch',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const HomePage(title: 'Calibre Touch'),
    );
  }
}
