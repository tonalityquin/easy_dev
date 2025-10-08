import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/plate/plate_state.dart';
import '../offline_dialog/offline_area_picker_bottom_sheet.dart'; // 위 파일 경로에 맞추세요

import '../sql/offline_auth_db.dart';        // ← 경로 조정
import '../sql/offline_auth_service.dart';   // ← 경로 조정

/// 오프라인 상단 네비게이션 (SQLite 직결):
/// - AreaState 없이 현재 지역을 DB에서 읽어 표시
/// - 바텀시트를 닫으면 DB를 재조회하여 즉시 갱신
class OfflineTopNavigation extends StatefulWidget {
  const OfflineTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  final bool isAreaSelectable;

  @override
  State<OfflineTopNavigation> createState() => _OfflineTopNavigationState();
}

class _OfflineTopNavigationState extends State<OfflineTopNavigation> {
  late Future<String> _currentAreaF;

  @override
  void initState() {
    super.initState();
    _currentAreaF = _loadCurrentArea();
  }

  Future<String> _loadCurrentArea() async {
    // 1) 세션에서 현재 지역
    final session = await OfflineAuthService.instance.currentSession();
    final area = (session?.area ?? '').trim();
    if (area.isNotEmpty) return area;

    // 2) 폴백: area 마스터 첫 항목 (선택 사항)
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableArea,
      columns: ['name'],
      orderBy: 'name ASC',
      limit: 1,
    );
    return rows.isNotEmpty
        ? ((rows.first['name'] as String?) ?? '').trim()
        : '';
  }

  Future<void> _refresh() async {
    setState(() {
      _currentAreaF = _loadCurrentArea();
    });
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>(); // 필요 없다면 provider 의존 제거 가능

    return FutureBuilder<String>(
      future: _currentAreaF,
      builder: (context, snap) {
        final selectedArea = (snap.data ?? '').trim();
        final title = selectedArea.isNotEmpty ? selectedArea : '지역 없음';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isAreaSelectable
                ? () async {
              // 바텀시트 완료까지 대기 → 이후 DB 재조회로 즉시 반영
              await offlineAreaPickerBottomSheet(
                context: context,
                plateState: plateState,
              );
              await _refresh();
            }
                : null,
            splashColor: Colors.grey.withOpacity(0.2),
            highlightColor: Colors.grey.withOpacity(0.1),
            child: SizedBox(
              width: double.infinity,
              height: kToolbarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.car,
                    size: 18,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (widget.isAreaSelectable) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
