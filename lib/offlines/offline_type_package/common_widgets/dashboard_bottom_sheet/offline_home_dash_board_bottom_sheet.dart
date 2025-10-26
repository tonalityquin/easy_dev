import 'package:flutter/material.dart';

import '../../../utils/offline_logout_helper.dart';
import 'widgets/home_user_info_card.dart';

import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

import '../../../../../../routes.dart';

class OfflineHomeDashBoardBottomSheet extends StatefulWidget {
  const OfflineHomeDashBoardBottomSheet({super.key});

  @override
  State<OfflineHomeDashBoardBottomSheet> createState() => _OfflineHomeDashBoardBottomSheetState();
}

class _OfflineHomeDashBoardBottomSheetState extends State<OfflineHomeDashBoardBottomSheet> {
  bool _layerHidden = true;

  bool _processingClockOut = false;
  bool _processingLogout = false;

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _clockOut() async {
    if (_processingClockOut) return;
    setState(() => _processingClockOut = true);

    try {
      final session = await OfflineAuthService.instance.currentSession();
      final db = await OfflineAuthDb.instance.database;

      final ok = await db.transaction<bool>((txn) async {
        final all = await txn.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['userId', 'phone', 'isSelected', 'isWorking'],
        );

        String? targetUserId;

        final sessUid = (session?.userId ?? '').trim();
        final sessPhoneDigits = _digits(session?.phone ?? '');
        final sessUidDigits = _digits(sessUid);

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
          return false;
        }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퇴근 처리 완료되었습니다.')),
        );

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

  Future<void> _logout() async {
    if (_processingLogout) return;
    setState(() => _processingLogout = true);
    try {
      await OfflineLogoutHelper.logoutAndGoToLogin(
        context,
        loginRoute: AppRoutes.selector,
      );
    } catch (e, st) {
      debugPrint('❌ logout 실패: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 중 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLogout = false);
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('오프라인 로그아웃'),
                          style: _logoutBtnStyle(),
                          onPressed: _processingLogout ? null : _logout,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.redAccent, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _logoutBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.blueGrey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
