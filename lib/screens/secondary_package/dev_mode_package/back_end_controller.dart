// lib/screens/secondary_package/office_mode_package/back_end_controller.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

class BackEndController extends StatefulWidget {
  const BackEndController({super.key});

  @override
  State<BackEndController> createState() => _BackEndControllerState();
}

class _BackEndControllerState extends State<BackEndController> {
  // ✅ 기본값 true: 잠금 상태에서 시작
  bool _locked = true;

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();

    // ✅ 구독 대상에서 '입차 완료' 제거
    final List<PlateType> subscribableTypes =
    PlateType.values.where((t) => t != PlateType.parkingCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('근태 문서'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(_locked ? Icons.lock : Icons.lock_open),
                Switch.adaptive(
                  value: _locked, // true면 잠금
                  onChanged: (v) => setState(() => _locked = v),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ 잠금 시 입력 차단
          IgnorePointer(
            ignoring: _locked,
            child: ListView(
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
          ),

          // ✅ 잠금 상태 시 시각적 오버레이
          if (_locked)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6),
                child: const Center(
                  child: _LockedBanner(),
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
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료 (미정산만)';
    }
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.lock, size: 48, color: Colors.black54),
        SizedBox(height: 8),
        Text(
          '화면이 잠금 상태입니다',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text('오른쪽 상단 스위치를 끄면 조작할 수 있어요'),
      ],
    );
  }
}
