import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart'; // 하단 내비게이션 바

class FieldOffice extends StatelessWidget {
  const FieldOffice({super.key});

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
      bottomNavigationBar: const HqMiniNavigation(
        height: 56,
        iconSize: 22,
        icons: [
          Icons.today,       // 📅 Today Field
          Icons.input,       // 🔁 In&Out Doc.
          Icons.account_box, // 🧾 Account Doc.
        ],
        labels: [
          'Today Field',
          'In&Out Doc.',
          'Account Doc.',
        ],
      ),
    );
  }
}

