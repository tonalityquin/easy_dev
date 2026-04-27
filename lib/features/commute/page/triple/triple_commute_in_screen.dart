import 'package:flutter/material.dart';

import '../../utils/commute_mode_spec.dart';
import '../common/common_commute_in_screen.dart';

class TripleCommuteInScreen extends StatelessWidget {
  const TripleCommuteInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonCommuteInScreen(
      spec: CommuteModeSpec.tripleMode,
    );
  }
}
