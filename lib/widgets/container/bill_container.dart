import 'package:flutter/material.dart';

class BillCustomBoxStyles {
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Colors.black,
  );
  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );
  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
  static const VerticalDivider verticalDivider = VerticalDivider(
    width: 1,
    thickness: 1,
    color: Colors.grey,
  );
}

class BillContainer extends StatelessWidget {
  final String leftText;
  final String centerTopText;
  final String centerBottomText;
  final String rightTopText;
  final String rightBottomText;
  final VoidCallback onTap;
  final bool isSelected; // ✅ 추가됨

  const BillContainer({
    super.key,
    required this.leftText,
    required this.centerTopText,
    required this.centerBottomText,
    required this.rightTopText,
    required this.rightBottomText,
    required this.onTap,
    required this.isSelected, // ✅ 필수 매개변수 추가
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        // ✅ 애니메이션 지속 시간
        curve: Curves.easeInOut,
        // ✅ 부드러운 전환 애니메이션
        width: double.infinity,
        height: 120,
        alignment: Alignment.center,
        // ✅ 중앙 기준으로 정렬
        transformAlignment: Alignment.center,
        // ✅ 축소 시 중앙 기준 유지
        transform: isSelected
            ? (Matrix4.identity()..scale(0.95)) // ✅ 선택되면 95% 크기로 축소
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.2) : Colors.white,
          border: Border.all(color: Colors.black, width: 2.0),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Row(
          children: [
            // Left Section
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  leftText,
                  style: BillCustomBoxStyles.titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            BillCustomBoxStyles.verticalDivider,
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: Text(
                              centerTopText,
                              style: BillCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        BillCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              centerBottomText,
                              style: BillCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  BillCustomBoxStyles.commonDivider,
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: Text(
                              rightTopText,
                              style: BillCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        BillCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              rightBottomText,
                              style: BillCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
