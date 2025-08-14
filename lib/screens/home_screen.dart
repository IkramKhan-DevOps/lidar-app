import 'dart:ui';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:platform_channel_swift_demo/screens/dashboard_screen.dart';
import 'package:platform_channel_swift_demo/screens/scan_screen.dart';
import 'package:platform_channel_swift_demo/screens/settings_screen.dart';

// =============================================================
// HOME SCREEN
// Hosts the main 3-tab navigation using:
// - PageView (content switching without rebuilds)
// - AnimatedNotchBottomBar (notched bottom navigation)
// =============================================================
//
// FLOW OVERVIEW
// - Tabs: [0]=Dashboard, [1]=Scan (modal push), [2]=Settings
// - Tapping middle (index 1) pushes ScanScreen as a page (does not
//   change the selected PageView index).
// - Tapping other items jumps PageView to that index.
//
// INTEGRATION
// - PageView is controlled by _pageController.
// - Bottom bar selection is managed by NotchBottomBarController.
//
// UI NOTES
// - Bottom bar currently uses a solid black background (color: Colors.black).
//   To create a subtle "glass" effect without logic changes:
//     * Wrap the bar with ClipRect + BackdropFilter in the Scaffold's
//       bottomNavigationBar, and set bar color to Colors.transparent.
//     * Optionally set Scaffold(extendBody: true) to draw content under the bar.
// - kBottomRadius: 0 keeps the bar flat against edges; increase for rounding.
//
// SAFETY
// - Controllers are disposed in dispose().
// =============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controls which PageView page is visible.
  final _pageController = PageController(initialPage: 0);

  // Controls the AnimatedNotchBottomBar selected index.
  final NotchBottomBarController _controller = NotchBottomBarController(index: 0);

  @override
  void dispose() {
    // Always dispose controllers to prevent memory leaks.
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pages aligned with bottom bar items (index-matched).
    final List<Widget> bottomBarPages = [
      const DashboardScreen(),
      const Placeholder(), // Placeholder for scan
      const SettingsScreen(),
    ];

    return Scaffold(
      // Tip: For a translucent bottom bar look, you can set extendBody: true
      // and make the bar background transparent (see UI NOTES above).
      backgroundColor: Colors.grey[900],
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Navigation only via bar
        children: List.generate(bottomBarPages.length, (index) => bottomBarPages[index]),
      ),
      bottomNavigationBar: AnimatedNotchBottomBar(
        bottomBarWidth: MediaQuery.of(context).size.width,
        notchColor: Color(0xFF00AEEF), // Accent color for the center notch
        notchBottomBarController: _controller,
        color: Colors.black, // Current solid background for the bar
        showLabel: false, // Keep labels hidden for a minimal look
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
          // Center item (index 1) opens Scan as a pushed page.
          if (index == 1) {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const ScanScreen(autoStartScan: true),
              ),
            );
          } else {
            // Other items switch PageView page (no animation jump).
            _pageController.jumpToPage(index);
            setState(() {}); // Refresh if any visual needs updating
          }
        },
        showShadow: true, // Built-in shadow under the bar
        elevation: 0,     // Shadow depth controlled by package; 0 keeps it subtle
        kBottomRadius: 0, // Keep the bottom edge flat (no rounding)
        kIconSize: 24.0,  // Consistent icon sizing across items
      ),
    );
  }
}