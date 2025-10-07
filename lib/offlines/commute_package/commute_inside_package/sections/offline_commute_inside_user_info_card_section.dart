import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';

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
    final userState = context.watch<UserState>();

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
                            color: _Palette.dark.withOpacity(.7),
                          ),
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
              _infoRow(Icons.phone, 'Tel.', formatPhoneNumber(userState.phone)),
              _infoRow(Icons.location_on, 'Sector.', userState.area),
            ],
          ),
        ),
      ),
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
