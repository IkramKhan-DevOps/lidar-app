import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // This would be your three empty pages
  final List<Widget> _pages = [
    const Center(child: Text('Page 1')),
    const Center(child: Text('Page 2')),
    const Center(child: Text('Page 3')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomAppBar(
        height: 80, // Slightly taller than default
        color: Colors.black, // Black background like in your image
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // First tab - "READY TO SCAN" style
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.scanner, color: Colors.white),
                  onPressed: () => setState(() => _currentIndex = 0),
                ),
                const Text('READY TO SCAN',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            // Middle tab - "RECORD" style
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.fiber_manual_record, color: Colors.white),
                  onPressed: () => setState(() => _currentIndex = 1),
                ),
                const Text('RECORD',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            // Third tab - you can customize this
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () => setState(() => _currentIndex = 2),
                ),
                const Text('SETTINGS',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}