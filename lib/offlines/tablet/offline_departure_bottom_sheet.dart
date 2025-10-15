// lib/offlines/tablet/offline_departure_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sql/offline_auth_db.dart';
// ✅ TTS
import '../tts/offline_tts.dart';

/// 출차 요청 전용 오프라인 바텀시트 (HQ 단일 지역)
/// - 좌측: status_type = 'departureRequests' 목록
/// - 우측: 뒷자리 4자리 입력 → 입력이 4자리에 도달하는 순간, 일치하는 데이터들을 즉시 '출차 요청' 상태로 갱신
class OfflineDepartureBottomSheet extends StatefulWidget {
  const OfflineDepartureBottomSheet({super.key});

  @override
  State<OfflineDepartureBottomSheet> createState() => _OfflineDepartureBottomSheetState();
}

class _OfflineDepartureBottomSheetState extends State<OfflineDepartureBottomSheet> {
  // 좌측 목록 상태
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;
  int? _selectedId; // 좌측 목록 하이라이트 용

  // 우측 자동 요청 상태
  final TextEditingController _fourCtrl = TextEditingController();
  bool _autoRequesting = false;
  String? _lastAutoFiredFour; // 같은 값으로 중복 실행 방지
  String? _lastDoneFour;      // 마지막 처리된 4자리
  int? _lastAffectedCount;    // 마지막 처리 건수

  static const String _kStatusDepartureRequests = 'departureRequests';

  @override
  void initState() {
    super.initState();
    _loadLeftList();

    // 4자리 입력 완료 시 자동 실행
    _fourCtrl.addListener(() {
      final t = _fourCtrl.text.trim();
      final isFour = RegExp(r'^\d{4}$').hasMatch(t);
      if (!isFour) return;
      if (_autoRequesting) return;
      if (_lastAutoFiredFour == t) return; // 동일 값 재실행 방지
      _autoRequestDepartureByFour(t);
    });
  }

  @override
  void dispose() {
    _fourCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 좌측: departureRequests 목록 로드
  Future<void> _loadLeftList() async {
    setState(() => _loading = true);
    final db = await OfflineAuthDb.instance.database;

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id', 'plate_number', 'plate_four_digit',
        'updated_at', 'created_at', 'area', 'location'
      ],
      where: "COALESCE(status_type, '') = ?",
      whereArgs: const [_kStatusDepartureRequests],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
      limit: 1000,
    );

