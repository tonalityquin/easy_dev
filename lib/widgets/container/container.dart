import 'package:flutter/material.dart';

class CustomBox extends StatelessWidget {
  final String leftText;
  final String rightTextTop;
  final String rightTextBottomLeft;
  final String rightTextBottomRight; // 우하단 중간
  final String? rightTextBottomRightMost; // 우하단 우측 (선택적 매개변수)
  final VoidCallback onLeftTap;
  final VoidCallback? onRightTapOverlay;
  final VoidCallback onRightTopTap;
  final VoidCallback onRightBottomLeftTap;
  final VoidCallback onRightBottomRightTap;
  final VoidCallback? onRightBottomRightMostTap; // 우하단 우측 탭 동작
  final Color backgroundColor;
  final bool showRightTapOverlay;

  const CustomBox({
    super.key,
    required this.leftText,
    required this.rightTextTop,
    required this.rightTextBottomLeft,
    required this.rightTextBottomRight, // 우하단 중간 텍스트
    this.rightTextBottomRightMost, // 우하단 우측 (선택적 매개변수)
    required this.onLeftTap,
    required this.onRightTopTap,
    required this.onRightBottomLeftTap,
    required this.onRightBottomRightTap,
    this.onRightBottomRightMostTap, // 선택적 매개변수
    this.onRightTapOverlay,
    this.backgroundColor = Colors.white,
    this.showRightTapOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2.0),
      ),
      child: Row(
        children: [
          // 좌측 영역
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: onLeftTap,
              child: Container(
                alignment: Alignment.center,
                color: backgroundColor,
                child: Text(leftText, style: const TextStyle(fontSize: 14, color: Colors.black)),
              ),
            ),
          ),
          const VerticalDivider(width: 2.0, color: Colors.black),
          // 우측 영역
          Expanded(
            flex: 7,
            child: Stack(
              children: [
                Column(
                  children: [
                    // 우측 상단
                    Expanded(
                      flex: 5,
                      child: GestureDetector(
                        onTap: onRightTopTap,
                        child: Container(
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Text(rightTextTop, style: const TextStyle(fontSize: 14, color: Colors.black)),
                        ),
                      ),
                    ),
                    const Divider(height: 2.0, color: Colors.black),
                    // 우측 하단
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          // 우측 하단 좌측
                          Expanded(
                            flex: 4,
                            child: GestureDetector(
                              onTap: onRightBottomLeftTap,
                              child: Container(
                                alignment: Alignment.center,
                                color: Colors.transparent,
                                child: Text(rightTextBottomLeft,
                                    style: const TextStyle(fontSize: 14, color: Colors.black)),
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 2.0, color: Colors.black),
                          // 우측 하단 중간
                          Expanded(
                            flex: 3,
                            child: GestureDetector(
                              onTap: onRightBottomRightTap,
                              child: Container(
                                alignment: Alignment.center,
                                color: Colors.transparent,
                                child: Text(
                                  rightTextBottomRight, // 경과 시간
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold, // 글자 굵게 설정
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const VerticalDivider(width: 2.0, color: Colors.black),
                          // 우측 하단 우측
                          Expanded(
                            flex: 3,
                            child: GestureDetector(
                              onTap: onRightBottomRightMostTap ?? () {},
                              child: Container(
                                alignment: Alignment.center,
                                color: Colors.transparent,
                                child: Text(
                                  rightTextBottomRightMost ?? '',
                                  style: const TextStyle(fontSize: 14, color: Colors.black),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 우측 영역 오버레이
                if (showRightTapOverlay)
                  GestureDetector(
                    onTap: onRightTapOverlay,
                    child: Container(
                      color: Colors.white,
                      child: const Center(
                        child: Text(
                          '주차 영역 선택',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
