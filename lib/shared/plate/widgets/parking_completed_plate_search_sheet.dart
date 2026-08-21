import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/mode_double/parking_completed_package/widgets/double_parking_completed_plate_search_results.dart';
import '../../../features/mode_double/parking_completed_package/widgets/double_parking_completed_status_bottom_sheet.dart';
import '../../../features/mode_minor/parking_completed_package/widgets/minor_parking_completed_plate_search_results.dart';
import '../../../features/mode_minor/parking_completed_package/widgets/minor_parking_completed_status_bottom_sheet.dart';
import '../../../features/mode_triple/parking_completed_package/widgets/triple_parking_completed_plate_search_results.dart';
import '../../../features/mode_triple/parking_completed_package/widgets/triple_parking_completed_status_bottom_sheet.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../application/common/delete_plate.dart';
import '../application/common/movement_plate.dart';
import '../domain/enums/plate_type.dart';
import '../domain/models/plate_model.dart';
import '../domain/models/plate_out_log_search_result.dart';
import '../domain/repositories/plate_repository.dart';
import 'plate_out_log_search_results.dart';
import 'plate_remove_dialog.dart';
import 'plate_search_mode_switch.dart';

enum ParkingCompletedSearchVariant { minor, double, triple }

Future<void> showParkingCompletedPlateSearchSideDock({
  required BuildContext context,
  required String area,
  required ParkingCompletedSearchVariant variant,
  void Function(String)? onSearch,
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '번호판 검색 Side Dock',
    initialMessage: '번호판 검색 Side Dock을 준비합니다.',
    useCommonUi: true,
    showDialogImmediately: false,
    developerModeMessage: '개발자 모드 ON: 검색 동작을 추적하고 Status Dialog에서 debugPrint 코드를 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 번호판 검색 Side Dock을 실행합니다.',
  );
  trace.log(
    'plate_search_dock_open presentation=right_side_dock direction=right_to_left layout=left_rail_management_content resultPresentation=ops_management_list keypadPlacement=fixed_bottom keypadVisibility=persistent railDesign=common_operations railMetricsSource=CommonSideRailMetrics handoffPolicy=close_then_open area=$area variant=${variant.name} developerMode=${trace.developerMode} debugPrint=clipboard_copy_supported',
    progress: .08,
  );

  try {
    final selected = await showCommonRightSideDock<PlateModel>(
      context: context,
      barrierLabel: '번호판 검색',
      maxWidth: 360,
      widthFactor: .92,
      barrierDismissible: true,
      builder: (_) => ParkingCompletedPlateSearchSideDock(
        area: area,
        variant: variant,
        trace: trace,
        onSearch: onSearch,
      ),
    );
    trace.log(
      'plate_search_dock_closed presentation=right_side_dock result=${selected?.plateNumber ?? 'none'} sourceDock=plate_search sourcePopResolvedBeforeTarget=true overlayStacking=false',
      progress: selected == null ? .94 : .72,
    );

    if (selected != null && context.mounted) {
      trace.log(
        'plate_search_status_handoff_started plate=${selected.plateNumber} sourceDock=plate_search targetDock=parking_status handoffPolicy=close_then_open sourcePopResolvedBeforeTarget=true overlayStacking=false',
        progress: .76,
      );
      await _showPlateStatusAfterSearchHandoff(
        context: context,
        selected: selected,
        variant: variant,
        trace: trace,
      );
      trace.log(
        'plate_search_status_handoff_completed plate=${selected.plateNumber} sourceDock=plate_search targetDock=parking_status returnTarget=type_page overlayStacking=false',
        progress: .92,
      );
    }

    await trace.succeed(
      selected == null
          ? '번호판 검색 Side Dock 세션이 종료되었습니다.'
          : '번호판 검색에서 상태 처리 Side Dock으로 순차 전환을 완료했습니다.',
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
  } catch (error, stackTrace) {
    await trace.fail(
      '번호판 검색 Side Dock 실행 중 예외가 발생했습니다.',
      error: error,
      stackTrace: stackTrace,
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    rethrow;
  }
}

Future<void> _showPlateStatusAfterSearchHandoff({
  required BuildContext context,
  required PlateModel selected,
  required ParkingCompletedSearchVariant variant,
  required DeveloperOperationTrace trace,
}) async {
  Future<void> onRequestEntry(MovementPlateTraceLog? traceLog) async {
    if (selected.typeEnum != PlateType.parkingCompleted) return;
    traceLog?.call(
      '검색 상태 변경 시작 to=parkingRequests plate=${selected.plateNumber} area=${selected.area}',
    );
    trace.log(
      'plate_search_status_mutation_started action=request_entry plate=${selected.plateNumber} handoff=true',
      progress: .82,
    );
    await context.read<MovementPlate>().goBackToParkingRequest(
      fromType: PlateType.parkingCompleted,
      plateNumber: selected.plateNumber,
      area: selected.area,
      newLocation: '미지정',
      traceLog: traceLog,
    );
    traceLog?.call(
      '검색 상태 변경 완료 to=parkingRequests plate=${selected.plateNumber} area=${selected.area}',
    );
    trace.log(
      'plate_search_status_mutation_completed action=request_entry plate=${selected.plateNumber} refresh=false returnTarget=type_page',
      progress: .86,
    );
  }

  Future<bool> onDelete() => _deletePlateAfterSearchHandoff(
        context: context,
        selected: selected,
        variant: variant,
        trace: trace,
      );

  switch (variant) {
    case ParkingCompletedSearchVariant.minor:
      await showMinorParkingCompletedStatusBottomSheet(
        context: context,
        plate: selected,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      );
      return;
    case ParkingCompletedSearchVariant.double:
      await showDoubleParkingCompletedStatusBottomSheet(
        context: context,
        plate: selected,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      );
      return;
    case ParkingCompletedSearchVariant.triple:
      await showTripleParkingCompletedStatusBottomSheet(
        context: context,
        plate: selected,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      );
      return;
  }
}

Future<bool> _deletePlateAfterSearchHandoff({
  required BuildContext context,
  required PlateModel selected,
  required ParkingCompletedSearchVariant variant,
  required DeveloperOperationTrace trace,
}) async {
  final deleter = context.read<DeletePlate>();
  trace.log(
    'plate_search_delete_dialog_open plate=${selected.plateNumber} type=${selected.type} area=${selected.area} handoff=true',
    progress: .84,
  );

  final confirmed = await showCommonOverlayDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => PlateRemoveDialog(
          onConfirm: () {
            Navigator.of(dialogContext).pop(true);
          },
        ),
      ) ??
      false;

  if (!confirmed) {
    trace.log(
      'plate_search_delete_cancelled plate=${selected.plateNumber} handoff=true',
    );
    return false;
  }

  try {
    final type = selected.typeEnum;
    final performedBy = variant == ParkingCompletedSearchVariant.minor
        ? null
        : context.read<UserState>().name;

    if (type == PlateType.parkingRequests) {
      if (performedBy == null) {
        await deleter.deleteFromParkingRequest(
          selected.plateNumber,
          selected.area,
        );
      } else {
        await deleter.deleteFromParkingRequest(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      }
    } else if (type == PlateType.parkingCompleted) {
      if (performedBy == null) {
        await deleter.deleteFromParkingCompleted(
          selected.plateNumber,
          selected.area,
        );
      } else {
        await deleter.deleteFromParkingCompleted(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      }
    } else if (type == PlateType.departureRequests) {
      if (performedBy == null) {
        await deleter.deleteFromDepartureRequest(
          selected.plateNumber,
          selected.area,
        );
      } else {
        await deleter.deleteFromDepartureRequest(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      }
    } else {
      trace.log(
        'plate_search_delete_blocked plate=${selected.plateNumber} reason=unsupported_type type=${selected.type} handoff=true',
      );
      return false;
    }

    trace.log(
      'plate_search_delete_completed plate=${selected.plateNumber} refresh=false returnTarget=type_page handoff=true',
      progress: .9,
    );
    return true;
  } catch (error, stackTrace) {
    trace.log(
      'plate_search_delete_failed plate=${selected.plateNumber} error=$error handoff=true',
    );
    debugPrint('[PlateSearchSideDock] delete_error=$error\n$stackTrace');
    return false;
  }
}

class ParkingCompletedPlateSearchSideDock extends StatefulWidget {
  const ParkingCompletedPlateSearchSideDock({
    super.key,
    required this.area,
    required this.variant,
    required this.trace,
    this.onSearch,
  });

  final String area;
  final ParkingCompletedSearchVariant variant;
  final DeveloperOperationTrace trace;
  final void Function(String)? onSearch;

  @override
  State<ParkingCompletedPlateSearchSideDock> createState() =>
      _ParkingCompletedPlateSearchSideDockState();
}

class _ParkingCompletedPlateSearchSideDockState
    extends State<ParkingCompletedPlateSearchSideDock> {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false;
  PlateSearchMode _searchMode = PlateSearchMode.plates;
  List<PlateModel> _results = <PlateModel>[];
  List<PlateOutLogSearchResult> _outLogResults =
      <PlateOutLogSearchResult>[];
  int _querySerial = 0;
  String? _openingPlateNumber;
  String _lastRailMetricsSummary = 'unresolved';

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    widget.trace.log(
      'plate_search_content_mounted layout=left_rail_management_content resultPresentation=ops_management_list resultSurface=OpsDockListSurface resultRow=OpsDockSelectableRowSurface resultTransition=OpsDockResultSwitcher keypadPlacement=fixed_bottom keypadVisibility=persistent statusTransition=close_then_open_handoff',
      progress: .12,
    );
  }

  @override
  void dispose() {
    widget.trace.log(
      'plate_search_content_disposed mode=${_searchMode.name} searched=$_hasSearched resultCount=${_searchMode == PlateSearchMode.plates ? _results.length : _outLogResults.length}',
    );
    _controller.dispose();
    super.dispose();
  }

  bool _isValidPlate(String value) =>
      RegExp(r'^\d{4}$').hasMatch(value.trim());

  String get _modeLabel =>
      _searchMode == PlateSearchMode.plates ? '현재 차량' : '출차 로그';

  void _completeSearch({
    required int serial,
    List<PlateModel>? results,
    List<PlateOutLogSearchResult>? outLogResults,
  }) {
    if (!mounted || serial != _querySerial) return;
    setState(() {
      _results = results ?? <PlateModel>[];
      _outLogResults = outLogResults ?? <PlateOutLogSearchResult>[];
      _hasSearched = true;
      _isLoading = false;
    });
    final count = _searchMode == PlateSearchMode.plates
        ? _results.length
        : _outLogResults.length;
    widget.trace.log(
      'plate_search_query_completed serial=$serial mode=${_searchMode.name} resultCount=$count keypadPlacement=fixed_bottom keypadVisibility=persistent resultPresentation=ops_management_list queryLength=${_controller.text.trim().length}',
      progress: .58,
    );
  }

  void _finishLoadingAsSearched(int serial) {
    if (!mounted || serial != _querySerial) return;
    setState(() {
      _isLoading = false;
      _hasSearched = true;
    });
  }

  Future<void> _resetSearch({String source = 'header_reset'}) async {
    if (!mounted || _isLoading || _navigating) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      _querySerial += 1;
      _controller.clear();
      _hasSearched = false;
      _results.clear();
      _outLogResults.clear();
      _navigating = false;
      _isLoading = false;
      _openingPlateNumber = null;
    });
    widget.trace.log(
      'plate_search_reset source=$source mode=${_searchMode.name} keypadPlacement=fixed_bottom keypadVisibility=persistent queryCleared=true',
      progress: .22,
    );
  }

  Future<void> _setSearchMode(PlateSearchMode mode) async {
    if (!mounted || _searchMode == mode || _isLoading || _navigating) return;
    final previous = _searchMode;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      _querySerial += 1;
      _searchMode = mode;
      _hasSearched = false;
      _results.clear();
      _outLogResults.clear();
      _navigating = false;
      _openingPlateNumber = null;
    });
    widget.trace.log(
      'plate_search_mode_changed from=${previous.name} to=${mode.name} queryPreserved=true queryLength=${_controller.text.trim().length} contentAnimation=OpsDockResultSwitcher resultPresentation=ops_management_list',
      progress: .2,
    );
  }

  void _clearResultsForInputEdit() {
    _querySerial += 1;
    _hasSearched = false;
    _results.clear();
    _outLogResults.clear();
    _openingPlateNumber = null;
  }

  Future<void> _appendDigit(String digit) async {
    if (_isLoading || _navigating) return;
    final current = _controller.text;
    if (current.length >= 4) {
      await HapticFeedback.lightImpact();
      widget.trace.log(
        'plate_search_key_ignored key=$digit reason=max_length queryLength=${current.length}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      if (_hasSearched) _clearResultsForInputEdit();
      _controller.text = '$current$digit';
    });
    widget.trace.log(
      'plate_search_digit_entered digit=$digit queryLength=${_controller.text.length} complete=${_controller.text.length == 4} keypadPlacement=fixed_bottom',
    );
  }

  Future<void> _backspace() async {
    if (_isLoading || _navigating) return;
    final current = _controller.text;
    if (current.isEmpty) {
      await HapticFeedback.lightImpact();
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      if (_hasSearched) _clearResultsForInputEdit();
      _controller.text = current.substring(0, current.length - 1);
    });
    widget.trace.log(
      'plate_search_backspace beforeLength=${current.length} afterLength=${_controller.text.length} searchedReset=true keypadPlacement=fixed_bottom',
    );
  }

  Future<void> _clearInputFromLongPress() async {
    if (_isLoading || _navigating || _controller.text.isEmpty) return;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final before = _controller.text.length;
    setState(() {
      if (_hasSearched) _clearResultsForInputEdit();
      _controller.clear();
    });
    widget.trace.log(
      'plate_search_input_cleared source=backspace_long_press beforeLength=$before afterLength=0 searchedReset=true keypadPlacement=fixed_bottom',
    );
  }

  Future<void> _refreshSearchResults({bool userInitiated = true}) async {
    if (!mounted || _isLoading || _navigating) return;

    final query = _controller.text.trim();
    final area = widget.area.trim();
    final mode = _searchMode;

    if (!_isValidPlate(query) || area.isEmpty) {
      widget.trace.log(
        'plate_search_query_blocked mode=${mode.name} queryLength=${query.length} areaAvailable=${area.isNotEmpty} reason=invalid_input',
      );
      await HapticFeedback.lightImpact();
      return;
    }

    final serial = ++_querySerial;
    if (userInitiated) {
      await HapticFeedback.selectionClick();
      if (!mounted) return;
    }
    setState(() => _isLoading = true);
    widget.trace.log(
      'plate_search_query_started serial=$serial mode=${mode.name} query=$query area=$area repository=${mode == PlateSearchMode.plates ? 'fourDigitCommonQuery' : 'searchPlateOutLogsByFourDigit'}',
      progress: .34,
    );

    try {
      final repository = context.read<PlateRepository>();

      if (mode == PlateSearchMode.plateOutLog) {
        final results = await repository.searchPlateOutLogsByFourDigit(
          plateFourDigit: query,
          area: area,
        );

        if (!mounted || serial != _querySerial) return;
        if (_searchMode != mode) {
          setState(() => _isLoading = false);
          widget.trace.log(
            'plate_search_query_ignored serial=$serial reason=mode_changed from=${mode.name} to=${_searchMode.name}',
          );
          return;
        }

        _completeSearch(serial: serial, outLogResults: results);
        widget.onSearch?.call(query);
        return;
      }

      final results = await repository.fourDigitCommonQuery(
        plateFourDigit: query,
        area: area,
      );

      final allowedTypes = <String>{
        PlateType.parkingRequests.firestoreValue,
        PlateType.parkingCompleted.firestoreValue,
        PlateType.departureRequests.firestoreValue,
      };

      final filtered =
          results.where((plate) => allowedTypes.contains(plate.type)).toList();

      if (!mounted || serial != _querySerial) return;
      if (_searchMode != mode) {
        setState(() => _isLoading = false);
        widget.trace.log(
          'plate_search_query_ignored serial=$serial reason=mode_changed from=${mode.name} to=${_searchMode.name}',
        );
        return;
      }

      _completeSearch(serial: serial, results: filtered);
      widget.onSearch?.call(query);
    } catch (error, stackTrace) {
      _finishLoadingAsSearched(serial);
      widget.trace.log(
        'plate_search_query_failed serial=$serial mode=${mode.name} error=$error',
        progress: .58,
      );
      debugPrint('[PlateSearchSideDock] query_error=$error\n$stackTrace');
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '검색 중 오류가 발생했습니다.',
        useCommonUi: true,
      );
    }
  }

  Future<void> _requestStatusHandoff(PlateModel selected) async {
    if (_navigating || _isLoading) {
      widget.trace.log(
        'plate_search_result_ignored plate=${selected.plateNumber} reason=${_navigating ? 'navigation_active' : 'loading'}',
      );
      return;
    }

    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      _navigating = true;
      _openingPlateNumber = selected.plateNumber;
    });
    widget.trace.log(
      'plate_search_result_selected plate=${selected.plateNumber} type=${selected.type} resultPresentation=ops_management_row rowFeedback=selected_indicator statusDockHandoff=true handoffPolicy=close_then_open sourceDock=plate_search targetDock=parking_status sourcePopResolvedBeforeTarget=true overlayStacking=false',
      progress: .68,
    );
    debugPrint(
      '[PlateSearchSideDock] handoff_request plate=${selected.plateNumber} policy=close_then_open overlayStacking=false',
    );
    if (!_reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
    }
    Navigator.of(context).pop(selected);
  }

  Widget _buildPlateResults() {
    switch (widget.variant) {
      case ParkingCompletedSearchVariant.minor:
        return MinorParkingCompletedPlateSearchResults(
          results: _results,
          selectedPlateNumber: _openingPlateNumber,
          onSelect: (plate) => unawaited(_requestStatusHandoff(plate)),
        );
      case ParkingCompletedSearchVariant.double:
        return DoubleParkingCompletedPlateSearchResults(
          results: _results,
          selectedPlateNumber: _openingPlateNumber,
          onSelect: (plate) => unawaited(_requestStatusHandoff(plate)),
        );
      case ParkingCompletedSearchVariant.triple:
        return TripleParkingCompletedPlateSearchResults(
          results: _results,
          selectedPlateNumber: _openingPlateNumber,
          onSelect: (plate) => unawaited(_requestStatusHandoff(plate)),
        );
    }
  }

  Widget _buildResultSection() {
    final text = _controller.text.trim();
    final valid = _isValidPlate(text);

    if (_isLoading) {
      return const _SearchLoadingState();
    }

    if (!_hasSearched) {
      return _SearchReadyState(
        modeLabel: _modeLabel,
        hasInput: text.isNotEmpty,
        valid: valid,
        reduceMotion: _reduceMotion,
      );
    }

    if (!valid) {
      return const _EmptyState(
        icon: Icons.error_outline_rounded,
        title: '유효하지 않은 번호 형식',
        message: '숫자 4자리를 입력해주세요.',
        tone: _EmptyTone.danger,
      );
    }

    if (_searchMode == PlateSearchMode.plateOutLog) {
      if (_outLogResults.isEmpty) {
        return const _EmptyState(
          icon: Icons.search_off_rounded,
          title: '검색 결과 없음',
          message: '저장된 출차 로그 문서를 찾지 못했습니다.',
          tone: _EmptyTone.neutral,
        );
      }
      return PlateOutLogSearchResults(
        results: _outLogResults,
        trace: widget.trace,
      );
    }

    if (_results.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off_rounded,
        title: '검색 결과 없음',
        message: '해당 4자리 번호판을 찾지 못했습니다.',
        tone: _EmptyTone.neutral,
      );
    }

    return _buildPlateResults();
  }

  Future<void> _showDeveloperStatus() async {
    if (!widget.trace.developerMode || !mounted) return;
    widget.trace.log(
      'plate_search_status_dialog_open mode=${_searchMode.name} queryLength=${_controller.text.length} loading=$_isLoading searched=$_hasSearched navigating=$_navigating currentResults=${_results.length} outLogResults=${_outLogResults.length} openingPlate=${_openingPlateNumber ?? '-'} layout=left_rail_management_content resultPresentation=ops_management_list resultSurface=OpsDockListSurface resultRow=OpsDockSelectableRowSurface resultScroll=content_only resultTransition=OpsDockResultSwitcher keypadPlacement=fixed_bottom keypadVisibility=persistent handoffPolicy=close_then_open sourceDock=plate_search targetDock=parking_status sourcePopResolvedBeforeTarget=true overlayStacking=false railDesign=common_operations railMetrics=$_lastRailMetricsSummary debugPrint=clipboard_copy_supported',
    );
    await widget.trace.showStatusDialog(context);
  }

  void _closeDock() {
    widget.trace.log(
      'plate_search_close_button mode=${_searchMode.name} queryLength=${_controller.text.length} searched=$_hasSearched navigating=$_navigating',
      progress: .9,
    );
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = _reduceMotion;
    final query = _controller.text.trim();
    final subtitle = query.isEmpty ? _modeLabel : '$_modeLabel · $query';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 58,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.accent.withOpacity(.28)),
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  color: tokens.onAccentContainer,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '번호판 검색',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      child: Text(
                        subtitle,
                        key: ValueKey<String>(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trace.developerMode)
                Semantics(
                  button: true,
                  label: '번호판 검색 개발자 상태 보기',
                  child: IconButton(
                    onPressed: _showDeveloperStatus,
                    icon: Icon(
                      Icons.bug_report_rounded,
                      color: tokens.info,
                      size: 20,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: _hasSearched
                    ? Semantics(
                        key: const ValueKey<String>('reset'),
                        button: true,
                        label: '번호판 다시 검색',
                        child: IconButton(
                          onPressed: _isLoading || _navigating
                              ? null
                              : () => unawaited(
                                    _resetSearch(source: 'header_reset'),
                                  ),
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: tokens.accent,
                            size: 20,
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey<String>('reset_empty'),
                        width: 0,
                        height: 0,
                      ),
              ),
              Semantics(
                button: true,
                label: '번호판 검색 닫기',
                child: IconButton(
                  onPressed: _closeDock,
                  icon: Icon(
                    Icons.close_rounded,
                    color: tokens.iconPrimary,
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.maybeOf(context);
              final dockHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : media?.size.height ?? 720.0;
              final dockWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : media?.size.width ?? 360.0;
              final textScale = media?.textScaler.scale(1.0) ?? 1.0;
              final railMetrics = CommonSideRailMetrics.resolve(
                dockHeight: dockHeight,
                textScale: textScale,
              );
              final effectiveRailWidth =
                  railMetrics.effectiveRailWidth(dockWidth);
              final effectiveRailGap = railMetrics.effectiveRailGap(dockWidth);
              final railSummary =
                  'variant=${railMetrics.variantName},width=${effectiveRailWidth.toStringAsFixed(1)},gap=${effectiveRailGap.toStringAsFixed(1)},button=${railMetrics.minimumButtonExtent.toStringAsFixed(1)},outerX=${railMetrics.outerHorizontal.toStringAsFixed(1)},outerY=${railMetrics.outerVertical.toStringAsFixed(1)},insetX=${railMetrics.actionInsetHorizontal.toStringAsFixed(1)},insetY=${railMetrics.actionInsetVertical.toStringAsFixed(1)}';
              if (_lastRailMetricsSummary != railSummary) {
                _lastRailMetricsSummary = railSummary;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.trace.log(
                    'plate_search_rail_layout railDesign=common_operations railMetricsSource=CommonSideRailMetrics $railSummary alignment=equal_fill_or_scroll_fallback title=번호_검색',
                  );
                });
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: effectiveRailWidth,
                    child: CommonSideRailSurface(
                      title: '번호 검색',
                      metrics: railMetrics,
                      child: _PlateSearchRail(
                        value: _searchMode,
                        metrics: railMetrics,
                        enabled: !_isLoading && !_navigating,
                        onChanged: (mode) => unawaited(_setSearchMode(mode)),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: effectiveRailGap,
                  ),
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: tokens.canvas,
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.card),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: _PlateSearchContent(
                        mode: _searchMode,
                        controller: _controller,
                        hasSearched: _hasSearched,
                        isLoading: _isLoading,
                        navigating: _navigating,
                        reduceMotion: reduceMotion,
                        isValidPlate: _isValidPlate,
                        resultSection: _buildResultSection(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        OpsDockContextFooter(
          children: [
            Expanded(
              child: _SearchKeypadReveal(
                reduceMotion: reduceMotion,
                child: _CompactSearchKeypad(
                  controller: _controller,
                  isLoading: _isLoading,
                  navigating: _navigating,
                  isValidPlate: _isValidPlate,
                  reduceMotion: reduceMotion,
                  onDigit: _appendDigit,
                  onBackspace: _backspace,
                  onClear: _clearInputFromLongPress,
                  onSearch: () => _refreshSearchResults(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlateSearchRail extends StatelessWidget {
  const _PlateSearchRail({
    required this.value,
    required this.metrics,
    required this.enabled,
    required this.onChanged,
  });

  final PlateSearchMode value;
  final CommonSideRailMetrics metrics;
  final bool enabled;
  final ValueChanged<PlateSearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final items = <({
      PlateSearchMode mode,
      String visualLabel,
      String semanticsLabel,
      IconData icon,
    })>[
      (
        mode: PlateSearchMode.plates,
        visualLabel: '현재',
        semanticsLabel: '현재 차량 검색',
        icon: Icons.directions_car_rounded,
      ),
      (
        mode: PlateSearchMode.plateOutLog,
        visualLabel: '출차',
        semanticsLabel: '출차 로그 검색',
        icon: Icons.history_rounded,
      ),
    ];

    Widget button(
      ({
        PlateSearchMode mode,
        String visualLabel,
        String semanticsLabel,
        IconData icon,
      }) item, {
      required double extent,
    }) {
      return CommonSideRailActionButton(
        key: ValueKey<PlateSearchMode>(item.mode),
        semanticLabel: item.semanticsLabel,
        visualLabel: item.visualLabel,
        icon: item.icon,
        selected: value == item.mode,
        enabled: enabled,
        disabledReason: enabled ? '' : '검색 작업 처리 중',
        compact: metrics.compact,
        extent: extent,
        onTap: () => onChanged(item.mode),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 720.0;
        final actionCount = items.length;
        final availableListHeight = math.max(0.0, railHeight);
        final equalSlotExtent = availableListHeight / actionCount;
        final minimumSlotExtent =
            metrics.minimumButtonExtent + metrics.actionInsetVertical * 2;
        final scrollable = equalSlotExtent + .5 < minimumSlotExtent;
        final buttonExtent = scrollable
            ? metrics.minimumButtonExtent
            : math.max(
                0.0,
                equalSlotExtent - metrics.actionInsetVertical * 2,
              );
        final actionArea = scrollable
            ? SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: button(
                          item,
                          extent: metrics.minimumButtonExtent,
                        ),
                      ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: button(item, extent: buttonExtent),
                      ),
                    ),
                ],
              );

        return AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-.05, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(
              '${metrics.variantName}|$scrollable|${value.name}|$enabled',
            ),
            child: actionArea,
          ),
        );
      },
    );
  }
}

class _PlateSearchContent extends StatelessWidget {
  const _PlateSearchContent({
    required this.mode,
    required this.controller,
    required this.hasSearched,
    required this.isLoading,
    required this.navigating,
    required this.reduceMotion,
    required this.isValidPlate,
    required this.resultSection,
  });

  final PlateSearchMode mode;
  final TextEditingController controller;
  final bool hasSearched;
  final bool isLoading;
  final bool navigating;
  final bool reduceMotion;
  final bool Function(String) isValidPlate;
  final Widget resultSection;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final modeLabel = mode == PlateSearchMode.plates ? '현재 차량' : '출차 로그';

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.component,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.035, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey<String>('mode_intro_${mode.name}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeLabel,
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode == PlateSearchMode.plates
                          ? '현재 작업 지역의 차량을 4자리 번호로 검색합니다.'
                          : '저장된 출차 기록을 4자리 번호로 검색합니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PlateNumberDisplay(
                controller: controller,
                isValidPlate: isValidPlate,
                reduceMotion: reduceMotion,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: OpsDockResultSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      '${mode.name}|$hasSearched|$isLoading|${controller.text}|${resultSection.runtimeType}',
                    ),
                    child: resultSection,
                  ),
                ),
              ),
            ],
          ),
        ),
        IgnorePointer(
          ignoring: !navigating,
          child: AnimatedOpacity(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            opacity: navigating ? 1 : 0,
            child: ColoredBox(
              color: tokens.scrim.withOpacity(.08),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchKeypadReveal extends StatelessWidget {
  const _SearchKeypadReveal({
    required this.reduceMotion,
    required this.child,
  });

  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: Transform.scale(
              alignment: Alignment.topCenter,
              scale: .985 + (.015 * value),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _PlateNumberDisplay extends StatelessWidget {
  const _PlateNumberDisplay({
    required this.controller,
    required this.isValidPlate,
    required this.reduceMotion,
  });

  final TextEditingController controller;
  final bool Function(String) isValidPlate;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final valid = isValidPlate(text);
        final tone = text.isEmpty
            ? tokens.textSecondary
            : valid
                ? tokens.success
                : tokens.danger;
        final border = text.isEmpty
            ? tokens.borderSubtle
            : valid
                ? tokens.success.withOpacity(.55)
                : tokens.danger.withOpacity(.55);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: List<Widget>.generate(4, (index) {
                final char = index < text.length ? text[index] : '';
                final filled = char.isNotEmpty;
                return Expanded(
                  child: AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    margin: EdgeInsets.only(right: index == 3 ? 0 : 5),
                    height: 48,
                    decoration: BoxDecoration(
                      color: filled
                          ? tokens.surfaceRaised
                          : tokens.surfaceOverlay.withOpacity(.7),
                      borderRadius:
                          BorderRadius.circular(CommonUiShapes.control),
                      border: Border.all(color: border, width: 1.1),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.press,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .94, end: 1)
                                .animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        char.isEmpty ? '•' : char,
                        key: ValueKey<String>('cell_${index}_$char'),
                        style: textTheme.titleLarge?.copyWith(
                          color: char.isEmpty
                              ? tokens.textDisabled.withOpacity(.65)
                              : tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 7),
            AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Row(
                key: ValueKey<String>('validation_${text.length}_$valid'),
                children: [
                  Icon(
                    text.isEmpty
                        ? Icons.dialpad_rounded
                        : valid
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                    size: 15,
                    color: tone,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      text.isEmpty
                          ? '숫자 4자리를 입력해주세요.'
                          : valid
                              ? '검색할 수 있습니다.'
                              : '숫자 4자리를 입력해주세요.',
                      style: textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CompactSearchKeypad extends StatelessWidget {
  const _CompactSearchKeypad({
    required this.controller,
    required this.isLoading,
    required this.navigating,
    required this.isValidPlate,
    required this.reduceMotion,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isLoading;
  final bool navigating;
  final bool Function(String) isValidPlate;
  final bool reduceMotion;
  final Future<void> Function(String) onDigit;
  final Future<void> Function() onBackspace;
  final Future<void> Function() onClear;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final valid = isValidPlate(value.text);
        final enabled = !isLoading && !navigating;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(<Widget>[
              _SearchKey(
                label: '1',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('1'),
              ),
              _SearchKey(
                label: '2',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('2'),
              ),
              _SearchKey(
                label: '3',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('3'),
              ),
            ]),
            const SizedBox(height: 6),
            _row(<Widget>[
              _SearchKey(
                label: '4',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('4'),
              ),
              _SearchKey(
                label: '5',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('5'),
              ),
              _SearchKey(
                label: '6',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('6'),
              ),
            ]),
            const SizedBox(height: 6),
            _row(<Widget>[
              _SearchKey(
                label: '7',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('7'),
              ),
              _SearchKey(
                label: '8',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('8'),
              ),
              _SearchKey(
                label: '9',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('9'),
              ),
            ]),
            const SizedBox(height: 6),
            _row(<Widget>[
              _SearchKey(
                semanticsLabel: '한 자리 삭제, 길게 눌러 전체 삭제',
                icon: Icons.backspace_outlined,
                reduceMotion: reduceMotion,
                enabled: enabled,
                tone: _SearchKeyTone.secondary,
                onTap: onBackspace,
                onLongPress: onClear,
              ),
              _SearchKey(
                label: '0',
                reduceMotion: reduceMotion,
                enabled: enabled,
                onTap: () => onDigit('0'),
              ),
              _SearchKey(
                semanticsLabel: '번호판 검색',
                icon: Icons.search_rounded,
                loading: isLoading,
                reduceMotion: reduceMotion,
                enabled: enabled && valid,
                tone: _SearchKeyTone.primary,
                onTap: onSearch,
              ),
            ]),
          ],
        );
      },
    );
  }

  Widget _row(List<Widget> children) {
    return Row(
      children: [
        for (int index = 0; index < children.length; index++) ...[
          Expanded(child: children[index]),
          if (index != children.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

enum _SearchKeyTone { number, secondary, primary }

class _SearchKey extends StatefulWidget {
  const _SearchKey({
    this.label,
    this.semanticsLabel,
    this.icon,
    this.loading = false,
    required this.reduceMotion,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
    this.tone = _SearchKeyTone.number,
  });

  final String? label;
  final String? semanticsLabel;
  final IconData? icon;
  final bool loading;
  final bool reduceMotion;
  final bool enabled;
  final Future<void> Function() onTap;
  final Future<void> Function()? onLongPress;
  final _SearchKeyTone tone;

  @override
  State<_SearchKey> createState() => _SearchKeyState();
}

class _SearchKeyState extends State<_SearchKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.enabled;
    final primary = widget.tone == _SearchKeyTone.primary;
    final secondary = widget.tone == _SearchKeyTone.secondary;
    final background = !enabled
        ? tokens.surfaceDisabled.withOpacity(.72)
        : primary
            ? (_pressed ? tokens.accentPressed : tokens.accent)
            : secondary
                ? tokens.surfaceOverlay.withOpacity(_pressed ? .95 : .78)
                : tokens.surfaceRaised.withOpacity(_pressed ? .88 : .72);
    final foreground = !enabled
        ? tokens.textDisabled
        : primary
            ? tokens.onAccent
            : secondary
                ? tokens.iconSecondary
                : tokens.textPrimary;
    final border = primary
        ? tokens.accent.withOpacity(.72)
        : secondary
            ? tokens.borderStrong.withOpacity(.42)
            : tokens.borderSubtle;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label ?? '숫자 키',
      child: AnimatedScale(
        duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .95 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            onTap: enabled ? () => unawaited(widget.onTap()) : null,
            onLongPress: enabled && widget.onLongPress != null
                ? () => unawaited(widget.onLongPress!())
                : null,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : CommonUiMotion.press,
              curve: CommonUiMotion.standard,
              height: 48,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                border: Border.all(color: border),
              ),
              alignment: Alignment.center,
              child: widget.loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    )
                  : widget.icon != null
                      ? Icon(widget.icon, color: foreground, size: 19)
                      : Text(
                          widget.label ?? '',
                          style: textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.infoContainer.withOpacity(.58),
        borderRadius: BorderRadius.circular(CommonUiShapes.button),
        border: Border.all(color: tokens.info.withOpacity(.28)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.info),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '번호판 정보를 검색하고 있습니다.',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onInfoContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchReadyState extends StatelessWidget {
  const _SearchReadyState({
    required this.modeLabel,
    required this.hasInput,
    required this.valid,
    required this.reduceMotion,
  });

  final String modeLabel;
  final bool hasInput;
  final bool valid;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final tone = valid ? tokens.success : tokens.info;
    final container = valid ? tokens.successContainer : tokens.infoContainer;
    final foreground =
        valid ? tokens.onSuccessContainer : tokens.onInfoContainer;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: container.withOpacity(.56),
        borderRadius: BorderRadius.circular(CommonUiShapes.button),
        border: Border.all(color: tone.withOpacity(.26)),
      ),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valid
                  ? '$modeLabel 검색 준비가 완료되었습니다.'
                  : hasInput
                      ? '4자리 숫자를 완성해주세요.'
                      : '$modeLabel 검색 번호를 입력해주세요.',
              style: textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EmptyTone { neutral, danger }

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final _EmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final danger = tone == _EmptyTone.danger;
    final foreground = danger ? tokens.danger : tokens.textSecondary;
    final background =
        danger ? tokens.dangerContainer.withOpacity(.62) : tokens.surfaceOverlay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.button),
        border: Border.all(
          color: danger
              ? tokens.danger.withOpacity(.28)
              : tokens.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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
