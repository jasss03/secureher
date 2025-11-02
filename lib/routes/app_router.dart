import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/sos/sos_screen.dart';
import '../features/map/safe_space_finder_screen.dart';
import '../features/tips/tips_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/women_essential/women_essential_screen.dart';
import '../widgets/global_sos_button.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    SosScreen(),
    SafeSpaceFinderScreen(),
    WomenEssentialScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent navigating back from the root app shell to splash/login
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Main content
            Positioned.fill(child: _pages[_index]),
            // Global SOS button overlay on all screens
            const Positioned(
              right: 16,
              bottom: 16,
              child: GlobalSosButton(),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.emergency_rounded), label: 'SOS'),
            NavigationDestination(icon: Icon(Icons.map_rounded), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.spa_rounded), label: 'Essentials'),
            NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
