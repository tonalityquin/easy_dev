
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';


part 'tetris_package/tetris_models.dart';
part 'tetris_package/tetris_templates.dart';
part 'tetris_package/tetris_painter.dart';
part 'tetris_package/tetris_base.dart';
part 'tetris_package/tetris_input.dart';
part 'tetris_package/tetris_ui.dart';
part 'tetris_package/tetris_state.dart';


class Tetris extends StatefulWidget {
  const Tetris({super.key});
  @override
  State<Tetris> createState() => _TetrisState();
}
