import 'package:flutter/material.dart';

import 'tetris.dart';

class GameArcadeBottomSheet extends StatelessWidget {
  final BuildContext rootContext; // 바텀시트 밖으로 네비게이션할 때 사용

  const GameArcadeBottomSheet({super.key, required this.rootContext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.videogame_asset_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '게임 아케이드',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '원하는 게임을 선택하세요',
                  style: text.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 12),

              // 게임 목록
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _games.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final g = _games[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: g.bg,
                        child: Icon(g.icon, color: g.fg),
                      ),
                      title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(g.subtitle),
                      onTap: () {
                        if (g.route == _GameRoute.tetris) {
                          // 바텀시트를 닫고 → 테트리스 화면으로 이동
                          Navigator.of(context).pop();
                          Future.microtask(() {
                            Navigator.of(rootContext).push(
                              MaterialPageRoute(builder: (_) => const Tetris()),
                            );
                            // ※ 네임드 라우트 사용 시:
                            // Navigator.of(rootContext).pushNamed('/tetris');
                          });
                        } else {
                          // 임의의 게임: 준비중 안내
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(content: Text('「${g.title}」는 준비 중입니다.')),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 임의의 게임 목록 정의 (하나는 테트리스)
// ──────────────────────────────────────────────────────────────

enum _GameRoute { tetris, comingSoon }

class _GameItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color bg;
  final Color fg;
  final _GameRoute route;

  const _GameItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.route,
  });
}

const _games = <_GameItem>[
  _GameItem(
    title: '테트리스',
    subtitle: '클래식 드롭 퍼즐',
    icon: Icons.extension, // 블록 느낌
    bg: Color(0xFFE0F7FA),
    fg: Color(0xFF006064),
    route: _GameRoute.tetris,
  ),
  _GameItem(
    title: '스네이크',
    subtitle: '아케이드 클래식',
    icon: Icons.timeline_rounded,
    bg: Color(0xFFE8F5E9),
    fg: Color(0xFF1B5E20),
    route: _GameRoute.comingSoon,
  ),
  _GameItem(
    title: '2048',
    subtitle: '숫자 합치기 퍼즐',
    icon: Icons.calculate_rounded,
    bg: Color(0xFFFFF3E0),
    fg: Color(0xFFE65100),
    route: _GameRoute.comingSoon,
  ),
  _GameItem(
    title: '브릭 브레이커',
    subtitle: '벽돌 깨기',
    icon: Icons.sports_baseball_rounded,
    bg: Color(0xFFEDE7F6),
    fg: Color(0xFF4527A0),
    route: _GameRoute.comingSoon,
  ),
  _GameItem(
    title: '미로 탈출',
    subtitle: '길을 찾아라',
    icon: Icons.alt_route_rounded,
    bg: Color(0xFFF3E5F5),
    fg: Color(0xFF6A1B9A),
    route: _GameRoute.comingSoon,
  ),
];
