import 'package:flutter/material.dart';

import 'widgets/home_user_info_card.dart';

// ▼ SQLite / 세션 (경로는 프로젝트에 맞게 조정하세요)
import '../../../sql/offline_auth_db.dart'; // ← 경로 조정
import '../../../sql/offline_auth_service.dart'; // ← 경로 조정

// ▼ 라우트 (경로/상수명은 프로젝트에 맞게 조정하세요)
import '../../../../../../routes.dart'; // 예: AppRoutes.selector

class OfflineHomeDashBoardBottomSheet extends StatefulWidget {
  const OfflineHomeDashBoardBottomSheet({super.key});

  @override
  State<OfflineHomeDashBoardBottomSheet> createState() => _OfflineHomeDashBoardBottomSheetState();
}

class _OfflineHomeDashBoardBottomSheetState extends State<OfflineHomeDashBoardBottomSheet> {
  // true = 숨김(기본), false = 펼침
  bool _layerHidden = true;

  // 퇴근 처리 중 중복 탭 방지
  bool _processingClockOut = false;

  // 숫자만 추출(전화번호 비교용)
  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// 퇴근 처리: offline_accounts.isWorking = 0
  /// - 세션 userId 또는 phone(숫자만 비교)로 타깃 행을 찾고
  /// - 없으면 isSelected=1 행으로 폴백
  /// - 성공 시 selector 페이지로 이동
  Future<void> _clockOut() async {
    if (_processingClockOut) return;
    setState(() => _processingClockOut = true);

    try {
      final session = await OfflineAuthService.instance.currentSession();
      final db = await OfflineAuthDb.instance.database;

      final ok = await db.transaction<bool>((txn) async {
        // 후보 탐색용 전체 행(필요 컬럼만)
        final all = await txn.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['userId', 'phone', 'isSelected', 'isWorking'],
        );

        String? targetUserId;

        // 세션 정보
        final sessUid = (session?.userId ?? '').trim();
        final sessPhoneDigits = _digits(session?.phone ?? '');
        final sessUidDigits = _digits(sessUid);

        // 1) userId 일치 → 2) phone 숫자 == userId 숫자 → 3) phone 숫자 == session.phone 숫자
        for (final r in all) {
          final uid = (r['userId'] as String?)?.trim() ?? '';
          final phone = (r['phone'] as String?) ?? '';
          final phDigits = _digits(phone);

          if (uid.isNotEmpty && uid == sessUid) {
            targetUserId = uid;
            break;
          }
          if (phDigits.isNotEmpty && sessUidDigits.isNotEmpty && phDigits == sessUidDigits) {
            targetUserId = uid;
            break;
          }
          if (phDigits.isNotEmpty && sessPhoneDigits.isNotEmpty && phDigits == sessPhoneDigits) {
            targetUserId = uid;
            break;
          }
        }

        // 4) 후보 없으면 isSelected=1 행 사용
        if (targetUserId == null) {
          final sel = await txn.query(
            OfflineAuthDb.tableAccounts,
            columns: const ['userId'],
            where: 'isSelected = 1',
            limit: 1,
          );
          if (sel.isNotEmpty) {
            targetUserId = (sel.first['userId'] as String?)?.trim();
          }
        }

        if (targetUserId == null || targetUserId.isEmpty) {
          // 타깃 행 없음
          return false;
        }

        // 퇴근: isWorking = 0
        final upd = await txn.update(
          OfflineAuthDb.tableAccounts,
          {'isWorking': 0},
          where: 'userId = ?',
          whereArgs: [targetUserId],
        );

        return upd > 0;
      });

      if (!mounted) return;

      if (ok) {
        // (선택) 사용자 피드백
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근 처리 완료되었습니다.')),
        );

        // ✅ selector 페이지로 이동 (스택 비우기)
        // - AppRoutes.selector 이름은 프로젝트 라우트에 맞춰 변경하세요.
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.selector,
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근 처리에 실패했습니다. 계정 정보를 확인하세요.')),
        );
      }
    } catch (e, st) {
      debugPrint('❌ clockOut 실패: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오류가 발생했습니다. 잠시 후 다시 시도하세요.')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingClockOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(height: 16),
                const HomeUserInfoCard(),
                const SizedBox(height: 16),

                // 레이어(토글) 버튼: 기본 true(숨김) → 누르면 false(펼침)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                    label: Text(_layerHidden ? '오프라인 작업 버튼 펼치기' : '작업 버튼 숨기기'),
                    style: _layerToggleBtnStyle(),
                    onPressed: () => setState(() => _layerHidden = !_layerHidden),
                  ),
                ),

                const SizedBox(height: 16),

                // 숨김/펼침 영역
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('오프라인 퇴근하기'),
                          style: _clockOutBtnStyle(),
                          onPressed: _processingClockOut ? null : _clockOut,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 접힘 상태일 때 하단 여백
                if (_layerHidden) const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

ButtonStyle _layerToggleBtnStyle() {
  // 토글 버튼도 공통 톤 유지(화이트 + 블랙)
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _clockOutBtnStyle() {
  // 눈에 띄도록 경고톤 보더만 살짝 진하게(실수 방지 목적)
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.redAccent, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
