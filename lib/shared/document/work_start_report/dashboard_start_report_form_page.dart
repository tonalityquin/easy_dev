import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/email_config.dart';
import '../../utils/gmail_pdf_mailer.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_api_logger.dart';
import 'dashboard_start_report_styles.dart';

class DashboardStartReportFormPage extends StatefulWidget {
  const DashboardStartReportFormPage({super.key});

  @override
  State<DashboardStartReportFormPage> createState() =>
      _DashboardStartReportFormPageState();
}

class _DashboardStartReportFormPageState
    extends State<DashboardStartReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _contentCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _contentNode = FocusNode();

  bool? _hasSpecialNote;
  String? _selectedArea;

  bool _sending = false;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  final GlobalKey _contentFieldKey = GlobalKey();

  static const String _tStart = 'start_report';
  static const String _tStartUi = 'start_report/ui';
  static const String _tStartPrefs = 'start_report/prefs';
  static const String _tStartPdf = 'start_report/pdf';
  static const String _tStartEmail = 'start_report/email';
  static const String _tGmailSend = 'gmail/send';

  static const String _prefStartDraftHasSpecialNote =
      'start_report_draft_has_special_note';
  static const String _prefStartDraftContent = 'start_report_draft_content';

  Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _updateMailBody();
    _loadSelectedArea();
    _loadDraft();
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      if (!mounted) return;
      setState(() {
        _selectedArea = area.trim().isEmpty ? null : area.trim();
      });

      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._loadSelectedArea',
        message: 'SharedPreferences(selectedArea) 로드 실패',
        error: e,
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
      if (!mounted) return;
      setState(() {
        _selectedArea = null;
      });
      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    }
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _contentNode.dispose();
    _pageController.dispose();

    super.dispose();
  }

  String _fmtDT(BuildContext context, DateTime? dt) {
    if (dt == null) return '미선택';
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(dt);
    final timeStr = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: true,
    );
    return '$dateStr $timeStr';
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSpecialNote = prefs.getBool(_prefStartDraftHasSpecialNote);
      final content = prefs.getString(_prefStartDraftContent) ?? '';
      _contentCtrl.text = content;
      if (!mounted) return;
      setState(() {
        _hasSpecialNote = hasSpecialNote;
      });
      _updateMailSubject();
      _updateMailBody(force: true);
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._loadDraft',
        message: '업무 시작 보고서 임시저장 데이터 로드 실패',
        error: e,
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasSpecialNote == null) {
        await prefs.remove(_prefStartDraftHasSpecialNote);
      } else {
        await prefs.setBool(
          _prefStartDraftHasSpecialNote,
          _hasSpecialNote!,
        );
      }
      await prefs.setString(_prefStartDraftContent, _contentCtrl.text.trim());
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._persistDraft',
        message: '업무 시작 보고서 임시저장 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
        },
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefStartDraftHasSpecialNote);
      await prefs.remove(_prefStartDraftContent);
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._clearDraft',
        message: '업무 시작 보고서 임시저장 데이터 삭제 실패',
        error: e,
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _animateToPage(int page) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _handleSpecialNoteSelection(bool value) async {
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = value;
      if (!value) {
        _contentCtrl.clear();
      }
      _updateMailSubject();
    });
    await _persistDraft();
    if (!mounted) return;
    if (value) {
      await _animateToPage(1);
      return;
    }
    await _animateToPage(2);
  }

  Future<void> _saveSpecialContentAndGoToMail() async {
    FocusScope.of(context).unfocus();

    if (_hasSpecialNote == null) {
      await _animateToPage(0);
      return;
    }

    if (_hasSpecialNote == true) {
      final isValid = _formKey.currentState?.validate() ?? false;
      if (!isValid) {
        _contentNode.requestFocus();
        final ctx = _contentFieldKey.currentContext;
        if (ctx != null) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        return;
      }
    }

    _updateMailBody(force: true);
    await _persistDraft();
    if (!mounted) return;
    await _animateToPage(2);
  }

  Future<void> _goBackFromCurrentPage() async {
    if (_currentPageIndex == 2) {
      await _animateToPage(_hasSpecialNote == true ? 1 : 0);
      return;
    }
    if (_currentPageIndex == 1) {
      await _animateToPage(0);
    }
  }

  Future<void> _exitPage() async {
    if (_sending || !mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _reset() async {
    _formKey.currentState?.reset();
    _contentCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = null;
      _currentPageIndex = 0;
    });
    _updateMailSubject();
    _updateMailBody(force: true);
    _pageController.jumpToPage(0);
  }

  String _resolveReportArea() {
    try {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isNotEmpty) return currentArea;
    } catch (_) {}

    final selectedArea = (_selectedArea ?? '').trim();
    if (selectedArea.isNotEmpty) return selectedArea;

    return '업무';
  }

  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    final area = _resolveReportArea();

    _mailSubjectCtrl.text =
        '$area 업무 시작 보고서 – ${month}월 ${day}일자$suffixSpecial';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text =
        '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 시작 보고서입니다.';
  }

  String _buildPreviewText(BuildContext context) {
    final specialText =
        _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    return [
      '— 업무 시작 보고서 —',
      '',
      '특이사항: $specialText',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showSubmitSuccessDialogAndClose() async {
    if (!mounted) return;

    await StatusDialog.showSuccess(
      context,
      title: StatusDialog.workStartReportSuccess,
      closeCurrentPageAfter: true,
    );
  }

  Future<void> _showPreview() async {
    _updateMailBody();
    final text = _buildPreviewText(context);

    final specialText =
        _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final createdAtText = _fmtDT(context, DateTime.now());

    Widget infoPill(ColorScheme cs, TextTheme t, IconData icon, String label,
        String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: t.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: t.bodySmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final t = Theme.of(ctx).textTheme;

        final borderColor = cs.outlineVariant.withOpacity(0.8);

        Widget section({
          required IconData icon,
          required String title,
          required Widget child,
          Color? background,
        }) {
          return Container(
            decoration: BoxDecoration(
              color: background ?? cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 20, color: borderColor),
                const SizedBox(height: 2),
                child,
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxHeight = MediaQuery.of(ctx).size.height * 0.8;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Material(
                      color: cs.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: BoxDecoration(color: cs.primary),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined,
                                    color: cs.onPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '업무 시작 보고서 미리보기',
                                        style: t.titleMedium?.copyWith(
                                          color: cs.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 보고서 내용을 한 번 더 확인해 주세요.',
                                        style: t.bodySmall?.copyWith(
                                          color: cs.onPrimary.withOpacity(0.85),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: Icon(Icons.close, color: cs.onPrimary),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        infoPill(
                                            cs,
                                            t,
                                            Icons.calendar_today_outlined,
                                            '작성일',
                                            createdAtText),
                                        infoPill(
                                            cs,
                                            t,
                                            Icons.label_important_outline,
                                            '특이사항',
                                            specialText),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    section(
                                      icon: Icons.email_outlined,
                                      title: '메일 전송 정보',
                                      background: cs.surfaceContainerLow,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '제목',
                                            style: t.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: t.bodyMedium?.copyWith(
                                              color: cs.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: t.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: cs.surface,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: borderColor
                                                      .withOpacity(0.8)),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: t.bodyMedium?.copyWith(
                                                  color: cs.onSurface),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    section(
                                      icon: Icons.report_problem_outlined,
                                      title: '특이 사항 상세 내용',
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color:
                                                  borderColor.withOpacity(0.8)),
                                        ),
                                        child: Text(
                                          _contentCtrl.text.trim().isEmpty
                                              ? '입력된 특이 사항이 없습니다.'
                                              : _contentCtrl.text,
                                          style: t.bodyMedium?.copyWith(
                                            height: 1.4,
                                            color:
                                                _contentCtrl.text.trim().isEmpty
                                                    ? cs.onSurfaceVariant
                                                    : cs.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color:
                                                borderColor.withOpacity(0.7)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline,
                                              size: 18,
                                              color: cs.onPrimaryContainer),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: t.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: cs.onPrimaryContainer,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              border: Border(
                                  top: BorderSide(
                                      color: borderColor.withOpacity(0.9))),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: text));
                                  },
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('텍스트 복사'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: cs.primary),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('닫기'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: cs.onSurface),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }

    setState(() => _sending = true);

    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        await _logApiError(
          tag: 'DashboardStartReportFormPage._submit',
          message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
          error: Exception('invalid_to'),
          extra: <String, dynamic>{'toRaw': cfg.to},
          tags: const <String>[_tStartEmail, _tStartUi, _tStart],
        );
        if (!mounted) return;
        return;
      }

      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        if (!mounted) return;
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final filename = _safeFileName('업무시작보고서_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      await _clearDraft();

      if (!mounted) return;
      await _showSubmitSuccessDialogAndClose();
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._submit',
        message: '메일 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'subjectLen': _mailSubjectCtrl.text.trim().length,
          'bodyLen': _mailBodyCtrl.text.trim().length,
        },
        tags: const <String>[_tStartEmail, _tStartUi, _tStart, _tGmailSend],
      );

      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '업무시작보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    try {
      pw.Font? regular;
      pw.Font? bold;

      try {
        final regData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
        regular = pw.Font.ttf(regData);
      } catch (_) {}

      try {
        final boldData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
        bold = pw.Font.ttf(boldData);
      } catch (_) {
        bold = regular;
      }

      final theme = (regular != null)
          ? pw.ThemeData.withFont(
              base: regular,
              bold: bold ?? regular,
              italic: regular,
              boldItalic: bold ?? regular,
            )
          : pw.ThemeData.base();

      final doc = pw.Document();

      final specialText =
          _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

      final fields = <MapEntry<String, String>>[
        MapEntry('특이사항', specialText),
      ];

      pw.Widget buildFieldTable() => pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(7)
            },
            children: [
              for (final kv in fields)
                pw.TableRow(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      color: PdfColors.grey200,
                      child: pw.Text(kv.key,
                          style: const pw.TextStyle(fontSize: 11)),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(kv.value,
                          style: const pw.TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
            ],
          );

      pw.Widget buildSection(String title, String body) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 8),
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(body.isEmpty ? '-' : body,
                    style: const pw.TextStyle(fontSize: 11)),
              ),
            ],
          );

      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
          build: (context) => [
            pw.Center(
              child: pw.Text('업무 시작 보고서',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[업무 내용]', _contentCtrl.text),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '생성 시각: ${_fmtCompact(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ),
      );

      return doc.save();
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
        },
        tags: const <String>[_tStartPdf, _tStartUi, _tStart],
      );
      rethrow;
    }
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      await GmailPdfMailer.sendPdf(
        pdfBytes: pdfBytes,
        filename: filename,
        to: to,
        subject: subject,
        body: body,
      );
    } catch (e) {
      await _logApiError(
        tag: 'DashboardStartReportFormPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
        },
        tags: const <String>[_tStartEmail, _tStartUi, _tStart, _tGmailSend],
      );
      rethrow;
    }
  }


  InputDecoration _inputDec(
    BuildContext context, {
    required String labelText,
    String? hintText,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
      ),
      color: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: t.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Widget _buildSpecialNoteBody() {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget choice({required bool value, required String label}) {
      final selected = _hasSpecialNote == value;

      return Expanded(
        child: selected
            ? ElevatedButton(
                onPressed:
                    _sending ? null : () => _handleSpecialNoteSelection(value),
                style: DashboardReportButtonStyles.primary(context),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed:
                    _sending ? null : () => _handleSpecialNoteSelection(value),
                style: DashboardReportButtonStyles.outlined(context),
                child: Text(label),
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: t.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            choice(value: false, label: '특이사항 없음'),
            const SizedBox(width: 12),
            choice(value: true, label: '특이사항 있음'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildWorkContentBody() {
    return TextFormField(
      key: _contentFieldKey,
      controller: _contentCtrl,
      focusNode: _contentNode,
      decoration: _inputDec(
        context,
        labelText: '특이 사항',
        hintText: '예)\n'
            '- 육하원칙에 맞춰서 작성하세요.\n'
            '- 컴플레인, 사고, 인사 갈등, 고객사와의 소통 발생 여부 및 내용\n'
            '- 업무 프로세스, 업무 환경, 물품 파손 등 문제\n'
            '- 발생 과정 및 조치 사항\n',
      ),
      keyboardType: TextInputType.multiline,
      minLines: 8,
      maxLines: 16,
      onTap: () {
        Future.delayed(const Duration(milliseconds: 150), () {
          final ctx = _contentFieldKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut);
          }
        });
      },
      onChanged: (_) {
        if (_hasSpecialNote == true) {
          _persistDraft();
        }
      },
      validator: (v) {
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) return '업무 내용을 입력하세요.';
        }
        return null;
      },
    );
  }

  Widget _buildMailBody() {
    return Column(
      children: [
        TextFormField(
          controller: _mailSubjectCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            context,
            labelText: '메일 제목(자동 생성)',
            hintText: '예: 콜센터 업무 시작 보고서 – 11월 25일자 - 특이사항 있음',
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(context,
              labelText: '메일 본문(자동 생성)', hintText: '작성 시각 정보가 자동으로 입력됩니다.'),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  Widget _buildReportPage({
    required String sectionTitle,
    required Widget sectionBody,
  }) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scrollbar(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '업무 시작 보고서',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK START REPORT',
                  textAlign: TextAlign.center,
                  style: t.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.8), width: 1),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded,
                              size: 22, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            '업무 시작 보고서 양식',
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: t.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                          height: 24,
                          color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.8)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.\n'
                                '문제 발생 시 담당자에게 상황을 전달해 주세요.',
                                style: t.bodySmall?.copyWith(
                                    height: 1.4, color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _gap(20),
                      _sectionCard(
                        context,
                        title: sectionTitle,
                        margin: const EdgeInsets.only(bottom: 0),
                        child: sectionBody,
                      ),
                      _gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sending ? null : _reset,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('초기화'),
                              style:
                                  DashboardReportButtonStyles.outlined(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style:
                                  DashboardReportButtonStyles.primary(context),
                            ),
                          ),
                        ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: cs.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '뒤로가기',
            onPressed: _sending ? null : _exitPage,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: const Text('업무 시작 보고서 작성'),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withOpacity(0.8),
              width: 1,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                onPressed: _showPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('미리보기'),
                style: DashboardReportButtonStyles.smallPrimary(context),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _currentPageIndex == 1 || _currentPageIndex == 2
            ? SafeArea(
                top: false,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withOpacity(0.8),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sending ? null : _goBackFromCurrentPage,
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          label: const Text('이전'),
                          style: DashboardReportButtonStyles.outlined(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sending
                              ? null
                              : _currentPageIndex == 1
                                  ? _saveSpecialContentAndGoToMail
                                  : _submit,
                          icon: _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      cs.onPrimary,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _currentPageIndex == 1
                                      ? Icons.save_outlined
                                      : Icons.send_outlined,
                                ),
                          label: Text(
                            _sending
                                ? '전송 중…'
                                : _currentPageIndex == 1
                                    ? '저장'
                                    : '제출',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: DashboardReportButtonStyles.primary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
              },
              children: [
                _buildReportPage(
                  sectionTitle: '1. 특이사항 여부 (필수)',
                  sectionBody: _buildSpecialNoteBody(),
                ),
                _buildReportPage(
                  sectionTitle: '2. 특이 사항 (조건부 필수)',
                  sectionBody: _buildWorkContentBody(),
                ),
                _buildReportPage(
                  sectionTitle: '3. 메일 전송 내용',
                  sectionBody: _buildMailBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
