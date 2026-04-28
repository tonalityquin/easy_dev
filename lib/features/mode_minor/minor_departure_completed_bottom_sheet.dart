import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/application/field_calendar_state.dart';
import '../../../shared/plate/application/minor/minor_plate_state.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/plate/domain/models/plate_model.dart';
import 'departure_completed_package/minor_departure_completed_tab_settled.dart';
import 'departure_completed_package/minor_departure_completed_tab_unsettled.dart';
import 'departure_completed_package/widgets/minor_departure_completed_selected_date_bar.dart';

class MinorDepartureCompletedBottomSheet extends StatefulWidget {
  const MinorDepartureCompletedBottomSheet({super.key});

  @override
  State<MinorDepartureCompletedBottomSheet> createState() =>
      _MinorDepartureCompletedBottomSheetState();
}

class _MinorDepartureCompletedBottomSheetState
    extends State<MinorDepartureCompletedBottomSheet> {
  static const String screenTag = 'departure completed';

  final bool _isSorted = true;

  bool _areaEquals(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
            const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6),
          child: Semantics(
            label: 'screen_tag: $screenTag',
            child: Text(screenTag, style: style),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final plateState = context.watch<MinorPlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();

    final selectedDateRaw =
        context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(
      selectedDateRaw.year,
      selectedDateRaw.month,
      selectedDateRaw.day,
    );

    final baseList = plateState.minorGetPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    final List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      return !p.isLockedFee && sameArea;
    }).toList()
      ..sort((a, b) => _isSorted
          ? b.requestTime.compareTo(a.requestTime)
          : a.requestTime.compareTo(b.requestTime));

    final selectedPlate = plateState.minorGetSelectedPlate(
        PlateType.departureCompleted, userName);
    final plateNumber = selectedPlate?.plateNumber ?? '';

    return WillPopScope(
      onWillPop: () async {
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.minorTogglePlateIsSelected(
            collection: PlateType.departureCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }
        return true;
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
          ),
          child: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                final tabController = DefaultTabController.of(context);

                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    final isSettled = tabController.index == 1;

                    return Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Column(
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              width: 60,
                              height: 6,
                              decoration: BoxDecoration(
                                color: cs.outlineVariant.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          _buildScreenTag(context),
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TabBar(
                              labelColor: cs.onSurface,
                              unselectedLabelColor: cs.onSurfaceVariant,
                              indicatorColor: cs.primary,
                              dividerColor: Colors.transparent,
                              tabs: const [
                                Tab(text: '미정산'),
                                Tab(text: '정산'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          MinorDepartureCompletedSelectedDateBar(
                            visible: !isSettled,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: TabBarView(
                              children: [
                                MinorDepartureCompletedUnsettledTab(
                                  firestorePlates: firestorePlates,
                                  userName: userName,
                                ),
                                MinorDepartureCompletedSettledTab(
                                  area: area,
                                  division: division,
                                  selectedDate: selectedDate,
                                  plateNumber: plateNumber,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
