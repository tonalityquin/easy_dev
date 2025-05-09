import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';

class Headquarter extends StatefulWidget {
  const Headquarter({super.key});

  @override
  State<Headquarter> createState() => _HeadquarterState();
}

class _HeadquarterState extends State<Headquarter> {
  int _selectedIndex = 0;

  final List<String> _tabContents = [
    '📊 Dashboard 콘텐츠 준비 중',
    '📈 Analytics 콘텐츠 준비 중',
    '⚙️ Settings 콘텐츠 준비 중',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          _tabContents[_selectedIndex],
          style: const TextStyle(fontSize: 16),
        ),
      ),
      bottomNavigationBar: HqMiniNavigation(
        height: 56,
        iconSize: 22,
        icons: const [
          Icons.dashboard,
          Icons.analytics,
          Icons.settings,
        ],
        labels: const [
          'Dashboard',
          'Analytics',
          'Settings',
        ],
        onIconTapped: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
