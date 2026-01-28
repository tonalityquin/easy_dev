import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

class TripleHomeUserInfoCard extends StatelessWidget {
  const TripleHomeUserInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => debugPrint('📄 사용자 상세 정보 보기'),
      child: Card(
        elevation: 0, // ✅ 브랜드 통일(모드별 그림자 차이 제거)
        color: cs.surface,
        surfaceTintColor: Colors.transparent, // ✅ M3 tint 방지(디자인 흔들림 방지)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
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
                  Icon(Icons.badge, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '근무자 정보',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
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
                    backgroundColor: cs.primary, // ✅ 브랜드 Primary
                    child: Icon(Icons.person, color: cs.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userState.name.isNotEmpty ? userState.name : '-',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userState.position.isNotEmpty ? userState.position : '-',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.qr_code, color: cs.onSurfaceVariant),
                ],
              ),

              const SizedBox(height: 16),
              Divider(color: cs.outlineVariant.withOpacity(.85), height: 1),
              const SizedBox(height: 12),

              _infoRow(cs: cs, icon: Icons.phone, value: userState.phone),
              _infoRow(cs: cs, icon: Icons.location_on, value: userState.area),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required ColorScheme cs,
    required IconData icon,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
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
