import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../widgets/personal_plate_search_result_section.dart';
import 'personal_departure_success_dialog.dart';

enum PersonalPlateSearchDialogCloseReason {
  reset,
  confirmed,
  cancelled,
}

enum _PersonalPlateSearchDialogScreen {
  list,
  confirm,
}

Future<PersonalPlateSearchDialogCloseReason?> showPersonalPlateSearchDialog({
  required BuildContext context,
  required List<PlateModel> results,
  required String input,
}) {
  return showDialog<PersonalPlateSearchDialogCloseReason>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (dialogCtx) {
      return PersonalPlateSearchDialog(
        results: results,
        input: input,
      );
    },
  );
}

class PersonalPlateSearchDialog extends StatefulWidget {
  const PersonalPlateSearchDialog({
    super.key,
    required this.results,
    required this.input,
  });

  final List<PlateModel> results;
  final String input;

  @override
  State<PersonalPlateSearchDialog> createState() =>
      _PersonalPlateSearchDialogState();
}

class _PersonalPlateSearchDialogState extends State<PersonalPlateSearchDialog> {
  PlateModel? _selected;
  String? _selectedId;
  bool _busy = false;
  late _PersonalPlateSearchDialogScreen _screen;

  @override
  void initState() {
    super.initState();
    final hasSingleResult = widget.results.length == 1;
    _selected = hasSingleResult ? widget.results.first : null;
    _selectedId = hasSingleResult ? widget.results.first.id : null;
    _screen = hasSingleResult
        ? _PersonalPlateSearchDialogScreen.confirm
        : _PersonalPlateSearchDialogScreen.list;
  }

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

  void _popReset() {
    if (_busy) return;
    Navigator.of(context).pop(PersonalPlateSearchDialogCloseReason.reset);
  }

  void _popCancelled() {
    if (_busy) return;
    Navigator.of(context).pop(PersonalPlateSearchDialogCloseReason.cancelled);
  }

  Future<void> _confirmDepartureRequested() async {
    final plate = _selected;
    if (plate == null || _busy) return;

    setState(() => _busy = true);

    try {
      final movementPlate = context.read<MovementPlate>();
      await movementPlate.setDepartureRequested(
        plate.plateNumber,
        plate.area,
        plate.location,
        forceViewSync: true,
      );

      if (!mounted) return;
      await showPersonalDepartureRequestedSuccessDialog(context, plate);

      if (!mounted) return;
      Navigator.of(context).pop(PersonalPlateSearchDialogCloseReason.confirmed);
    } catch (e) {
      if (!mounted) return;
      debugPrint('개인형 출차 요청 처리 중 오류가 발생했습니다: $e');
      setState(() => _busy = false);
    }
  }

  Widget _buildResultsList({required bool compact}) {
    final cs = Theme.of(context).colorScheme;

    final render = widget.results
        .map((p) => p.copyWith(
              isSelected: _selectedId != null && p.id == _selectedId,
            ))
        .toList();

    if (render.isEmpty) {
      return _PersonalBigInlineEmpty(
        text: '검색 결과가 없습니다.',
        compact: compact,
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
        child: PersonalPlateSearchResultSection(
          results: render,
          compact: compact,
          onSelect: (p) {
            if (_busy) return;
            setState(() {
              _selected = p;
              _selectedId = p.id;

              if (compact) {
                _screen = _PersonalPlateSearchDialogScreen.confirm;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildConfirmPanel({required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_selected == null) {
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

    final plate = _selected!;
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

    final double plateFontSize = compact ? 36 : 44;
    final double buttonHeight = compact ? 52 : 56;

    final content = Column(
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
                onPressed: _busy ? null : _popCancelled,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, buttonHeight),
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outline.withOpacity(.35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: (text.titleMedium ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton.icon(
                icon: _busy
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
                label: Text(_busy ? '처리 중...' : '네, 출차 요청'),
                onPressed: _busy ? null : _confirmDepartureRequested,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, buttonHeight),
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
      ],
    );

    if (compact) return content;

    return Container(
      decoration: BoxDecoration(
        color: _tintOnSurface(
          cs,
          opacity: cs.brightness == Brightness.dark ? 0.08 : 0.035,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.14)),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: SingleChildScrollView(
          child: content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final bool isPhone = size.shortestSide < 600;
    final double maxDialogWidth =
        (size.width - 32).clamp(0.0, 1280.0).toDouble();
    final double maxDialogHeight =
        (size.height * 0.92).clamp(0.0, size.height).toDouble();
    final bool useTwoPane = !isPhone && maxDialogWidth >= 980;
    final countLabel = widget.results.isEmpty ? '없음' : '${widget.results.length}건';
    final inputLine = '입력 번호: ${widget.input}';

    if (isPhone) {
      final screenTitle = _screen == _PersonalPlateSearchDialogScreen.list
          ? '검색 결과 · $countLabel'
          : '출차 요청 확인';
      final screenSubtitle = _screen == _PersonalPlateSearchDialogScreen.list
          ? inputLine
          : (_selected == null ? inputLine : _selected!.plateNumber);

      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: SafeArea(
            child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(screenTitle),
                  Text(
                    screenSubtitle,
                    style: (text.bodySmall ?? const TextStyle()).copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              leading: _screen == _PersonalPlateSearchDialogScreen.confirm &&
                      widget.results.length != 1
                  ? IconButton(
                      tooltip: '목록으로',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _screen = _PersonalPlateSearchDialogScreen.list;
                              }),
                    )
                  : IconButton(
                      tooltip: '닫기',
                      icon: const Icon(Icons.close),
                      onPressed: _busy ? null : _popReset,
                    ),
              actions: [
                IconButton(
                  tooltip: '초기화',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: _busy ? null : _popReset,
                ),
              ],
            ),
            body: Column(
              children: [
                if (_screen == _PersonalPlateSearchDialogScreen.list)
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
                          opacity: cs.brightness == Brightness.dark ? 0.12 : 0.06,
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
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _screen == _PersonalPlateSearchDialogScreen.list
                        ? _buildResultsList(compact: true)
                        : _buildConfirmPanel(compact: true),
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
                        opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10,
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
                      style: (text.titleLarge ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '초기화',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: _busy ? null : _popReset,
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
                    opacity: cs.brightness == Brightness.dark ? 0.12 : 0.06,
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
                            child: _buildResultsList(compact: false),
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
                            child: _buildConfirmPanel(compact: false),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _buildResultsList(compact: false)),
                          const SizedBox(height: 12),
                          Expanded(child: _buildConfirmPanel(compact: false)),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _popReset,
                  child: Text(
                    '초기화',
                    style: (text.titleMedium ?? const TextStyle()).copyWith(
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
  }
}

class _PersonalBigInlineEmpty extends StatelessWidget {
  final String text;
  final bool compact;

  const _PersonalBigInlineEmpty({
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
