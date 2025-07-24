import 'dart:ui';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:platform_channel_swift_demo/screens/dashboard_screen.dart';
import 'package:platform_channel_swift_demo/screens/scan_screen.dart';
import 'package:platform_channel_swift_demo/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pageController = PageController(initialPage: 0);
  final NotchBottomBarController _controller = NotchBottomBarController(index: 0);

  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> bottomBarPages = [
      const DashboardScreen(),
      const Placeholder(), // Placeholder for scan
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(bottomBarPages.length, (index) => bottomBarPages[index]),
      ),
      bottomNavigationBar: AnimatedNotchBottomBar(
        bottomBarWidth: MediaQuery.of(context).size.width,
        notchColor: Color(0xFF00AEEF),
        notchBottomBarController: _controller,
        color: Colors.black, // Match your original BNB background
        showLabel: false, // Hide labels initially
        bottomBarItems: [
          BottomBarItem(
            inActiveItem: Icon(Icons.folder_outlined, color: Colors.white70),
            activeItem: Icon(Icons.folder_outlined, color: Colors.white70),
            itemLabel: 'Library',
          ),
          BottomBarItem(
            inActiveItem: Icon(Icons.camera_alt_outlined, color: Colors.white70),
            activeItem: Icon(Icons.camera_alt_outlined, color: Colors.white70),
            itemLabel: 'Scan',
          ),
          BottomBarItem(
            inActiveItem: Icon(Icons.settings_outlined, color: Colors.white70),
            activeItem: Icon(Icons.settings_outlined, color: Colors.white70),
            itemLabel: 'Settings',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const ScanScreen(autoStartScan: true),
              ),
            );
          } else {
            _pageController.jumpToPage(index);
            setState(() {});
          }
        },
        showShadow: true,
        elevation: 0,
        kBottomRadius: 0,
        kIconSize: 24.0,
      ),
    );
  }
}