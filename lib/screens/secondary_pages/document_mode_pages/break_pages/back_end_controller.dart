import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';


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
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(
                _getTypeLabel(type),
                style: const TextStyle(fontSize: 18),
              ),
              trailing: Switch(
                value: isOn,
                onChanged: (value) {
                  if (value) {
                    plateState.subscribeType(type);
                    debugPrint('🔔 [${_getTypeLabel(type)}] 구독 시작');
                    _showSnackBar(context, '✅ [${_getTypeLabel(type)}] 구독 시작됨');
                  } else {
                    plateState.unsubscribeType(type);
                    debugPrint('🛑 [${_getTypeLabel(type)}] 구독 해제');
                    _showSnackBar(context, '🛑 [${_getTypeLabel(type)}] 구독 해제됨');
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
        return '출차 완료';
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
