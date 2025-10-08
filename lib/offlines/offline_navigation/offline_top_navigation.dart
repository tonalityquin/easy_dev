import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// 바텀시트: SQLite 전용 버전 (context 만 받는 시그니처)
import '../offline_dialog/offline_area_picker_bottom_sheet.dart'; // ← 경로를 프로젝트에 맞게 조정하세요

// SQLite 인증/세션/DB
import '../sql/offline_auth_db.dart';        // ← 경로 조정
import '../sql/offline_auth_service.dart';   // ← 경로 조정

/// 오프라인 상단 네비게이션 (SQLite 직결):
/// - 상태(PlateState/AreaState) 없이 현재 지역을 DB에서 읽어 표시
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

  /// DB에서 현재 표시할 지역명을 로드
  Future<String> _loadCurrentArea() async {
    // 1) 세션 테이블에 기록된 현재 지역
    final session = await OfflineAuthService.instance.currentSession();
    final area = (session?.area ?? '').trim();
    if (area.isNotEmpty) return area;

    // 2) 폴백: area 마스터 첫 항목(선택 사항)
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableArea,
      columns: const ['name'],
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
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
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
