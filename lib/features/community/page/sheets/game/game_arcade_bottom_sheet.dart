import 'package:flutter/material.dart';

import '../../../../../utils/snackbar_helper.dart';
import '../../../widgets/game/minesweeper.dart';
import '../../../widgets/game/tetris.dart';

class GameArcadeBottomSheet extends StatelessWidget {
  final BuildContext rootContext; 

  const GameArcadeBottomSheet({super.key, required this.rootContext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      
      initialChildSize: 1.0,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      expand: false, 
      builder: (_, controller) {
        return Container(
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
          child: SafeArea(
            top: true,  
            bottom: false,
            child: ListView(
              controller: controller, 
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                
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

                
                ..._buildGameTiles(context, cs),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGameTiles(BuildContext context, ColorScheme cs) {
    final tiles = <Widget>[];
    for (int i = 0; i < _games.length; i++) {
      final g = _games[i];
      tiles.add(
        ListTile(
          leading: CircleAvatar(
            backgroundColor: g.bg,
            child: Icon(g.icon, color: g.fg),
          ),
          title: Text(
            g.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(g.subtitle),
          onTap: () {
            
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
                  showSelectedSnackbar(rootContext, '「${g.title}」는 준비 중입니다.');
                  break;
              }
            });
          },
        ),
      );
      if (i != _games.length - 1) {
        tiles.add(const Divider(height: 1));
      }
    }
    return tiles;
  }
}





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
