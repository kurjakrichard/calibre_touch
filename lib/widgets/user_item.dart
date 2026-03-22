import 'dart:math';

import 'package:flutter/material.dart';

class UserItem extends StatelessWidget {
  const UserItem({super.key, required this.name, required this.email, required this.imageurl,});

 final String name;
 final String email; 
 final String imageurl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Color.fromRGBO(223, 220, 221, 1),
          borderRadius: BorderRadius.all(Radius.circular(4.0)),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.25),
              blurRadius: 0.0,
              spreadRadius: 0.0,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        height: 70,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Image.network(
                imageurl
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                   name,
                    style: TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                   email,
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.0),
          ],
        ),
      ),
    );
  }
}


// return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
//       child: ListTile(
//         leading: Image.network('https://randomuser.me/api/portraits/women/84.jpg'),
//         title: Text('Mr. Luca Lewis'),        
//         subtitle: Text('luca.lewis@me.com'),
//         tileColor: Color.fromRGBO(247, 236, 225, 0.5),
//       ),
//     );