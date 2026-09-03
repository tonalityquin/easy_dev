import 'package:flutter/material.dart';

import '../../utils/commute_mode_spec.dart';
import '../common/common_commute_in_screen.dart';

class SingleCommuteInScreen extends StatelessWidget {
  const SingleCommuteInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonCommuteInScreen(
      spec: CommuteModeSpec.singleMode,
    );
  }
}
