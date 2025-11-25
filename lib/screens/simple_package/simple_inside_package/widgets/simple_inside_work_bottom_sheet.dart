import 'package:flutter/material.dart';

import 'sections/simple_inside_work_form_page.dart';

void showSimpleInsideWorkFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SimpleInsideWorkFormPage(),
    ),
  );
}