    setState(() {
      _rows = rows;
      _loading = false;
      if (_selectedId != null && !_rows.any((e) => (e['id'] as int) == _selectedId)) {
        _selectedId = null; // 목록에서 사라졌으면 선택 해제
      }
    });
  }

  String _plateTitle(Map<String, Object?> r) {
    final pn = ((r['plate_number'] as String?) ?? '').trim();
    if (pn.isNotEmpty) return pn;
    final four = ((r['plate_four_digit'] as String?) ?? '').trim();
    if (four.isNotEmpty) return '****-$four';
    return '미상';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 우측: 4자리 자동 출차 요청
  Future<void> _autoRequestDepartureByFour(String four) async {
    _autoRequesting = true;
    _lastAutoFiredFour = four;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowStr = '$nowMs';

    try {
      final db = await OfflineAuthDb.instance.database;

      // 일치하는 모든 데이터(status 무관)를 'departureRequests'로 갱신
      // - plate_four_digit = ? OR plate_number 끝 4자리 = ?
      final affected = await db.rawUpdate(
        '''
        UPDATE ${OfflineAuthDb.tablePlates}
           SET status_type = ?,
               request_time = ?,  -- TEXT 가정
               updated_at  = ?,
               is_selected = 0
         WHERE (
                COALESCE(plate_four_digit, '') = ?
             OR  substr(
                    replace(plate_number,'-',''),
                    length(replace(plate_number,'-',''))-3, 4
                 ) = ?
               )
        ''',
        [_kStatusDepartureRequests, nowStr, nowMs, four, four],
      );

      // 갱신된 데이터 중 최신 1건을 찾아 좌측에서 하이라이트
      final pick = await db.rawQuery(
        '''
        SELECT id
          FROM ${OfflineAuthDb.tablePlates}
         WHERE COALESCE(status_type,'') = ?
           AND (
                COALESCE(plate_four_digit, '') = ?
             OR  substr(
                    replace(plate_number,'-',''),
                    length(replace(plate_number,'-',''))-3, 4
                 ) = ?
               )
         ORDER BY COALESCE(updated_at, created_at) DESC
         LIMIT 1
        ''',
        [_kStatusDepartureRequests, four, four],
      );

      await _loadLeftList();
      if (pick.isNotEmpty) {
        setState(() => _selectedId = (pick.first['id'] as int?));
      }

      setState(() {
        _lastDoneFour = four;
        _lastAffectedCount = affected;
      });

      // ✅ 일치 항목이 하나라도 갱신되었다면 TTS로 "차량 뒷번호#### 출차 요청"
      if (affected > 0) {
        await OfflineTts.instance.sayDepartureRequested(fourDigit: four);
      }

      if (mounted) {
        final msg = affected > 0
            ? '출차 요청 갱신 완료: $four (${affected}건)'
            : '일치하는 데이터가 없습니다: $four';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자동 출차 요청 중 오류: $e')),
        );
      }
    } finally {
      _autoRequesting = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black.withOpacity(.15))],
              ),
              child: Column(
                children: [
                  // 헤더
                  const SizedBox(height: 10),
                  Container(
                    width: 44, height: 4,
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car, size: 20),
                        const SizedBox(width: 8),
                        const Text('출차 요청 (HQ)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: '새로고침',
                          onPressed: _loadLeftList,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // 본문: 좌/우 2패널
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        final leftFlex = constraints.maxWidth >= 900
                            ? 2
                            : (constraints.maxWidth >= 600 ? 2 : 3);
                        final rightFlex = 3 - (leftFlex - 1);

                        return Row(
                          children: [
                            // ── 좌측: 출차 요청 목록
                            Expanded(
                              flex: leftFlex,
                              child: _rows.isEmpty
                                  ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Text('출차 요청 중인 차량이 없습니다.',
                                      style: TextStyle(color: Colors.black54)),
                                ),
                              )
                                  : RefreshIndicator(
                                onRefresh: _loadLeftList,
                                child: ListView.separated(
                                  controller: controller,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final r = _rows[i];
                                    final id = r['id'] as int;
                                    final title = _plateTitle(r);
                                    final selected = id == _selectedId;

                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      selected: selected,
                                      selectedTileColor: Colors.orange.withOpacity(0.08),
                                      title: Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: selected ? Colors.deepOrange : Colors.black,
                                        ),
                                      ),
                                      subtitle: _buildLeftSubtitle(r),
                                      onTap: () => setState(() => _selectedId = id),
                                    );
                                  },
                                ),
                              ),
                            ),

                            const VerticalDivider(width: 1),

                            // ── 우측: 4자리 자동 출차 요청 입력창
                            Expanded(
                              flex: rightFlex,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                child: _buildRightPanel(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftSubtitle(Map<String, Object?> r) {
    final area = (r['area'] as String?)?.trim();
    final loc  = (r['location'] as String?)?.trim();
    if ((area ?? '').isEmpty && (loc ?? '').isEmpty) return const SizedBox.shrink();
    return Text(
      '${(area ?? 'HQ')} • ${(loc ?? '위치 미지정')}',
      style: const TextStyle(color: Colors.black54),
    );
  }

  Widget _buildRightPanel() {
    final running = _autoRequesting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('뒷자리 4자리', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _fourCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: InputDecoration(
            hintText: '예: 1234',
            helperText: '4자리 입력이 완료되면 자동으로 출차 요청됩니다.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running)
                  const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _fourCtrl.clear();
                    _lastAutoFiredFour = null; // 같은 값 재실행 허용을 위해 리셋
                    setState(() {
                      _lastDoneFour = null;
                      _lastAffectedCount = null;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_lastDoneFour != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _lastAffectedCount != null
                  ? '최근 처리: $_lastDoneFour → ${_lastAffectedCount}건 갱신'
                  : '최근 처리: $_lastDoneFour',
              style: const TextStyle(color: Colors.black87),
            ),
          ),
      ],
    );
  }
}

/// 외부에서 쉽게 호출
void showOfflineDepartureBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.25),
    builder: (_) => const OfflineDepartureBottomSheet(),
  );
}
