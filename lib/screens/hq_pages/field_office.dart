import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';

class FieldOffice extends StatefulWidget {
  const FieldOffice({super.key});

  @override
  State<FieldOffice> createState() => _FieldOfficeState();
}

class _FieldOfficeState extends State<FieldOffice> {
  int _selectedIndex = 0;

  final List<String> _tabContents = [
    '📂 Open 콘텐츠 준비 중',
    '💬 Comment 콘텐츠 준비 중',
    '❌ Close 콘텐츠 준비 중',
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
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
            Icons.folder_open,
            Icons.comment,
            Icons.close,
          ],
          labels: const [
            'Open',
            'Comment',
            'Close',
          ],
          onIconTapped: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }
}
