import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';

class OfficeField extends StatelessWidget {
  const OfficeField({super.key});

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
      body: const Center(
        child: Text('오피스 -> 필드'),
      ),
      bottomNavigationBar: const HqMiniNavigation(
        height: 56,
        iconSize: 22,
        icons: [
          Icons.folder_open, // Open
          Icons.comment, // Comment
          Icons.close, // Close
        ],
        labels: [
          'Open',
          'Comment',
          'Close',
        ],
      ),
    );
  }
}
