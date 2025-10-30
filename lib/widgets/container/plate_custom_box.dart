import 'package:flutter/material.dart';

class PlateCustomBoxStyles {
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
  static const TextStyle miniTitleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Colors.black,
  );
  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
}

class PlateCustomBox extends StatelessWidget {
  final String topLeftText;        // 좌측 라벨(요구사항: '소속' 하드코딩 예정)
  final String topCenterText;      // NEW: 가운데(기존 topLeftText 내용 이동)
  final String topRightUpText;
  final String topRightDownText;
  final String midLeftText;
  final String midCenterText;
  final String midRightText;
  final String bottomLeftLeftText;
  final String bottomLeftCenterText;
  final String bottomRightText;
  final VoidCallback onTap;
  final bool isSelected;
  final Color? backgroundColor;

  const PlateCustomBox({
    super.key,
    required this.topLeftText,
    required this.topCenterText,    // NEW
    required this.topRightUpText,
    required this.topRightDownText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.bottomLeftLeftText,
    required this.bottomLeftCenterText,
    required this.bottomRightText,
    required this.onTap,
    required this.isSelected,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final combinedBottomLeftText =
    [bottomLeftLeftText, if (bottomLeftCenterText.isNotEmpty) bottomLeftCenterText].join(' ');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: 120,
        alignment: Alignment.center,
        transformAlignment: Alignment.center,
        transform: isSelected ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: backgroundColor ?? (isSelected ? Colors.blue.withOpacity(0.2) : Colors.white),
          border: Border.all(color: Colors.black, width: 2.0),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Column(
          children: [
            // ── 상단 줄: [좌: '소속'(2)] | [중: 기존 큰 텍스트(5)] | [우: 정산 타입/요금(3)]
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  // 좌: '소속' 라벨
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        topLeftText,
                        style: PlateCustomBoxStyles.titleStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black),

                  // 중: 기존 topLeftText에 들어가던 번호판/지역 텍스트
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: Text(
                        topCenterText,
                        style: PlateCustomBoxStyles.titleStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black),

                  // 우: 정산 타입 / 요금 (두 줄)
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          topRightUpText,
                          style: PlateCustomBoxStyles.miniTitleStyle.copyWith(
                            fontSize: 12,
                            overflow: TextOverflow.ellipsis,
                          ),
                          softWrap: false,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          topRightDownText,
                          style: PlateCustomBoxStyles.miniTitleStyle.copyWith(
                            fontSize: 12,
                            height: 1.5,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0, color: Colors.black),

            // ── 중단 줄 (기존 그대로)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: Text(midLeftText, style: PlateCustomBoxStyles.titleStyle),
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(midCenterText, style: PlateCustomBoxStyles.subtitleStyle),
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        midRightText,
                        style: const TextStyle(color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0, color: Colors.black),

            // ── 하단 줄 (기존 그대로)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Center(
                      child: Text(
                        combinedBottomLeftText,
                        style: PlateCustomBoxStyles.miniTitleStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        bottomRightText,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
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
