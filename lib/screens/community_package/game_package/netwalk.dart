// File: lib/screens/stub_package/game_package/netwalk.dart
//
// Netwalk (네트워크 퍼즐)
// - 스팬닝 트리 기반 무작위 퍼즐 생성 → 반드시 해답 존재
// - 타일 탭: 90° 회전, 길게 누름: 잠금 토글
// - 서버(초록)에서 모든 케이블이 정확히 연결되면 클리어
// - 힌트 모드: 연결된 타일은 선명, 미스매치/외부로 나간 선은 강조
//
// 사용법: Navigator.push(..., MaterialPageRoute(builder: (_) => const Netwalk()));
// 필요 패키지: Flutter 기본만 사용

import 'dart:math';
import 'package:flutter/material.dart';

class Netwalk extends StatefulWidget {
  const Netwalk({super.key});

  @override
  State<Netwalk> createState() => _NetwalkState();
}

class _NetwalkState extends State<Netwalk> {
  // --- 보드 크기(난이도) ---
  int rows = 6;
  int cols = 6;

  // 서버 위치
  late Point<int> server;

  // 타일 데이터
  late List<_Tile> tiles;

  // 힌트/오버레이
  bool showHints = true;

  // 생성 시드 (새게임 때 살짝 바뀜)
  int seed = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame({int? r, int? c}) {
    if (r != null && c != null) {
      rows = r;
      cols = c;
    }
    seed = DateTime.now().millisecondsSinceEpoch ^ seed;
    _generatePuzzle();
    setState(() {});
  }

  // 4방향 비트(↑→↓←): 1,2,4,8
  static const int U = 1, R = 2, D = 4, L = 8;

  // 반대 방향
  static const Map<int, int> opp = {U: D, D: U, L: R, R: L};

  // 회전(시계 90°)
  int _rot90(int mask) {
    // U(1)->R(2), R(2)->D(4), D(4)->L(8), L(8)->U(1)
    int out = 0;
    if ((mask & U) != 0) out |= R;
    if ((mask & R) != 0) out |= D;
    if ((mask & D) != 0) out |= L;
    if ((mask & L) != 0) out |= U;
    return out;
  }

  // 좌표 → 인덱스
  int _idx(int r, int c) => r * cols + c;

  // 보드 생성
  void _generatePuzzle() {
    final rnd = Random(seed);

    // 서버는 중앙 근처
    server = Point(rows ~/ 2, cols ~/ 2);

    // 스팬닝 트리 생성: 모든 칸을 하나의 네트워크로
    // (DFS 랜덤 탐색)
    final visited = List.generate(rows, (_) => List.filled(cols, false));
    final conns = List.generate(rows * cols, (_) => 0);

    void dfs(int r, int c) {
      visited[r][c] = true;
      final dirs = <int>[U, R, D, L]..shuffle(rnd);
      for (final dir in dirs) {
        final nr = r + (dir == U ? -1 : dir == D ? 1 : 0);
        final nc = c + (dir == L ? -1 : dir == R ? 1 : 0);
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        if (!visited[nr][nc]) {
          // 양방향 연결
          conns[_idx(r, c)] |= dir;
          conns[_idx(nr, nc)] |= opp[dir]!;
          dfs(nr, nc);
        }
      }
    }

    dfs(server.x, server.y);

    // 타일로 변환 & 랜덤 회전
    tiles = List.generate(rows * cols, (i) {
      var mask = conns[i];
      final rot = rnd.nextInt(4);
      for (int k = 0; k < rot; k++) {
        mask = _rot90(mask);
      }
      return _Tile(mask: mask, lock: false);
    });

    // 서버 타일 표시용 플래그(필드 유지)
    tiles[_idx(server.x, server.y)].isServer = true;
  }

  // 인접 타일 마스크 얻기
  int _maskAt(int r, int c) => tiles[_idx(r, c)].mask;

  // 현재 상태에서 “연결 성립” 여부 계산 + 서버로부터 연결된 영역 마킹
  _CheckResult _checkBoard() {
    int mismatches = 0;
    int outside = 0;

    // 모든 상호 연결이 맞는지 (서로 마주보는 비트가 있는지)
    bool _match(int r, int c, int dir) {
      final nr = r + (dir == U ? -1 : dir == D ? 1 : 0);
      final nc = c + (dir == L ? -1 : dir == R ? 1 : 0);
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) {
        // 보드 밖으로 연결되면 문제
        return false;
      }
      return (_maskAt(nr, nc) & opp[dir]!) != 0;
    }

