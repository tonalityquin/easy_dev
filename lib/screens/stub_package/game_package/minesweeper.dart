library minesweeper_game;

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart'; // compute
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'mine_package/mine_models.dart';
part 'mine_package/mine_gen.dart';
part 'mine_package/mine_state.dart';
part 'mine_package/mine_ui.dart';

class Minesweeper extends StatefulWidget {
  const Minesweeper({super.key});
  @override
  State<Minesweeper> createState() => _MinesweeperState();
}
