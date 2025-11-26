import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../utils/block_dialogs/blocking_dialog.dart';
import '../../../../../utils/block_dialogs/duration_blocking_dialog.dart';
import 'end_work_report_service.dart';
import 'end_work_report_controller.dart';

class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
  static const fg = Colors.white;
}

Future<void> showEndReportDialog(BuildContext context) async {
  final areaState = context.read<AreaState>();
  final userState = context.read<UserState>();

  final area = areaState.currentArea;
  final division = areaState.currentDivision;
  final userName = userState.name;

  final controller = EndWorkReportController();
  await controller.loadInitialCounts(area);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height;

      return ChangeNotifierProvider.value(
        value: controller,
        child: SizedBox(
          height: height,
          child: Container(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: height,
              decoration: const BoxDecoration(
                // 바깥 배경은 문서철과 비슷하게 약간 밝은 회색 톤
                color: Color(0xFFF6F7F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
              ),
              child: EndWorkReportSheet(
                division: division,
                area: area,
                userName: userName,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class EndWorkReportSheet extends StatefulWidget {
  const EndWorkReportSheet({
    super.key,
    required this.division,
    required this.area,
    required this.userName,
  });

  final String division;
  final String area;
  final String userName;

  @override
  State<EndWorkReportSheet> createState() => _EndWorkReportSheetState();
}

class _EndWorkReportSheetState extends State<EndWorkReportSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _inputCtrl;
  late final TextEditingController _outputCtrl;
  late final TextEditingController _extraCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<EndWorkReportController>();
    _inputCtrl = TextEditingController(text: controller.vehicleInput.toString());
    _outputCtrl = TextEditingController(text: controller.vehicleOutput.toString());
    _extraCtrl = TextEditingController(text: controller.departureExtra.toString());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) {
      showFailedSnackbar(context, '숫자만 입력해 주세요.');
      return;
    }

    // ✅ 1단계: 15초 동안 취소 가능 다이얼로그 (자동 진행 or 취소 여부 확인)
    final proceed = await showDurationBlockingDialog(
      context,
      message: '업무 종료 보고를 서버에 전송합니다.\n'
          '약 15초 가량 소요되며, 취소하려면 아래 [취소] 버튼을 눌러 주세요.\n'
          '중간에 화면을 이탈하지 마세요.',
      duration: const Duration(seconds: 15),
    );

    if (!proceed) {
      if (mounted) {
        showFailedSnackbar(context, '업무 종료 보고가 취소되었습니다.');
      }
      return;
    }

    // ✅ 2단계: 실제 전송 시작 - 기존 runWithBlockingDialog로 처리 중 다이얼로그 표시
    setState(() => _submitting = true);

    final controller = context.read<EndWorkReportController>();
    final service = EndWorkReportService();

    try {
      final vehicleInput = int.tryParse(_inputCtrl.text.trim()) ?? 0;
      final vehicleOutputAgg = int.tryParse(_outputCtrl.text.trim()) ?? 0;
      final departureExtra =
          int.tryParse(_extraCtrl.text.trim()) ?? controller.departureExtra;

      final vehicleOutputTotal = vehicleOutputAgg + departureExtra;

      controller.setVehicleCounts(
        input: vehicleInput,
        output: vehicleOutputAgg,
      );
      controller.setDepartureExtraFromText(departureExtra.toString());

      await runWithBlockingDialog(
        context: context,
        message: '보고 처리 중입니다. 잠시만 기다려 주세요...',
        task: () async {
          final result = await service.submitEndReport(
            division: widget.division,
            area: widget.area,
            userName: widget.userName,
            vehicleInputCount: vehicleInput,
            vehicleOutputManual: vehicleOutputTotal,
          );

          if (!mounted) return;

          Navigator.pop(context);

          final lines = <String>[
            '업무 종료 보고 완료',
            '• 사용자 최종 출차 수(출차+중복 입차): ${result.vehicleOutputManual}',
            '• 스냅샷(plates: 정산 문서 수/합계요금): '
                '${result.snapshotLockedVehicleCount} / ${result.snapshotTotalLockedFee}',
          ];

          if (!result.cleanupOk) {
            lines.add('• 주의: 스냅샷 일부가 삭제되지 않았습니다. 관리자에게 문의하세요.');
          }

          if (!result.firestoreSaveOk) {
            lines.add('• Firestore(end_work_reports) 저장에 실패했습니다.');
          }

          if (!result.gcsReportUploadOk || !result.gcsLogsUploadOk) {
            lines.add('• GCS 보고/로그 파일 업로드에 일부 실패했습니다. 관리자에게 문의하세요.');
          }

          showSuccessSnackbar(context, lines.join('\n'));
        },
      );
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '예기치 못한 오류: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _gap(double h) => SizedBox(height: h);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = widget.area;
    final controller = context.watch<EndWorkReportController>();
    final textTheme = Theme.of(context).textTheme;

    final expectedInput = int.tryParse(_inputCtrl.text.trim()) ?? 0;
    final expectedOutputAgg = int.tryParse(_outputCtrl.text.trim()) ?? 0;
    final expectedExtra = int.tryParse(_extraCtrl.text.trim()) ?? 0;
    final expectedOutputTotal = expectedOutputAgg + expectedExtra;

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          // 상단 드래그 핸들
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),

          // 본문 스크롤 영역 (문서 느낌)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 상단 문서 헤더 타이틀
                              Text(
                                '업무 종료 보고서',
                                textAlign: TextAlign.center,
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'END OF WORK REPORT',
                                textAlign: TextAlign.center,
                                style: textTheme.labelMedium?.copyWith(
                                  color: Colors.black54,
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 실제 "종이" 느낌의 보고서 카드
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _Palette.light.withOpacity(0.8),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 상단 메타 정보 라인
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _Palette.base.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.assignment_turned_in,
                                            size: 20,
                                            color: _Palette.dark,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '업무 종료 보고',
                                                style: textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: _Palette.dark,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '근무 종료 시점의 차량 입·출차 집계를 정리하고\n'
                                                    '서버에 최종 결과를 보고합니다.',
                                                style: textTheme.bodySmall?.copyWith(
                                                  color: Colors.black54,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '지역: ${area.isEmpty ? "미설정" : area}',
                                              style:
                                              textTheme.bodySmall?.copyWith(
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '작성일 ${_fmtCompact(DateTime.now())}',
                                              style:
                                              textTheme.bodySmall?.copyWith(
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Divider(height: 24),
                                    const SizedBox(height: 4),

                                    // 안내 문구
                                    Container(
                                      decoration: BoxDecoration(
                                        color:
                                        _Palette.light.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _Palette.light.withOpacity(0.7),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                            color: _Palette.dark,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '입차/출차/중복 입차 수를 확인한 뒤 아래 양식에 숫자를 입력하고 '
                                                  '[제출] 버튼을 눌러 업무 종료 보고를 완료해 주세요.',
                                              style: textTheme.bodySmall?.copyWith(
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    _gap(16),

                                    // 1. 집계 기준 섹션
                                    _InfoCard(
                                      title: '1. 집계 기준',
                                      lines: const [
                                        '• 입차: 현재 근무 지역의 아직 입차 완료 상태인 차량',
                                        '• 출차: 현재 근무 지역의 출차 완료 차량 중 정산이 완료된 차량',
                                        '• 중복 입차: 출차 완료된 동일 번호판 차량의 입차에 대한 보정치',
                                      ],
                                    ),

                                    _gap(12),

                                    // 2. 차량 수 입력 섹션
                                    _SectionCard(
                                      title: '2. 차량 수 입력',
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          _numberField(
                                            context: context,
                                            controller: _inputCtrl,
                                            label: '입차 차량 수',
                                            helper: '집계값이 자동으로 출력됩니다.',
                                            onChanged: context
                                                .read<EndWorkReportController>()
                                                .setVehicleInputFromText,
                                          ),
                                          const SizedBox(height: 12),
                                          _numberField(
                                            context: context,
                                            controller: _outputCtrl,
                                            label: '출차 차량 수',
                                            helper: '집계값이 자동으로 출력됩니다.',
                                            onChanged: context
                                                .read<EndWorkReportController>()
                                                .setVehicleOutputFromText,
                                          ),
                                          const SizedBox(height: 12),
                                          _numberField(
                                            context: context,
                                            controller: _extraCtrl,
                                            label: '중복 입차 차량 수',
                                            helper: '집계값이 자동으로 출력됩니다.',
                                            onChanged: context
                                                .read<EndWorkReportController>()
                                                .setDepartureExtraFromText,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '출차 합계(출차 차량 수 + 중복 입차 차량 수): ${controller.departureTotal}대',
                                            style:
                                            textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding:
                                            const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _Palette.base
                                                  .withOpacity(0.08),
                                              borderRadius:
                                              BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _Palette.light
                                                    .withOpacity(.6),
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.flag_rounded,
                                                  size: 20,
                                                  color: _Palette.base,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '제출 시 저장 예상: 입차 $expectedInput대 / 출차 $expectedOutputTotal대',
                                                    style: textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                      fontWeight:
                                                      FontWeight.w700,
                                                      color: _Palette.dark,
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

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 하단 제출/취소 바
          _FooterBar(
            onCancel: () => Navigator.pop(context),
            onSubmit: _handleSubmit,
            busy: _submitting,
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? helper,
    ValueChanged<String>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _Palette.base),
        ),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      validator: (v) {
        if (v == null || v.isEmpty) return '값을 입력해 주세요.';
        if (int.tryParse(v) == null) return '정수만 입력 가능합니다.';
        return null;
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: textTheme.bodyMedium!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleSmall!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ...lines.map(
                  (raw) {
                String line = raw.trim();
                if (line.startsWith('•')) {
                  line = line.substring(1).trimLeft();
                }

                String label = line;
                String? desc;

                final colonIndex = line.indexOf(':');
                if (colonIndex != -1) {
                  label = line.substring(0, colonIndex).trim();
                  desc = line.substring(colonIndex + 1).trimLeft();
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: _Palette.base,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: textTheme.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (desc != null && desc.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                desc,
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.directions_car, color: _Palette.base),
              SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.onCancel,
    required this.onSubmit,
    required this.busy,
  });

  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -6),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Palette.dark,
                  side: BorderSide(
                    color: _Palette.light.withOpacity(.8),
                  ),
                ),
                child: const Text('취소'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: busy ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Palette.base,
                  foregroundColor: _Palette.fg,
                ),
                child: busy
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(_Palette.fg),
                  ),
                )
                    : const Text('제출'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
