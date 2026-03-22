import 'package:calibre_touch/utils/constants.dart';
import 'package:flutter/material.dart';
import '../widgets/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  PageSelector currentPage = PageSelector.text;
  late TabController tabController;
  int userCount = 3;

  @override
  void initState() {
    tabController = TabController(length: 2, vsync: this);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromRGBO(176, 179, 191, 1),
      appBar: AppBar(
        backgroundColor: Color.fromRGBO(199, 204, 219, 1),

        title: Text(widget.title, style: const TextStyle(color: Colors.black)),
        bottom: TabBar(
          controller: tabController,
          onTap: (index) => setState(
            () {
              currentPage = index == 0
                ? PageSelector.text
                : PageSelector.image;
                tabController.index = index;
            },
          ),
          tabs: [
            Tab(
              child: Text('Lista', style: TextStyle(color: Colors.black)),
            ),
            Tab(
              child: Text('Kép', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              setState(() {
                currentPage = PageSelector.text;
                tabController.index = 0;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.share),
            onPressed: () {
              setState(() {
                currentPage = PageSelector.image;
                tabController.index = 1;
              });
            },
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Text('Szöveg'),
                onTap: () {
                  setState(() {
                    currentPage = PageSelector.text;
                  });
                },
              ),
              PopupMenuItem(
                child: Text('Kép'),
                onTap: () {
                  setState(() {
                    currentPage = PageSelector.image;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Color.fromRGBO(199, 204, 219, 1),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color.fromRGBO(199, 204, 219, 1),
              ),
              child: FlutterLogo(textColor: Colors.white, size: 50),
            ),
            ListTile(
              title: const Text('Szöveg'),
              onTap: () {
                setState(() {
                  currentPage = PageSelector.text;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Kép'),
              onTap: () {
                setState(() {
                  currentPage = PageSelector.image;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Szöveg'),
            BottomNavigationBarItem(icon: Icon(Icons.share), label: 'Kép'),
          ],
          currentIndex: currentPage.index,
          onTap: (index) {
            setState(() {
              currentPage = PageSelector.values[index];
              tabController.index = index;
            });
          },
        ),
      
    
      body: currentPage == PageSelector.text
          ? listViewPage()
          : Image.network('https://randomuser.me/api/portraits/women/1.jpg'),
    );
  }

  Widget listViewPage() => ListView(
    children: <Widget>[
      for (var i = 0; i < userCount; i++)
        UserItem(
          name: 'Mr. Luca Lewis',
          email: 'luca.lewis@me.com',
          imageurl: 'https://randomuser.me/api/portraits/women/$i.jpg',
        ),
    ],
  );

  void incrementCounter() => setState(() => userCount++);
}
