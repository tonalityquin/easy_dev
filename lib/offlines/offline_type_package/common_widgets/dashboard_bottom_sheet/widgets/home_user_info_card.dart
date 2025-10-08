import 'package:flutter/material.dart';

import 'package:easydev/offlines/sql/offline_auth_service.dart';
import 'package:easydev/offlines/sql/offline_session_model.dart';

/// Deep Blue 팔레트(서비스 카드 계열)
class _Palette {
  static const base  = Color(0xFF0D47A1); // primary
  static const dark  = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg    = Colors.white;      // 전경(아이콘/텍스트)
}

class HomeUserInfoCard extends StatelessWidget {
  const HomeUserInfoCard({super.key});

  @override
  Widget build(BuildContext context) {

    return FutureBuilder<OfflineSession?>(
      future: OfflineAuthService.instance.currentSession(),
      builder: (context, snap) {
        // 로딩 상태
        if (snap.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            color: Colors.white,
            surfaceTintColor: _Palette.light,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.35)),
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

        // 세션 없음
        if (!snap.hasData || snap.data == null) {
          return Card(
            elevation: 2,
            color: Colors.white,
            surfaceTintColor: _Palette.light,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.35)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: _Palette.dark.withOpacity(.8)),
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

        // 세션 있음 → 동일 정보 출력
        final session  = snap.data!;
        final name     = session.name.trim();
        final position = session.position.trim();
        final phone    = session.phone.trim();
        final area     = session.area.trim();

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => debugPrint('📄 사용자 상세 정보 보기'),
          child: Card(
            elevation: 2,
            color: Colors.white,
            surfaceTintColor: _Palette.light, // 살짝 블루 틴트
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _Palette.light.withOpacity(.35)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더 라벨 (원본과 동일한 타이틀)
                  Row(
                    children: [
                      Icon(Icons.badge, size: 14, color: _Palette.dark.withOpacity(.9)),
                      const SizedBox(width: 4),
                      Text(
                        '근무자 카드',
                        style: TextStyle(
                          fontSize: 12,
                          color: _Palette.dark.withOpacity(.9),
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 프로필 영역
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
                              name.isNotEmpty ? name : '-',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // 직책/직무
                            Text(
                              position.isNotEmpty ? position : '-',
                              style: TextStyle(
                                fontSize: 13,
                                color: _Palette.dark.withOpacity(.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // QR 코드 아이콘
                      Icon(
                        Icons.qr_code,
                        color: _Palette.dark.withOpacity(.85),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(color: _Palette.light.withOpacity(.35), height: 1),
                  const SizedBox(height: 12),

                  // 전화번호(라벨 포함)
                  _infoRow(Icons.phone, 'Tel.', _formatPhoneNumber(phone)),
                  // 근무 지역(세션의 area 반영)
                  _infoRow(Icons.location_on, 'Sector.', area.isNotEmpty ? area : '-'),
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
          Icon(icon, size: 18, color: _Palette.dark.withOpacity(.9)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _Palette.dark.withOpacity(.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPhoneNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }
}
