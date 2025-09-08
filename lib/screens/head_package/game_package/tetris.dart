// lib/screens/stub_package/game_package/tetris.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// parts
part 'tetris_package/tetris_models.dart';
part 'tetris_package/tetris_templates.dart';
part 'tetris_package/tetris_painter.dart';
part 'tetris_package/tetris_base.dart';
part 'tetris_package/tetris_input.dart';
part 'tetris_package/tetris_ui.dart';
part 'tetris_package/tetris_state.dart';

/// 완전 신규 테트리스 (SRS/7-bag/락딜레이/홀드/다음/고스트/키보드/제스처)
class Tetris extends StatefulWidget {
  const Tetris({super.key});
  @override
  State<Tetris> createState() => _TetrisState();
}
