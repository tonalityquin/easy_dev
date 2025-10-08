import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import 'package:easydev/offlines/sql/offline_auth_service.dart';
import 'package:easydev/offlines/sql/offline_session_model.dart';

/// Deep Blue Palette
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg = Color(0xFFFFFFFF);   // 전경(아이콘/텍스트)
}

class OfflineCommuteInsideUserInfoCardSection extends StatelessWidget {
  const OfflineCommuteInsideUserInfoCardSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Provider 구독은 유지(외부 상태 변경 시 리빌드 트리거)
    final _ = context.watch<UserState>();

    return FutureBuilder<OfflineSession?>(
      future: OfflineAuthService.instance.currentSession(),
      builder: (context, snap) {
        // 로딩
        if (snap.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.45)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('사용자 정보를 불러오는 중...'),
                ],
              ),
            ),
          );
        }

        // 세션 없음(로그인 전/세션 정리됨)
        if (!snap.hasData || snap.data == null) {
          return Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.45)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: _Palette.dark.withOpacity(.7)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '오프라인 세션이 없습니다. 오프라인 로그인 후 이용해 주세요.',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final session = snap.data!;
        final name = session.name;         // ex) Tester
        final position = session.position; // ex) dev
        final phone = session.phone;       // ex) 01012345678
        final area = session.area;         // ex) HQ 지역 or WorkingArea 지역 등

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            debugPrint('📄 사용자 상세 정보 보기');
          },
          child: Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.45)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, size: 14, color: _Palette.dark.withOpacity(.7)),
                      const SizedBox(width: 4),
                      Text(
                        '근무자 카드',
                        style: TextStyle(
                          fontSize: 12,
                          color: _Palette.dark.withOpacity(.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _Palette.base,
                        child: const Icon(Icons.person, color: _Palette.fg),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 이름
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 직책/직무
                            Text(
                              position,
                              style: TextStyle(
                                fontSize: 13,
                                color: _Palette.dark.withOpacity(.7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.qr_code, color: _Palette.dark.withOpacity(.7)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: _Palette.light.withOpacity(.35), height: 1),
                  const SizedBox(height: 12),

                  // 전화번호
                  _infoRow(Icons.phone, 'Tel.', formatPhoneNumber(phone)),
                  // 근무 지역(세션의 area 반영)
                  _infoRow(Icons.location_on, 'Sector.', area),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _Palette.dark.withOpacity(.7)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _Palette.dark.withOpacity(.6),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String formatPhoneNumber(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 7)}-${phone.substring(7)}';
    } else if (phone.length == 10) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 6)}-${phone.substring(6)}';
    }
    return phone;
  }
}
