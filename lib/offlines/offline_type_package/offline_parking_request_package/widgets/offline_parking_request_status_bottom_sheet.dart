import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../screens/modify_package/modify_plate_screen.dart';
import '../../../../screens/log_package/log_viewer_bottom_sheet.dart';
import '../../../../states/area/area_state.dart';
import '../../../../enums/plate_type.dart';
import '../../../../states/user/user_state.dart';

/// 입차 요청 상태 처리 바텀시트 (선택지 A: onDelete 제거)
/// ▶️ 리팩터링: 바텀시트가 **화면 최상단까지** 차오르도록 변경
/// - showModalBottomSheet + FractionallySizedBox(heightFactor: 1) 사용
/// - 키보드가 올라오면 하단 여백 반영
Future<void> offlineShowParkingRequestStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required VoidCallback onCancelEntryRequest,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // 시스템 인셋을 고려
    backgroundColor: Colors.transparent, // 외곽 투명
    builder: (_) {
      return FractionallySizedBox(
        heightFactor: 1, // ⬆️ 최상단까지
        child: _FullHeightSheet(
          plateNumber: plateNumber,
          division: division,
          area: area,
          requestTime: plate.requestTime,
          onCancelEntryRequest: onCancelEntryRequest,
          plate: plate,
        ),
      );
    },
  );
}

class _FullHeightSheet extends StatelessWidget {
  const _FullHeightSheet({
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.requestTime,
    required this.onCancelEntryRequest,
    required this.plate,
  });

  final String plateNumber;
  final String division;
  final String area;
  final DateTime? requestTime;
  final VoidCallback onCancelEntryRequest;
  final PlateModel plate;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      // 상단 라운드 유지 위해 top=false
      top: false,
      child: Padding(
        // 키보드가 올라오면 내용을 위로 밀어 올림
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Drag handle
              const SizedBox(height: 12),
              Center(
                child: Semantics(
                  label: '당겨서 닫기',
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 헤더
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text(
                      '입차 요청 상태 처리',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 본문(스크롤)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    // 로그 확인
                    ElevatedButton.icon(
                      icon: const Icon(Icons.history),
                      label: const Text("로그 확인"),
                      onPressed: () {
                        Navigator.pop(context);
                        // pop 직후 push는 마이크로태스크로 지연하여 컨텍스트 안정화
                        Future.microtask(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LogViewerBottomSheet(
                                initialPlateNumber: plateNumber,
                                division: division,
                                area: area,
                                requestTime: requestTime ?? DateTime.now(),
                              ),
                            ),
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 정보 수정
                    ElevatedButton.icon(
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text("정보 수정"),
                      onPressed: () {
                        Navigator.pop(context);
                        Future.microtask(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ModifyPlateScreen(
                                plate: plate,
                                collectionKey: PlateType.parkingRequests,
                              ),
                            ),
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 입차 요청 취소 (삭제/취소 역할 수행)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.assignment_return),
                      label: const Text("입차 요청 취소"),
                      onPressed: () {
                        Navigator.pop(context);
                        onCancelEntryRequest();
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
