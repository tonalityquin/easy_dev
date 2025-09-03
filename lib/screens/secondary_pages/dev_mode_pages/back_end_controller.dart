import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

class BackEndController extends StatelessWidget {
  const BackEndController({super.key});

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();

    // ✅ 구독 대상에서 '입차 완료' 제거
    final List<PlateType> subscribableTypes = PlateType.values
        .where((t) => t != PlateType.parkingCompleted)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('근태 문서'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final type in subscribableTypes)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(
                  _getTypeLabel(type),
                  style: const TextStyle(fontSize: 18),
                ),
                subtitle: _buildSubscribedAreaText(plateState, type),
                trailing: Switch(
                  value: plateState.isSubscribed(type),
                  onChanged: (value) {
                    final typeLabel = _getTypeLabel(type);

                    if (value) {
                      plateState.subscribeType(type);
                      final currentArea = plateState.currentArea;

                      debugPrint('🔔 [$typeLabel] 구독 시작 (지역: $currentArea)');
                      showSuccessSnackbar(
                        context,
                        '✅ [$typeLabel] 구독 시작됨\n지역: $currentArea',
                      );
                    } else {
                      final unsubscribedArea =
                          plateState.getSubscribedArea(type) ?? '알 수 없음';

                      plateState.unsubscribeType(type);
                      debugPrint('🛑 [$typeLabel] 구독 해제 (지역: $unsubscribedArea)');
                      showFailedSnackbar(
                        context,
                        '🛑 [$typeLabel] 구독 해제됨\n지역: $unsubscribedArea',
                      );
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildSubscribedAreaText(PlateState plateState, PlateType type) {
    final subscribedArea = plateState.getSubscribedArea(type);
    if (subscribedArea == null) return null;
    return Text(
      '지역: $subscribedArea',
      style: const TextStyle(fontSize: 14, color: Colors.grey),
    );
  }

  String _getTypeLabel(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
      // 현재 화면에서는 사용되지 않지만 enum 완전성 유지를 위해 남겨둠
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료 (미정산만)';
    }
  }
}