    // 미스매치 & 바깥 연결 카운트
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final m = _maskAt(r, c);
        if ((m & U) != 0) {
          if (r == 0) {
            outside++;
          } else if (!_match(r, c, U)) {
            mismatches++;
          }
        }
        if ((m & R) != 0) {
          if (c == cols - 1) {
            outside++;
          } else if (!_match(r, c, R)) {
            mismatches++;
          }
        }
        if ((m & D) != 0) {
          if (r == rows - 1) {
            outside++;
          } else if (!_match(r, c, D)) {
            mismatches++;
          }
        }
        if ((m & L) != 0) {
          if (c == 0) {
            outside++;
          } else if (!_match(r, c, L)) {
            mismatches++;
          }
        }
      }
    }

    // 서버로부터 연결성 체크 (정합이 맞는 연결만 따라감)
    final connected = List.generate(rows * cols, (_) => false);
    final q = <Point<int>>[];

    bool _okMove(int r, int c, int dir) {
      final nr = r + (dir == U ? -1 : dir == D ? 1 : 0);
      final nc = c + (dir == L ? -1 : dir == R ? 1 : 0);
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) return false;
      // 양쪽 비트가 서로 마주보고 있어야 "실제 연결"로 간주
      return (_maskAt(r, c) & dir) != 0 && (_maskAt(nr, nc) & opp[dir]!) != 0;
    }

    q.add(server);
    connected[_idx(server.x, server.y)] = true;

    while (q.isNotEmpty) {
      final p = q.removeLast();
      final r = p.x, c = p.y;
      for (final dir in [U, R, D, L]) {
        if (_okMove(r, c, dir)) {
          final nr = r + (dir == U ? -1 : dir == D ? 1 : 0);
          final nc = c + (dir == L ? -1 : dir == R ? 1 : 0);
          final ni = _idx(nr, nc);
          if (!connected[ni]) {
            connected[ni] = true;
            q.add(Point(nr, nc));
          }
        }
      }
    }

    // 컨넥터가 하나라도 있는 타일은 전부 서버에 연결되어야 승리
    int withWire = 0;
    int connectedWire = 0;
    for (int i = 0; i < tiles.length; i++) {
      final hasWire = tiles[i].mask != 0;
      if (hasWire) {
        withWire++;
        if (connected[i]) connectedWire++;
      }
    }

    final solved = mismatches == 0 && outside == 0 && withWire > 0 && withWire == connectedWire;

    return _CheckResult(
      mismatches: mismatches,
      outside: outside,
      connected: connected,
      solved: solved,
    );
  }

  void _onTapTile(int r, int c) {
    final t = tiles[_idx(r, c)];
    if (t.lock) return;
    setState(() {
      t.mask = _rot90(t.mask);
    });
    final res = _checkBoard();
    if (res.solved) {
      _showWin();
    }
  }

  void _onLongPressTile(int r, int c) {
    setState(() {
      final t = tiles[_idx(r, c)];
      t.lock = !t.lock;
    });
  }

  void _showWin() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('성공!'),
        content: const Text('모든 장치가 서버에 연결되었습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          FilledButton(onPressed: () { Navigator.pop(ctx); _newGame(); }, child: const Text('새 게임')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = _checkBoard(); // 실시간 체크 (힌트 표시용)

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Netwalk: 네트워크 퍼즐'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0.5,
        actions: [
          // 난이도
          PopupMenuButton<String>(
            tooltip: '보드 크기',
            onSelected: (v) {
              switch (v) {
                case '5x5':
                  _newGame(r: 5, c: 5);
                  break;
                case '6x6':
                  _newGame(r: 6, c: 6);
                  break;
                case '7x7':
                  _newGame(r: 7, c: 7);
                  break;
                case '8x8':
                  _newGame(r: 8, c: 8);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '5x5', child: Text('5 × 5')),
              PopupMenuItem(value: '6x6', child: Text('6 × 6 (기본)')),
              PopupMenuItem(value: '7x7', child: Text('7 × 7')),
              PopupMenuItem(value: '8x8', child: Text('8 × 8')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.grid_view_rounded),
            ),
          ),
          IconButton(
            tooltip: '힌트 보기/숨기기',
            onPressed: () => setState(() => showHints = !showHints),
            icon: Icon(showHints ? Icons.visibility : Icons.visibility_off),
          ),
          IconButton(
            tooltip: '새 게임',
            onPressed: _newGame,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _pill(
                  icon: Icons.cloud_done,
                  text: res.solved ? '완료' : '연결 확인 중',
                  color: res.solved ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                _pill(
                  icon: Icons.report,
                  text: '미스매치 ${res.mismatches} / 외부 ${res.outside}',
                  color: (res.mismatches + res.outside) == 0 ? Colors.green : Colors.redAccent,
                ),
                const Spacer(),
                const Text('탭: 회전 · 길게: 잠금', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (_, cons) {
            final size = min(cons.maxWidth, cons.maxHeight) - 24;
            final tile = size / max(rows, cols);
            return SizedBox(
              width: tile * cols,
              height: tile * rows,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 1,
                ),
                itemCount: rows * cols,
                itemBuilder: (_, i) {
                  final r = i ~/ cols, c = i % cols;
                  final t = tiles[i];
                  final isConnected = res.connected[i]; // 상단에서 계산한 결과 재사용
                  return _TileWidget(
                    key: ValueKey('tile_$i'),
                    mask: t.mask,
                    locked: t.lock,
                    server: (r == server.x && c == server.y),
                    size: tile,
                    hintConnected: showHints ? isConnected : null,
                    hintWarn: showHints ? _tileHasIssue(r, c) : null,
                    onTap: () => _onTapTile(r, c),
                    onLong: () => _onLongPressTile(r, c),
                  );
                },
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '모든 케이블이 서버(초록)까지 정확히 이어지도록 타일을 회전시키세요. '
                '보드 밖으로 나가는 케이블이나, 이웃 타일과 맞물리지 않는 케이블은 허용되지 않습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ),
    );
  }

  bool _tileHasIssue(int r, int c) {
    final m = _maskAt(r, c);
    bool warn = false;
    // 바깥으로 나가는 선/이웃과 비정합 선 여부
    if ((m & U) != 0) {
      if (r == 0) warn = true;
      else if ((tiles[_idx(r - 1, c)].mask & D) == 0) warn = true;
    }
    if ((m & R) != 0) {
      if (c == cols - 1) warn = true;
      else if ((tiles[_idx(r, c + 1)].mask & L) == 0) warn = true;
    }
    if ((m & D) != 0) {
      if (r == rows - 1) warn = true;
      else if ((tiles[_idx(r + 1, c)].mask & U) == 0) warn = true;
    }
    if ((m & L) != 0) {
      if (c == 0) warn = true;
      else if ((tiles[_idx(r, c - 1)].mask & R) == 0) warn = true;
    }
    return warn;
  }

  Widget _pill({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 타일 위젯 + 페인터
// ──────────────────────────────────────────────────────────────

class _TileWidget extends StatelessWidget {
  final int mask; // 4방향 비트
  final bool locked;
  final bool server;
  final double size;
  final bool? hintConnected; // true: 서버 연결, false: 미연결, null: 힌트 끔
  final bool? hintWarn;      // true: 경고(미스매치/외부), null: 힌트 끔
  final VoidCallback onTap;
  final VoidCallback onLong;

  const _TileWidget({
    Key? key,
    required this.mask,
    required this.locked,
    required this.server,
    required this.size,
    required this.onTap,
    required this.onLong,
    this.hintConnected,
    this.hintWarn,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final warn = hintWarn == true;
    final connected = hintConnected == true;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
        ),
        child: Stack(
          children: [
            CustomPaint(
              painter: _WirePainter(
                mask: mask,
                server: server,
                colorBase: connected ? Colors.teal : Colors.black54,
                warn: warn,
              ),
              size: Size.square(size),
            ),
            if (locked)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.lock, size: 16, color: Colors.black45),
              ),
          ],
        ),
      ),
    );
  }
}

class _WirePainter extends CustomPainter {
  final int mask;
  final bool server;
  final Color colorBase;
  final bool warn;

  static const int U = 1, R = 2, D = 4, L = 8;

  _WirePainter({
    required this.mask,
    required this.server,
    required this.colorBase,
    required this.warn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final radius = min(w, h) * 0.18;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = min(w, h) * 0.10
      ..strokeCap = StrokeCap.round
      ..color = warn ? Colors.redAccent : colorBase;

    // 백그라운드 연한 가이드
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black12;
    // 경계 가이드(가볍게)
    canvas.drawRect(Offset.zero & size, guide);

    // 4방향 선
    void drawDir(Offset from, Offset to) {
      canvas.drawLine(from, to, line);
    }

    final offset = radius + line.strokeWidth / 2 + 2;

    if ((mask & U) != 0) drawDir(Offset(cx, cy), Offset(cx, 0 + offset));
    if ((mask & R) != 0) drawDir(Offset(cx, cy), Offset(w - offset, cy));
    if ((mask & D) != 0) drawDir(Offset(cx, cy), Offset(cx, h - offset));
    if ((mask & L) != 0) drawDir(Offset(cx, cy), Offset(0 + offset, cy));

    // 중앙 노드/서버
    final fill = Paint()..color = server ? const Color(0xFF1B5E20) : (warn ? Colors.redAccent : colorBase);
    if (server) {
      // 서버는 ■ 모양
      final s = radius * 1.3;
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: s, height: s);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.2)),
        fill,
      );
    } else {
      // 일반 장치 ○
      canvas.drawCircle(Offset(cx, cy), radius, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _WirePainter old) {
    return old.mask != mask || old.server != server || old.colorBase != colorBase || old.warn != warn;
  }
}

// ──────────────────────────────────────────────────────────────
// 모델/체크 구조체
// ──────────────────────────────────────────────────────────────

class _Tile {
  int mask;
  bool lock;
  bool isServer; // 서버 플래그(현재 표시는 좌표 기반, 필요시 사용할 수 있도록 유지)

  _Tile({
    required this.mask,
    this.lock = false,
  }) : isServer = false;
}

class _CheckResult {
  final int mismatches; // 이웃과 비정합한 선 개수(방향 단위)
  final int outside;    // 보드 밖으로 나간 선 개수(방향 단위)
  final List<bool> connected; // 서버로부터 실제 연결된 타일
  final bool solved;
  _CheckResult({
    required this.mismatches,
    required this.outside,
    required this.connected,
    required this.solved,
  });
}
