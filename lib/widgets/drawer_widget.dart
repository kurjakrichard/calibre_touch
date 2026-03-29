import 'package:calibre_touch/utils/utils.dart';
import 'package:flutter/material.dart';

class DrawerWidget extends StatelessWidget {
  const DrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: secondary,
      child: ListView(
        children: [
          SizedBox(
            height: 72,
            child: DrawerHeader(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    Image.asset(
                      'images/flutibre-icon.png',
                      height: 64,
                    ),
                    const Expanded(
                      child: Text(
                        'Calibre Touch',
                        style: TextStyle(
                            color: buttoncolor,
                            fontSize: 16,
                            height: 2,
                            overflow: TextOverflow.clip),
                      ),
                    ),
                  ],
                )),
          ),
        ],
      ),
    );
  }
}
