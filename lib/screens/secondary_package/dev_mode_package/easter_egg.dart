// 생략된 imports 유지
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Block 클래스 생략 없이 유지
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

class EasterEgg extends StatefulWidget {
  const EasterEgg({super.key});

  @override
  State<EasterEgg> createState() => _EasterEggState();
}

class _EasterEggState extends State<EasterEgg> {
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
    if (!mounted) return;
    setState(() {
      score = 0;
      board = List.generate(rowCount, (_) => List.filled(colCount, null));
      currentBlock = _randomBlock();
      nextBlock = _randomBlock();
      gameOver = false;
      isPaused = false;
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
    if (!mounted || gameOver || isPaused) return;
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
    for (final p in currentBlock!.shape) {
      final x = currentBlock!.position.x + p.x;
      final y = currentBlock!.position.y + p.y;
      if (x >= 0 && x < rowCount && y >= 0 && y < colCount) {
        board[x][y] = currentBlock!.color;
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
    if (gameOver) return;
    Point<int> dropPos = currentBlock!.position;
    while (_canMove(currentBlock!, Point(dropPos.x + 1, dropPos.y))) {
      dropPos = Point(dropPos.x + 1, dropPos.y);
    }
    setState(() => currentBlock = currentBlock!.copyWith(position: dropPos));
    _tick();
  }

  Widget _buildCell(int x, int y) {
    Color? color = board[x][y];
    for (final p in currentBlock?.shape ?? []) {
      final px = currentBlock!.position.x + p.x;
      final py = currentBlock!.position.y + p.y;
      if (px == x && py == y) {
        color = currentBlock!.color;
        break;
      }
    }
    return Container(
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: color ?? Colors.grey[200],
        border: Border.all(color: Colors.black12),
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
          final isActive = nextBlock?.shape.contains(Point(row, col)) ?? false;
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

  Widget _controlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('테트리스'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            onPressed: () => setState(() => isPaused = !isPaused),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('점수', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        Text('$score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('최고 점수', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        Text('$highScore', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('다음 블록', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 4),
                        _buildPreviewBlock(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GestureDetector(
              onTap: _hardDrop,
              child: AspectRatio(
                aspectRatio: colCount / rowCount,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black),
                    color: Colors.white,
                  ),
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
            ),
          ),
          const SizedBox(height: 12),
          if (!gameOver)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _controlButton(icon: Icons.arrow_left, color: Colors.blue, onTap: _moveLeft),
                _controlButton(icon: Icons.rotate_right, color: Colors.green, onTap: _rotate),
                _controlButton(icon: Icons.arrow_right, color: Colors.red, onTap: _moveRight),
              ],
            )
          else
            Column(
              children: [
                const Text(
                  'Game Over',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: startGame,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  child: const Text('다시 시작', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 12),
              ],
            ),
        ],
      ),
    );
  }
}
