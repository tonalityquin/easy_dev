import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../states/plate/plate_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/container/plate_container.dart';
import '../departure_completed_pages/field_calendar_inline.dart';

import '../departure_completed_pages/widgets/departure_completed_status_bottom_sheet.dart';
import '../../../models/plate_model.dart';
import 'departure_completed_control_buttons.dart';

class DepartureCompletedUnsettledTab extends StatefulWidget {
  const DepartureCompletedUnsettledTab({
    super.key,
    required this.firestorePlates,
    required this.userName,
  });

  final List<PlateModel> firestorePlates;
  final String userName;

  @override
  State<DepartureCompletedUnsettledTab> createState() => _DepartureCompletedUnsettledTabState();
}

class _DepartureCompletedUnsettledTabState extends State<DepartureCompletedUnsettledTab> {
  bool _openCalendar = true;
  bool _openUnsettled = false;

  void _toggleCalendar() {
    setState(() {
      if (_openCalendar) {
        _openCalendar = false;
        _openUnsettled = false;
      } else {
        _openCalendar = true;
        _openUnsettled = false;
      }
    });
  }

  void _toggleUnsettled() {
    setState(() {
      if (_openUnsettled) {
        _openUnsettled = false;
        _openCalendar = false;
      } else {
        _openUnsettled = true;
        _openCalendar = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final total = widget.firestorePlates.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            _SectionHeaderTile(
              title: '날짜 선택',
              subtitle: '선택한 날짜의 출차 데이터를 확인합니다.',
              icon: Icons.calendar_month,
              isOpen: _openCalendar,
              onTap: _toggleCalendar,
            ),
            _CollapsibleCard(
              isOpen: _openCalendar,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: FieldCalendarInline(),
              ),
            ),
            const SizedBox(height: 12),
            _SectionHeaderTile(
              title: '미정산',
              subtitle: '선택한 날짜 · 현재 지역 기준',
              icon: Icons.list_alt,
              trailing: _CountBadge(count: total),
              isOpen: _openUnsettled,
              onTap: _toggleUnsettled,
            ),
            _CollapsibleCard(
              isOpen: _openUnsettled,
              child: (total == 0)
                  ? const _EmptyState(
                      icon: Icons.inbox_outlined,
                      title: '표시할 번호판이 없습니다',
                      message: '달력을 바꾸거나 검색을 사용해 보세요.',
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: PlateContainer(
                        data: widget.firestorePlates,
                        collection: PlateType.departureCompleted,
                        filterCondition: (_) => true,
                        onPlateTap: (plateNumber, area) async {
                          await plateState.togglePlateIsSelected(
                            collection: PlateType.departureCompleted,
                            plateNumber: plateNumber,
                            userName: widget.userName,
                            onError: (msg) => showFailedSnackbar(context, msg),
                          );

                          final currentSelected = plateState.getSelectedPlate(
                            PlateType.departureCompleted,
                            widget.userName,
                          );

                          if (currentSelected != null &&
                              currentSelected.isSelected &&
                              currentSelected.plateNumber == plateNumber) {
                            await showDepartureCompletedStatusBottomSheet(
                              context: context,
                              plate: currentSelected,
                            );
                          }
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DepartureCompletedControlButtons(
        isSearchMode: false,
        onResetSearch: () {}, // no-op
        onShowSearchDialog: () {}, // no-op
      ),
    );
  }
}

class _SectionHeaderTile extends StatelessWidget {
  const _SectionHeaderTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOpen,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chevron = isOpen ? Icons.expand_less : Icons.expand_more;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                const SizedBox(width: 6),
                Icon(chevron, size: 20, color: Colors.grey[700]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsibleCard extends StatelessWidget {
  const _CollapsibleCard({
    required this.isOpen,
    required this.child,
  });

  final bool isOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: Material(
        elevation: 1.5,
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Colors.grey[500]),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
