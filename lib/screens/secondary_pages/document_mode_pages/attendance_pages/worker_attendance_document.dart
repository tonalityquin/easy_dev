// 생략 없음: 전체 코드 제공
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkerAttendanceDocument extends StatefulWidget {
  const WorkerAttendanceDocument({super.key});

  @override
  State<WorkerAttendanceDocument> createState() => _WorkerAttendanceDocumentState();
}

class Block {
  List<List<Point<int>>> shapes;
  int rotationIndex;
  Point<int> position;
  Color color;

  Block({
    required this.shapes,
    this.rotationIndex = 0,
    this.position = const Point(0, 4),
    required this.color,
  });

  List<Point<int>> get shape => shapes[rotationIndex % shapes.length];

  Block copyWith({int? rotationIndex, Point<int>? position}) {
    return Block(
      shapes: shapes,
      rotationIndex: rotationIndex ?? this.rotationIndex,
      position: position ?? this.position,
      color: color,
    );
  }
}

class _WorkerAttendanceDocumentState extends State<WorkerAttendanceDocument> {
  static const int rowCount = 20;
  static const int colCount = 10;
  List<List<Color?>> board = List.generate(rowCount, (_) => List.filled(colCount, null));
  Block? currentBlock;
  Block? nextBlock;
  Timer? _timer;
  int score = 0;
  int highScore = 0;
  bool gameOver = false;
  bool isPaused = false;
  Set<Point<int>> recentFixedCells = {};

