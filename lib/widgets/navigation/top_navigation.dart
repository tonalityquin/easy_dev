import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../widgets/dialog/area_picker_dialog.dart';

/// ✅ 지역 선택 위젯 (AppBar의 title로 삽입)
class TopNavigation extends StatelessWidget {
  const TopNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final plateState = context.read<PlateState>();
    final selectedArea = areaState.currentArea;
    final isAreaSelectable = true;

    return GestureDetector(
      onTap: () => showAreaPickerDialog(
        context: context,
        areaState: areaState,
        plateState: plateState,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.car, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 6),
          Text(
            selectedArea.isNotEmpty ? selectedArea : '지역 없음',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (isAreaSelectable) ...[
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
          ],
        ],
      ),
    );
  }
}

/// ✅ 본사 페이지 예시
class HeadquarterPage extends StatelessWidget {
  const HeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const Center(
        child: Text('🏢 본사 페이지'),
      ),
    );
  }
}

/// ✅ 일반 지역(TypePage) 예시
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const Center(
        child: Text('🛠 번호 등록 | 업무 보조'),
      ),
    );
  }
}
