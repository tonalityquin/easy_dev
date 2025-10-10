import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// 튜토리얼 바텀시트만 사용 (오프라인에서 area 로직 제거)
import '../offline_tutorials//offline_tutorial_bottom_sheet.dart';

/// 오프라인 상단 네비게이션 (튜토리얼 전용)
/// - 탭하면 튜토리얼 목록 바텀시트를 연다.
class OfflineTopNavigation extends StatelessWidget {
  const OfflineTopNavigation({
    super.key,
    this.title = '튜토리얼',
    this.enabled = true,
    this.leading,
  });

  final String title;
  final bool enabled;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = leading ??
        const Icon(CupertinoIcons.book_solid, size: 18, color: Colors.blueAccent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => offlineTutorialBottomSheet(context: context) : null,
        splashColor: Colors.grey.withOpacity(0.2),
        highlightColor: Colors.grey.withOpacity(0.1),
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leadingIcon,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (enabled) ...[
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