  final List<Block> blockTypes = [
    Block(
      shapes: [
        [Point(0, 1), Point(1, 1), Point(2, 1), Point(3, 1)],
        [Point(1, 0), Point(1, 1), Point(1, 2), Point(1, 3)],
      ],
      color: Colors.cyan,
    ),
    Block(
      shapes: [
        [Point(0, 1), Point(1, 0), Point(1, 1), Point(1, 2)],
        [Point(0, 1), Point(1, 1), Point(2, 1), Point(1, 2)],
        [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 1)],
        [Point(0, 1), Point(1, 1), Point(2, 1), Point(1, 0)],
      ],
      color: Colors.purple,
    ),
    Block(
      shapes: [
        [Point(0, 0), Point(0, 1), Point(1, 0), Point(1, 1)],
      ],
      color: Colors.yellow,
    ),
    Block(
      shapes: [
        [Point(0, 1), Point(0, 2), Point(1, 0), Point(1, 1)],
        [Point(0, 0), Point(1, 0), Point(1, 1), Point(2, 1)],
      ],
      color: Colors.green,
    ),
    Block(
      shapes: [
        [Point(0, 0), Point(0, 1), Point(1, 1), Point(1, 2)],
        [Point(0, 1), Point(1, 0), Point(1, 1), Point(2, 0)],
      ],
      color: Colors.red,
    ),
    Block(
      shapes: [
        [Point(0, 0), Point(1, 0), Point(2, 0), Point(2, 1)],
        [Point(1, 0), Point(1, 1), Point(1, 2), Point(0, 2)],
        [Point(0, 0), Point(0, 1), Point(1, 1), Point(2, 1)],
        [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 0)],
      ],
      color: Colors.orange,
    ),
    Block(
      shapes: [
        [Point(0, 1), Point(1, 1), Point(2, 1), Point(2, 0)],
        [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 2)],
        [Point(0, 0), Point(0, 1), Point(1, 0), Point(2, 0)],
        [Point(0, 0), Point(1, 0), Point(1, 1), Point(1, 2)],
      ],
      color: Colors.blue,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadHighScore();
    startGame();
  }

  void _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      highScore = prefs.getInt('highScore') ?? 0;
    });
  }

  void _saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('highScore', highScore);
  }

  void startGame() {
    setState(() {
      score = 0;
      board = List.generate(rowCount, (_) => List.filled(colCount, null));
      currentBlock = _randomBlock();
      nextBlock = _randomBlock();
      gameOver = false;
      isPaused = false;
      recentFixedCells.clear();
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  Block _randomBlock() {
    final rand = Random();
    final block = blockTypes[rand.nextInt(blockTypes.length)];
    return block.copyWith(position: const Point(0, 4));
  }

  void _tick() {
    if (gameOver || isPaused) return;
    final nextPos = Point(currentBlock!.position.x + 1, currentBlock!.position.y);
    if (_canMove(currentBlock!, nextPos)) {
      setState(() => currentBlock = currentBlock!.copyWith(position: nextPos));
    } else {
      _fixBlock();
      _clearLines();
      final next = nextBlock!;
      if (_canMove(next, next.position)) {
        setState(() {
          currentBlock = next;
          nextBlock = _randomBlock();
        });
      } else {
        setState(() => gameOver = true);
        _timer?.cancel();
      }
    }
  }

  void _fixBlock() {
    recentFixedCells.clear();
    for (final p in currentBlock!.shape) {
      final x = currentBlock!.position.x + p.x;
      final y = currentBlock!.position.y + p.y;
      if (x >= 0 && x < rowCount && y >= 0 && y < colCount) {
        board[x][y] = currentBlock!.color;
        recentFixedCells.add(Point(x, y));
      }
    }
  }

  void _clearLines() {
    board.removeWhere((row) => row.every((cell) => cell != null));
    int cleared = rowCount - board.length;
    if (cleared > 0) {
      setState(() {
        board.insertAll(0, List.generate(cleared, (_) => List.filled(colCount, null)));
        score += cleared * 100;
        if (score > highScore) {
          highScore = score;
          _saveHighScore();
        }
        recentFixedCells.clear();
      });
    }
  }

  bool _canMove(Block block, Point<int> nextPos, [int? rotationIndex]) {
    final shape = block.shapes[rotationIndex ?? block.rotationIndex];
    for (final p in shape) {
      final x = nextPos.x + p.x;
      final y = nextPos.y + p.y;
      if (x < 0 || x >= rowCount || y < 0 || y >= colCount) return false;
      if (board[x][y] != null) return false;
    }
    return true;
  }

  void _moveLeft() {
    final next = Point(currentBlock!.position.x, currentBlock!.position.y - 1);
    if (_canMove(currentBlock!, next)) {
      setState(() => currentBlock = currentBlock!.copyWith(position: next));
    }
  }

  void _moveRight() {
    final next = Point(currentBlock!.position.x, currentBlock!.position.y + 1);
    if (_canMove(currentBlock!, next)) {
      setState(() => currentBlock = currentBlock!.copyWith(position: next));
    }
  }

  void _rotate() {
    final nextIndex = (currentBlock!.rotationIndex + 1) % currentBlock!.shapes.length;
    if (_canMove(currentBlock!, currentBlock!.position, nextIndex)) {
      setState(() => currentBlock = currentBlock!.copyWith(rotationIndex: nextIndex));
    }
  }

  void _hardDrop() {
    Point<int> dropPos = currentBlock!.position;
    while (_canMove(currentBlock!, Point(dropPos.x + 1, dropPos.y))) {
      dropPos = Point(dropPos.x + 1, dropPos.y);
    }
    setState(() => currentBlock = currentBlock!.copyWith(position: dropPos));
    _tick();
  }

  void _togglePause() => setState(() => isPaused = !isPaused);

  Widget _buildCell(int x, int y) {
    Color? color = board[x][y];
    bool isNew = recentFixedCells.contains(Point(x, y));
    for (final p in currentBlock?.shape ?? []) {
      final px = currentBlock!.position.x + p.x;
      final py = currentBlock!.position.y + p.y;
      if (px == x && py == y) {
        color = currentBlock!.color;
        break;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: color ?? Colors.grey[200],
        border: isNew ? Border.all(color: Colors.redAccent, width: 2) : Border.all(color: Colors.black12),
      ),
    );
  }

  Widget _buildPreviewBlock() {
    return SizedBox(
      width: 80,
      height: 80,
      child: GridView.count(
        crossAxisCount: 4,
        children: List.generate(16, (index) {
          final row = index ~/ 4;
          final col = index % 4;
          final isActive = nextBlock!.shape.contains(Point(row, col));
          return Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isActive ? nextBlock!.color : Colors.grey[300],
              border: Border.all(color: Colors.black12),
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 게임판 외부 탭 → 회전
      onTap: _rotate,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('테트리스'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              onPressed: _togglePause,
            ),
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('점수: $score', style: const TextStyle(fontSize: 18)),
                Text('최고 점수: $highScore', style: const TextStyle(fontSize: 18)),
                Column(children: [const Text('다음 블록'), _buildPreviewBlock()]),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  // 왼쪽 영역 → 왼쪽 이동
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _moveLeft,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // 게임판 (중앙 영역) → 하드 드롭
                  AspectRatio(
                    aspectRatio: colCount / rowCount,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _hardDrop,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: colCount,
                        ),
                        itemCount: rowCount * colCount,
                        itemBuilder: (context, index) {
                          final x = index ~/ colCount;
                          final y = index % colCount;
                          return _buildCell(x, y);
                        },
                      ),
                    ),
                  ),
                  // 오른쪽 영역 → 오른쪽 이동
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _moveRight,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!gameOver)
              const Text(
                '하드 드롭: 게임판 터치  |  회전: 바깥 터치  |  좌우 이동: 화면 양옆',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              )
            else
              ElevatedButton(
                onPressed: startGame,
                child: const Text('다시 시작'),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
