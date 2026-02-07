import 'package:flutter/material.dart';


// ✅ AppCardPalette 정의 파일을 프로젝트 경로에 맞게 import 하세요.
import '../../../../theme.dart';
import '../../../sql/offline_auth_service.dart';
import '../../../sql/offline_session_model.dart';

/// ✅ _Palette 제거
/// ✅ AppCardPalette(parking*)를 오프라인(=Offline Service) 톤으로 사용
class OfflineCommuteInsideUserInfoCardSection extends StatelessWidget {
  const OfflineCommuteInsideUserInfoCardSection({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    // 오프라인 서비스 컬러 매핑
    final base = palette.parkingBase;
    final dark = palette.parkingDark;
    final light = palette.parkingLight;
    const fg = Colors.white;

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
              side: BorderSide(color: light.withOpacity(.45)),
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

        if (!snap.hasData || snap.data == null) {
          return Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: light.withOpacity(.45)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: dark.withOpacity(.7)),
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
        final name = session.name;
        final position = session.position;
        final phone = session.phone;
        final area = session.area;

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
              side: BorderSide(color: light.withOpacity(.45)),
            ),
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, size: 14, color: dark.withOpacity(.7)),
                      const SizedBox(width: 4),
                      Text(
                        '근무자 카드',
                        style: TextStyle(
                          fontSize: 12,
                          color: dark.withOpacity(.7),
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
                        backgroundColor: base,
                        child: const Icon(Icons.person, color: fg),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              position,
                              style: TextStyle(
                                fontSize: 13,
                                color: dark.withOpacity(.7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.qr_code, color: dark.withOpacity(.7)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: light.withOpacity(.35), height: 1),
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.phone,
                    label: 'Tel.',
                    value: formatPhoneNumber(phone),
                    dark: dark,
                  ),
                  _infoRow(
                    icon: Icons.location_on,
                    label: 'Sector.',
                    value: area,
                    dark: dark,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color dark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: dark.withOpacity(.7)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: dark.withOpacity(.6),
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
