import 'package:flutter/material.dart';

class AdjustmentCustomBoxStyles {
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

class AdjustmentCustomBox extends StatelessWidget {
  final String leftText;
  final String centerTopText;
  final String centerBottomText;
  final String rightTopText;
  final String rightBottomText;
  final VoidCallback onTap;
  final Color backgroundColor;

  const AdjustmentCustomBox({
    super.key,
    required this.leftText,
    required this.centerTopText,
    required this.centerBottomText,
    required this.rightTopText,
    required this.rightBottomText,
    required this.onTap,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: Colors.black, width: 2.0),
        ),
        child: Row(
          children: [
            // Left Section
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  leftText,
                  style: AdjustmentCustomBoxStyles.titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            AdjustmentCustomBoxStyles.verticalDivider,
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
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        AdjustmentCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              centerBottomText,
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AdjustmentCustomBoxStyles.commonDivider,
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: Text(
                              rightTopText,
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        AdjustmentCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              rightBottomText,
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
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
