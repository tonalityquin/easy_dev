import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../widgets/dialog/area_picker_bottom_sheet.dart';

/// ✅ 지역 선택 위젯 (AppBar의 title로 삽입)
class TopNavigation extends StatelessWidget {
  const TopNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final plateState = context.read<PlateState>();
    final selectedArea = areaState.currentArea;
    final isAreaSelectable = true;

    return Material(
      // InkWell의 splash/highlight가 보이도록 투명한 Material 배경
      color: Colors.transparent,
      child: InkWell(
        // AppBar 전체 영역을 터치 가능하게
        onTap: () => areaPickerBottomSheet(
          context: context,
          areaState: areaState,
          plateState: plateState,
        ),
        splashColor: Colors.grey.withOpacity(0.2),
        highlightColor: Colors.grey.withOpacity(0.1),
        child: SizedBox(
          width: double.infinity,    // 가능한 가로 전체 영역 차지
          height: kToolbarHeight,    // AppBar 높이만큼 확보
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
        ),
      ),
    );
  }
}
