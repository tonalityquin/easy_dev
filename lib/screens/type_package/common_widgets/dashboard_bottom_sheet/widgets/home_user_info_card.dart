import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

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
    final userState = context.watch<UserState>();

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
              // 헤더 라벨
              Row(
                children: [
                  Icon(Icons.badge, size: 14, color: _Palette.dark.withOpacity(.9)),
                  const SizedBox(width: 4),
                  Text(
                    '근무자 정보',
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
                        Text(
                          (userState.name).isNotEmpty ? userState.name : '-',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (userState.position).isNotEmpty ? userState.position : '-',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
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

              _infoRow(Icons.phone, userState.phone),
              _infoRow(Icons.location_on, userState.area),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _Palette.dark.withOpacity(.9)),
          const SizedBox(width: 8),
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
}
