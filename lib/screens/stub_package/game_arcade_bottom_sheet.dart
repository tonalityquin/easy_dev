import 'package:flutter/material.dart';

import 'game_package/tetris.dart';
import 'game_package/minesweeper.dart';

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
                        // 바텀시트를 닫고 → 게임 화면으로 이동
                        Navigator.of(context).pop();
                        Future.microtask(() {
                          switch (g.route) {
                            case _GameRoute.tetris:
                              Navigator.of(rootContext).push(
                                MaterialPageRoute(builder: (_) => const Tetris()),
                              );
                              break;
                            case _GameRoute.minesweeper:
                              Navigator.of(rootContext).push(
                                MaterialPageRoute(builder: (_) => const Minesweeper()),
                              );
                              break;
                            case _GameRoute.comingSoon:
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(content: Text('「${g.title}」는 준비 중입니다.')),
                              );
                              break;
                          }
                        });
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
// 임의의 게임 목록 정의 (테트리스 + 스네이크 실행 가능)
// ──────────────────────────────────────────────────────────────

enum _GameRoute { tetris, minesweeper, comingSoon }

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
    icon: Icons.extension,
    // 블록 느낌
    bg: Color(0xFFE0F7FA),
    fg: Color(0xFF006064),
    route: _GameRoute.tetris,
  ),
  _GameItem(
    title: '지뢰찾기',
    subtitle: '롱프레스 = 깃발, 첫칸 보호',
    icon: Icons.grid_on,
    bg: Color(0xFFF3E5F5),
    fg: Color(0xFF4A148C),
    route: _GameRoute.minesweeper,
  ),
];
