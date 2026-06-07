import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/data/repositories/firestore_plate_repository.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../location/applications/location_state.dart';
import '../../../location/domain/models/location_model.dart';
import '../../applications/tablet_pad_mode_state.dart';
import '../../domain/models/two_d/tablet_grid_2d_preview.dart'
    show
        ParkingGridOverlay,
        ParkingSlotStatus,
        TabletGrid2dPreview,
        parkingOverlayCanonicalChildKey;
import '../sheets/widgets/keypad/tablet_animated_keypad.dart';
import '../widgets/tablet_plate_number_display_section.dart';
import '../widgets/tablet_plate_search_header_section.dart';
import '../widgets/tablet_plate_search_result_section.dart';

enum _UnifiedDialogCloseReason {
  reset,
  confirmed,
  cancelled,
}

enum _UnifiedDialogScreen {
  list,
  confirm,
}

class RightPaneSearchPanel extends StatefulWidget {
  final String area;

  const RightPaneSearchPanel({
    super.key,
    required this.area,
  });

  @override
  State<RightPaneSearchPanel> createState() => _RightPaneSearchPanelState();
}

class _RightPaneSearchPanelState extends State<RightPaneSearchPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _dialogOpen = false;

  late final AnimationController _keypadController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _keypadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _keypadController, curve: Curves.easeOut),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _keypadController,
      curve: Curves.easeIn,
    );
    _keypadController.forward();
  }

  @override
  void didUpdateWidget(covariant RightPaneSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) {
      _resetToInitial();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool _isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  String _formatDateTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }

  List<String> _splitLocationSegments(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const <String>[];
    return value
        .split(' - ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  _ParkingLocationDetails _parseParkingLocation(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '미지정') {
      return const _ParkingLocationDetails.empty();
    }

    final segments = _splitLocationSegments(trimmed);
    if (segments.isEmpty) {
      return _ParkingLocationDetails(
        full: trimmed,
        parent: trimmed,
        child: '',
        slot: '',
      );
    }

    final parent = segments[0];
    final child = segments.length >= 2 ? segments[1] : '';
    final slot = segments.length >= 3 ? segments.sublist(2).join(' - ') : '';
    final full = <String>[parent, child, slot]
        .where((e) => e.trim().isNotEmpty)
        .join(' - ');

    return _ParkingLocationDetails(
      full: full.isEmpty ? trimmed : full,
      parent: parent,
      child: child,
      slot: slot,
    );
  }

  Future<void> _showDepartureRequestedSuccessDialog(
    BuildContext dialogCtx,
    PlateModel plate,
  ) async {
    final details = _parseParkingLocation(plate.location);

    await showDialog<void>(
      context: dialogCtx,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) {
        return _AutoCloseDepartureRequestDialog(
          plate: plate,
          details: details,
        );
      },
    );
  }

  void _resetToInitial() {
    setState(() {
      _controller.clear();
      _isLoading = false;
    });
    _keypadController.forward(from: 0);
  }

  void _onKeypadComplete() {
    final input = _controller.text;
    if (_isValidPlate(input)) {
      _refreshSearchResults();
    }
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted || _isLoading || _dialogOpen) return;

    setState(() => _isLoading = true);

    try {
      final repository = FirestorePlateRepository();
      final input = _controller.text;

      final results = await repository.fourDigitForTabletQuery(
        plateFourDigit: input,
        area: widget.area,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      await _showUnifiedSearchDialog(results);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('검색 중 오류가 발생했습니다: $e');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.plates.fourDigitForTabletQuery',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'plates',
          'area': widget.area,
          'plateFourDigit': _controller.text,
          'types': <String>[
            PlateType.parkingCompleted.firestoreValue,
            PlateType.departureCompleted.firestoreValue,
          ],
          'widget': 'RightPaneSearchPanel',
        },
      );
    }
  }

  Future<void> _showUnifiedSearchDialog(List<PlateModel> results) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;

    final closeReason = await showDialog<_UnifiedDialogCloseReason>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final text = Theme.of(dialogCtx).textTheme;
        final mq = MediaQuery.of(dialogCtx);
        final size = mq.size;

        final bool isPhone = size.shortestSide < 600;

        final double maxDialogWidth =
            (size.width - 32).clamp(0.0, 1280.0).toDouble();
        final double maxDialogHeight =
            (size.height * 0.92).clamp(0.0, size.height);

        final bool useTwoPane = !isPhone && maxDialogWidth >= 980;

        final hasSingleResult = results.length == 1;
        PlateModel? selected = hasSingleResult ? results.first : null;
        String? selectedId = hasSingleResult ? results.first.id : null;
        bool busy = false;
        _UnifiedDialogScreen screen = isPhone && hasSingleResult
            ? _UnifiedDialogScreen.confirm
            : _UnifiedDialogScreen.list;

        void popReset() {
          if (busy) return;
          Navigator.of(dialogCtx).pop(_UnifiedDialogCloseReason.reset);
        }

        void popCancelled() {
          if (busy) return;
          Navigator.of(dialogCtx).pop(_UnifiedDialogCloseReason.cancelled);
        }

        Future<void> confirmDepartureRequested(StateSetter setStateSB) async {
          final plate = selected;
          if (plate == null || busy) return;

          setStateSB(() => busy = true);

          try {
            final movementPlate = dialogCtx.read<MovementPlate>();
            await movementPlate.setDepartureRequested(
              plate.plateNumber,
              plate.area,
              plate.location,
              forceViewSync: true,
            );

            if (!dialogCtx.mounted) return;
            await _showDepartureRequestedSuccessDialog(dialogCtx, plate);

            if (!dialogCtx.mounted) return;
            Navigator.of(dialogCtx).pop(_UnifiedDialogCloseReason.confirmed);
          } catch (e, st) {
            if (!dialogCtx.mounted) return;
            debugPrint('출차 요청 처리 중 오류가 발생했습니다: $e');
            await DevFirebaseDebugDialog.show(
              context: dialogCtx,
              operation: 'tablet.movement.setDepartureRequested',
              error: e,
              stackTrace: st,
              details: <String, Object?>{
                'collection': 'plates',
                'area': plate.area,
                'location': plate.location,
                'plateId': plate.id,
                'plateFourDigit': plate.plateFourDigit,
                'forceViewSync': true,
                'widget': 'RightPaneSearchPanel.confirmDepartureRequested',
              },
            );
            setStateSB(() => busy = false);
          }
        }

        Widget buildResultsList(StateSetter setStateSB) {
          final render = results
              .map((p) => p.copyWith(
                    isSelected: selectedId != null && p.id == selectedId,
                  ))
              .toList();

          if (render.isEmpty) {
            return _BigInlineEmpty(
              text: '검색 결과가 없습니다.',
              compact: isPhone,
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline.withOpacity(.14)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: TabletPlateSearchResultSection(
                results: render,
                compact: isPhone,
                onSelect: (p) {
                  if (busy) return;
                  setStateSB(() {
                    selected = p;
                    selectedId = p.id;

                    if (isPhone) {
                      screen = _UnifiedDialogScreen.confirm;
                    }
                  });
                },
              ),
            ),
          );
        }

        Widget buildConfirmPanel(StateSetter setStateSB) {
          if (selected == null) {
            return Container(
              decoration: BoxDecoration(
                color: _tintOnSurface(
                  cs,
                  opacity: cs.brightness == Brightness.dark ? 0.10 : 0.05,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outline.withOpacity(.14)),
              ),
              padding: const EdgeInsets.all(22),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined, size: 54, color: cs.primary),
                    const SizedBox(height: 12),
                    Text(
                      '왼쪽에서 번호판을 선택하세요',
                      style: (text.titleLarge ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '선택 후, 같은 창에서 바로 “출차 요청”으로 전환할 수 있습니다.',
                      style: (text.bodyLarge ?? const TextStyle()).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final plate = selected!;

          final typeLabel = plate.typeEnum?.label ?? plate.type;

          final metaLine =
              '${_formatDateTime(plate.requestTime)} · ${plate.location.isEmpty ? '위치 미지정' : plate.location}';
          final areaLine = plate.area.isEmpty ? '-' : plate.area;

          final plateBoxBg = _tintOnSurface(
            cs,
            opacity: cs.brightness == Brightness.dark ? 0.14 : 0.08,
          );
          final plateBorder = cs.primary.withOpacity(
            cs.brightness == Brightness.dark ? 0.30 : 0.22,
          );

          final double plateFontSize = isPhone ? 36 : 44;
          final double buttonHeight = isPhone ? 52 : 56;

          Widget content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: plateBoxBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: plateBorder),
                  ),
                  child: Text(
                    plate.plateNumber,
                    style: (text.displaySmall ?? const TextStyle()).copyWith(
                      fontSize: plateFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      height: 1.0,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _tintOnSurface(
                    cs,
                    opacity: cs.brightness == Brightness.dark ? 0.10 : 0.05,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outline.withOpacity(.14)),
                ),
                child: DefaultTextStyle(
                  style: (text.bodyLarge ?? const TextStyle()).copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('현재 상태: $typeLabel'),
                      const SizedBox(height: 6),
                      Text('구역: $areaLine'),
                      const SizedBox(height: 6),
                      Text(metaLine),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '선택한 차량을 “출차 요청”으로 변경하시겠습니까?',
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                  height: 1.15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('아니요'),
                      onPressed: busy ? null : popCancelled,
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(double.infinity, buttonHeight),
                        foregroundColor: cs.onSurface,
                        side: BorderSide(color: cs.outline.withOpacity(.35)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle:
                            (text.titleMedium ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.onPrimary,
                                ),
                              ),
                            )
                          : const Icon(Icons.exit_to_app),
                      label: Text(busy ? '처리 중...' : '네, 출차 요청'),
                      onPressed: busy
                          ? null
                          : () => confirmDepartureRequested(setStateSB),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, buttonHeight),
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        textStyle:
                            (text.titleMedium ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (isPhone) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outline.withOpacity(.14)),
              ),
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(child: content),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline.withOpacity(.14)),
            ),
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(child: content),
          );
        }

        final inputLine =
            '입력 번호: ${_controller.text}   /   구역: ${widget.area.isEmpty ? "-" : widget.area}';
        final countLabel = results.isEmpty ? '0건' : '${results.length}건';

        return StatefulBuilder(
          builder: (contextSB, setStateSB) {
            if (isPhone) {
              return Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: cs.surface,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
                child: SizedBox.expand(
                  child: Material(
                    color: cs.surface,
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                            child: Row(
                              children: [
                                if (screen == _UnifiedDialogScreen.confirm)
                                  IconButton(
                                    tooltip: '목록으로',
                                    icon: const Icon(Icons.arrow_back),
                                    onPressed: busy
                                        ? null
                                        : () => setStateSB(
                                              () => screen =
                                                  _UnifiedDialogScreen.list,
                                            ),
                                  )
                                else
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _tintOnSurface(
                                        cs,
                                        opacity:
                                            cs.brightness == Brightness.dark
                                                ? 0.18
                                                : 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: cs.outline.withOpacity(.10),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.search,
                                      color: cs.primary,
                                      size: 22,
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    screen == _UnifiedDialogScreen.list
                                        ? '검색 결과 · $countLabel'
                                        : '출차 요청 확인',
                                    style:
                                        (text.titleLarge ?? const TextStyle())
                                            .copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '초기화',
                                  icon: const Icon(Icons.restart_alt),
                                  onPressed: busy ? null : popReset,
                                ),
                              ],
                            ),
                          ),
                          if (screen == _UnifiedDialogScreen.list)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _tintOnSurface(
                                    cs,
                                    opacity: cs.brightness == Brightness.dark
                                        ? 0.12
                                        : 0.06,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.outline.withOpacity(.14),
                                  ),
                                ),
                                child: Text(
                                  inputLine,
                                  style: (text.bodyLarge ?? const TextStyle())
                                      .copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: screen == _UnifiedDialogScreen.list
                                  ? buildResultsList(setStateSB)
                                  : buildConfirmPanel(setStateSB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxDialogWidth,
                  maxHeight: maxDialogHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _tintOnSurface(
                                cs,
                                opacity: cs.brightness == Brightness.dark
                                    ? 0.18
                                    : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cs.outline.withOpacity(.10),
                              ),
                            ),
                            child: Icon(
                              Icons.search,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '검색 결과 · $countLabel',
                              style: (text.titleLarge ?? const TextStyle())
                                  .copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '초기화',
                            icon: const Icon(Icons.restart_alt),
                            onPressed: busy ? null : popReset,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _tintOnSurface(
                            cs,
                            opacity:
                                cs.brightness == Brightness.dark ? 0.12 : 0.06,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withOpacity(.14),
                          ),
                        ),
                        child: Text(
                          inputLine,
                          style: (text.bodyLarge ?? const TextStyle()).copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: useTwoPane
                            ? Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: buildResultsList(setStateSB),
                                  ),
                                  const SizedBox(width: 12),
                                  VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: cs.outlineVariant.withOpacity(.55),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 5,
                                    child: buildConfirmPanel(setStateSB),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: buildResultsList(setStateSB)),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: buildConfirmPanel(setStateSB),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : popReset,
                          child: Text(
                            '초기화',
                            style: (text.titleMedium ?? const TextStyle())
                                .copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    _dialogOpen = false;
    if (!mounted) return;

    if (closeReason == null ||
        closeReason == _UnifiedDialogCloseReason.reset ||
        closeReason == _UnifiedDialogCloseReason.cancelled ||
        closeReason == _UnifiedDialogCloseReason.confirmed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resetToInitial();
      });
    }
  }

  Widget _panelCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildHeaderCard({required EdgeInsets padding}) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: _panelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabletPlateSearchHeaderSection(),
            const SizedBox(height: 16),
            TabletPlateNumberDisplaySection(
              controller: _controller,
              isValidPlate: _isValidPlate,
            ),
            const SizedBox(height: 16),
            _buildSearchProgressBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchProgressBar(ColorScheme cs) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _isLoading
          ? ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 3,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                backgroundColor: cs.outlineVariant.withOpacity(.35),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  int _tabletTopFlexForHeight(double maxHeight) {
    if (maxHeight < 760) return 6;
    return 5;
  }

  int _tabletBottomFlexForHeight(double maxHeight) {
    if (maxHeight < 760) return 7;
    return 7;
  }

  Widget _buildTabletSearchCard({
    required ColorScheme cs,
    required BoxConstraints constraints,
  }) {
    final edgePadding = constraints.maxHeight < 760 ? 18.0 : 24.0;
    final titleGap = constraints.maxHeight < 260 ? 12.0 : 16.0;
    final bottomGap = constraints.maxHeight < 260 ? 10.0 : 14.0;

    return Padding(
      padding: EdgeInsets.all(edgePadding),
      child: _panelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabletPlateSearchHeaderSection(),
            SizedBox(height: titleGap),
            Expanded(
              child: SizedBox.expand(
                child: TabletPlateNumberDisplaySection(
                  controller: _controller,
                  isValidPlate: _isValidPlate,
                ),
              ),
            ),
            SizedBox(height: bottomGap),
            _buildSearchProgressBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _keypadWrapper({
    required Widget child,
    required bool fullHeight,
    required bool useTopDivider,
  }) {
    final cs = Theme.of(context).colorScheme;

    if (fullHeight) {
      return Container(
        color: cs.surface,
        child: child,
      );
    }

    final bg = _tintOnSurface(
      cs,
      opacity: cs.brightness == Brightness.dark ? 0.08 : 0.03,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: useTopDivider
            ? Border(top: BorderSide(color: cs.outline.withOpacity(.10)))
            : null,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmallPad =
        context.select<TabletPadModeState, bool>((s) => s.isSmall);
    final padMode = context.select<TabletPadModeState, PadMode>((s) => s.mode);
    final isMobile = padMode == PadMode.mobile;

    final cs = Theme.of(context).colorScheme;

    if (isMobile) {
      return Material(
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeaderCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: _keypadWrapper(
                    fullHeight: true,
                    useTopDivider: false,
                    child: TabletAnimatedKeypad(
                      slideAnimation: _slideAnimation,
                      fadeAnimation: _fadeAnimation,
                      controller: _controller,
                      maxLength: 4,
                      enableDigitModeSwitch: false,
                      onComplete: _onKeypadComplete,
                      onReset: _resetToInitial,
                      fullHeight: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isSmallPad) {
              return Column(
                children: [
                  Expanded(
                    child: SafeArea(
                      top: false,
                      bottom: true,
                      child: _keypadWrapper(
                        fullHeight: true,
                        useTopDivider: false,
                        child: TabletAnimatedKeypad(
                          slideAnimation: _slideAnimation,
                          fadeAnimation: _fadeAnimation,
                          controller: _controller,
                          maxLength: 4,
                          enableDigitModeSwitch: false,
                          onComplete: _onKeypadComplete,
                          onReset: _resetToInitial,
                          fullHeight: true,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final topFlex = _tabletTopFlexForHeight(constraints.maxHeight);
            final bottomFlex =
                _tabletBottomFlexForHeight(constraints.maxHeight);

            return Column(
              children: [
                Expanded(
                  flex: topFlex,
                  child: _buildTabletSearchCard(
                    cs: cs,
                    constraints: constraints,
                  ),
                ),
                Expanded(
                  flex: bottomFlex,
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: _keypadWrapper(
                      fullHeight: false,
                      useTopDivider: true,
                      child: TabletAnimatedKeypad(
                        slideAnimation: _slideAnimation,
                        fadeAnimation: _fadeAnimation,
                        controller: _controller,
                        maxLength: 4,
                        enableDigitModeSwitch: false,
                        onComplete: _onKeypadComplete,
                        onReset: _resetToInitial,
                        fullHeight: true,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AutoCloseDepartureRequestDialog extends StatefulWidget {
  final PlateModel plate;
  final _ParkingLocationDetails details;

  const _AutoCloseDepartureRequestDialog({
    required this.plate,
    required this.details,
  });

  @override
  State<_AutoCloseDepartureRequestDialog> createState() =>
      _AutoCloseDepartureRequestDialogState();
}

class _AutoCloseDepartureRequestDialogState
    extends State<_AutoCloseDepartureRequestDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _closeDialog();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _closeDialog() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final isPhone = mq.size.shortestSide < 600;

    final dialogWidth =
        ((isPhone ? mq.size.width - 24 : 860.0).clamp(320.0, 860.0)).toDouble();
    final dialogHeight =
        ((isPhone ? mq.size.height * 0.66 : 640.0).clamp(420.0, 700.0))
            .toDouble();

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isPhone ? 12 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outline.withOpacity(.12)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _DepartureRequestFocusedGrid(
                      area: widget.plate.area,
                      details: widget.details,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '현재 고객님의 차량 위치를 표시해드립니다.\n차량은 사전에 안내받은 위치에 준비될 예정입니다.',
                textAlign: TextAlign.center,
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: _progressController.value,
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          backgroundColor: cs.outlineVariant.withOpacity(.28),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.center,
                child: FilledButton.icon(
                  onPressed: _closeDialog,
                  icon: const Icon(Icons.close),
                  label: const Text('닫기'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: (text.titleMedium ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _ParkingLocationDetails {
  final String full;
  final String parent;
  final String child;
  final String slot;

  const _ParkingLocationDetails({
    required this.full,
    required this.parent,
    required this.child,
    required this.slot,
  });

  const _ParkingLocationDetails.empty()
      : full = '미지정',
        parent = '',
        child = '',
        slot = '';

  String get fullDisplay => full.trim().isEmpty ? '미지정' : full.trim();
}

class _DepartureRequestFocusedGrid extends StatelessWidget {
  final String area;
  final _ParkingLocationDetails details;

  const _DepartureRequestFocusedGrid({
    required this.area,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (details.parent.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '위치 정보가 없어 2D 그리드를 표시할 수 없습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      );
    }

    final liveLocations = List<LocationModel>.of(
      context.watch<LocationState>().locations,
    );

    final focusedLocations = _resolveFocusedLocations(liveLocations);
    if (focusedLocations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '주차 구역 2D 그리드를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TabletGrid2dPreview(
          locations: focusedLocations,
          overlay: _buildOverlay(),
        ),
      ),
    );
  }

  List<LocationModel> _resolveFocusedLocations(List<LocationModel> all) {
    final resolvedArea = area.trim();
    final parentKey = _dialogNameKey(details.parent);
    if (parentKey.isEmpty) return const <LocationModel>[];

    LocationModel? parentLocation;
    for (final location in all) {
      if (!_matchesAreaLooseForDialog(resolvedArea, location.area)) continue;
      if (!_isCompositeParentTypeForDialog(location.type)) continue;
      if (_dialogNameKey(location.locationName) != parentKey) continue;
      parentLocation = location;
      break;
    }

    if (parentLocation == null) return const <LocationModel>[];

    final aliases = _parentAliasesForDialog(parentLocation);
    final children = <LocationModel>[];

    for (final location in all) {
      if (!_matchesAreaLooseForDialog(resolvedArea, location.area)) continue;
      if (!_isCompositeChildTypeForDialog(location.type)) continue;
      final parentRefKey = _dialogNameKey(location.parent ?? '');
      if (parentRefKey.isEmpty || !aliases.contains(parentRefKey)) continue;
      children.add(location);
    }

    children.sort((a, b) => a.locationName.compareTo(b.locationName));

    return <LocationModel>[parentLocation, ...children];
  }

  ParkingGridOverlay _buildOverlay() {
    final parentKey = _dialogNameKey(details.parent);
    final childKey = parkingOverlayCanonicalChildKey(details.child);
    if (parentKey.isEmpty || childKey.isEmpty) {
      return const ParkingGridOverlay.empty();
    }

    final slotNo = _dialogParseFirstInt(details.slot);
    if (slotNo != null) {
      return ParkingGridOverlay(
        slotStatusByKey: <String, ParkingSlotStatus>{
          '$parentKey|$childKey|$slotNo': ParkingSlotStatus.departureRequest,
        },
        groupStatusByKey: const <String, ParkingSlotStatus>{},
      );
    }

    return ParkingGridOverlay(
      slotStatusByKey: const <String, ParkingSlotStatus>{},
      groupStatusByKey: <String, ParkingSlotStatus>{
        '$parentKey|$childKey': ParkingSlotStatus.departureRequest,
      },
    );
  }
}

String _dialogNormalizeName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _dialogNameKey(String raw) => _dialogNormalizeName(raw).toLowerCase();

int? _dialogParseFirstInt(String raw) {
  final match = RegExp(r'(\d+)').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

bool _isCompositeParentTypeForDialog(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  return value == 'composite_parent' ||
      value.replaceAll(RegExp(r'[_\-\s]'), '') == 'compositeparent';
}

bool _isCompositeChildTypeForDialog(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  if (value == 'composite_child' || value == 'composite') return true;
  final packed = value.replaceAll(RegExp(r'[_\-\s]'), '');
  return packed == 'compositechild' || packed == 'composite';
}

bool _matchesAreaLooseForDialog(String parentArea, String childArea) {
  final pa = parentArea.trim();
  final ca = childArea.trim();
  if (pa.isEmpty) return true;
  if (ca.isEmpty) return true;
  return pa == ca;
}

Set<String> _parentAliasesForDialog(LocationModel parent) {
  final out = <String>{};

  void addValue(Object? value) {
    final key = _dialogNameKey((value ?? '').toString());
    if (key.isNotEmpty) out.add(key);
  }

  addValue(parent.id);
  addValue(parent.locationName);

  try {
    addValue((parent as dynamic).locationId);
  } catch (_) {}

  return out;
}

class _BigInlineEmpty extends StatelessWidget {
  final String text;
  final bool compact;

  const _BigInlineEmpty({
    required this.text,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final iconSize = compact ? 44.0 : 56.0;
    final titleStyle = (t.titleLarge ?? const TextStyle()).copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w900,
      fontSize: compact ? 18 : null,
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 18 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: iconSize, color: cs.outline),
            const SizedBox(height: 12),
            Text(text, style: titleStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
