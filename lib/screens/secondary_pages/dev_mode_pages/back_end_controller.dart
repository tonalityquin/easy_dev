import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart'; // ✅ 커스텀 스낵바 사용을 위한 import

class BackEndController extends StatelessWidget {
  const BackEndController({super.key});

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();

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
        children: PlateType.values.map((type) {
          final isOn = plateState.isSubscribed(type);
          final subscribedArea = plateState.getSubscribedArea(type);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(
                _getTypeLabel(type),
                style: const TextStyle(fontSize: 18),
              ),
              subtitle: subscribedArea != null
                  ? Text('지역: $subscribedArea', style: const TextStyle(fontSize: 14, color: Colors.grey))
                  : null,
              trailing: Switch(
                value: isOn,
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
                    final unsubscribedArea = subscribedArea ?? '알 수 없음';

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
          );
        }).toList(),
      ),
    );
  }

  String _getTypeLabel(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료 (미정산만)'; // ← 변경
    }
  }
}
