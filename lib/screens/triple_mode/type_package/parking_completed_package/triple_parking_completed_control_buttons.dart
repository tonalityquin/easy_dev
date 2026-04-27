import 'package:flutter/material.dart';

import '../../../common_package/memo_package/chat_bot.dart';
import '../triple_departure_completed_bottom_sheet.dart';

class TripleParkingCompletedControlButtons extends StatelessWidget {
  final VoidCallback showSearchDialog;

  const TripleParkingCompletedControlButtons({
    super.key,
    required this.showSearchDialog,
  });

  static const int idxChatbot = 0;
  static const int idxSmartSearch = 1;
  static const int idxDepartureCompleted = 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color navBg = cs.surface;
    final Color selectedItemColor = cs.primary;
    final Color unselectedItemColor = cs.onSurfaceVariant.withOpacity(.65);

    final Color chatbotColor = cs.secondary;
    final Color searchColor = cs.error;
    final Color successColor = cs.tertiary;

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: navBg,
      elevation: 0,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      iconSize: 24,
      selectedItemColor: selectedItemColor,
      unselectedItemColor: unselectedItemColor,
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_rounded, color: chatbotColor),
          label: '챗봇',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.manage_search_rounded, color: searchColor),
          label: '스마트 검색',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car_filled_rounded, color: successColor),
          label: '출차 완료',
        ),
      ],
      onTap: (index) async {
        switch (index) {
          case idxChatbot:
            await ChatBot.togglePanel();
            break;
          case idxSmartSearch:
            showSearchDialog();
            break;
          case idxDepartureCompleted:
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const TripleDepartureCompletedBottomSheet(),
            );
            break;
        }
      },
    );
  }
}
