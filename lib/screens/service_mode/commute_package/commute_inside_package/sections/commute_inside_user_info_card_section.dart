import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../theme.dart'; // ✅ AppCardPalette 사용 (theme.dart 연결) - 경로 필요 시 조정
import '../../../../../states/user/user_state.dart';

class CommuteInsideUserInfoCardSection extends StatelessWidget {
  const CommuteInsideUserInfoCardSection({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();

    // ✅ theme.dart(AppCardPalette)에서 Service(Deep Blue) 팔레트 획득
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;   // 기존 _Palette.base
    final dark = palette.serviceDark;   // 기존 _Palette.dark
    final light = palette.serviceLight; // 기존 _Palette.light

    // 전경(아이콘/텍스트) - 기존 코드 유지(화이트)
    const fg = Colors.white;

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
                          userState.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          userState.position,
                          style: TextStyle(
                            fontSize: 13,
                            color: dark.withOpacity(.7),
                          ),
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
              _infoRow(dark: dark, icon: Icons.phone, label: 'Tel.', value: formatPhoneNumber(userState.phone)),
              _infoRow(dark: dark, icon: Icons.location_on, label: 'Sector.', value: userState.area),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required Color dark,
    required IconData icon,
    required String label,
    required String value,
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
