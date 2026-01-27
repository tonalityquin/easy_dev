import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/google_auth_v7.dart';
import '../../../../../utils/api/email_config.dart';
import 'single_inside_report_styles.dart';
import 'single_inside_report_signature_dialog.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

class SingleInsideStartReportFormPage extends StatefulWidget {
  const SingleInsideStartReportFormPage({super.key});

  @override
  State<SingleInsideStartReportFormPage> createState() => _SingleInsideStartReportFormPageState();
}

class _SingleInsideStartReportFormPageState extends State<SingleInsideStartReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 확장 대비 유지
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  bool? _hasSpecialNote; // null=미선택, true/false

  // SharedPreferences selectedArea
  String? _selectedArea;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  final GlobalKey _contentFieldKey = GlobalKey();

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직
  // ─────────────────────────────────────────────────────────────
  static const String _tReport = 'report';
  static const String _tReportStart = 'report/start';
  static const String _tReportPdf = 'report/pdf';
  static const String _tReportEmail = 'report/email';

  static const String _tGmail = 'gmail';
  static const String _tGmailSend = 'gmail/send';

  static const String _tPrefs = 'prefs';

  // MIME base64 line length (RFC 2045 recommends 76 chars)
  static const int _mimeB64LineLength = 76;

  static Future<void> _logApiError({
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

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? (i + lineLength) : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _updateMailBody();
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = (prefs.getString('selectedArea') ?? '').trim();
      if (!mounted) return;
      setState(() {
        _selectedArea = area.isEmpty ? null : area;
      });

      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._loadSelectedArea',
        message: 'SharedPreferences(selectedArea) 로드 실패',
        error: e,
        tags: const <String>[_tReport, _tReportStart, _tPrefs],
      );
      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    }
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _contentCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
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

  void _reset() {
    HapticFeedback.lightImpact();
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _contentCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();

    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _hasSpecialNote = null;
      _currentPageIndex = 0;
    });

    _updateMailSubject();
    _updateMailBody(force: true);
    _pageController.jumpToPage(0);
  }

  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    final area = (_selectedArea != null && _selectedArea!.trim().isNotEmpty) ? _selectedArea!.trim() : '업무';
    _mailSubjectCtrl.text = '$area 업무 시작 보고서 – ${month}월 ${day}일자$suffixSpecial';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text = '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 시작 보고서입니다.';
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    return [
      '— 업무 시작 보고서 —',
      '',
      '특이사항: $specialText',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    HapticFeedback.lightImpact();
    _updateMailBody();
    final text = _buildPreviewText(context);

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);
    final createdAtText = _fmtDT(context, DateTime.now());

    Widget infoPill(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    Widget sectionCard({
      required IconData icon,
      required String title,
      required Widget child,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 16, color: cs.outlineVariant.withOpacity(0.6)),
            child,
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final cs2 = Theme.of(ctx).colorScheme;
        final tt2 = Theme.of(ctx).textTheme;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxHeight = MediaQuery.of(ctx).size.height * 0.8;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Material(
                      color: cs2.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: BoxDecoration(color: cs2.primary),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined, color: cs2.onPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '업무 시작 보고서 미리보기',
                                        style: tt2.titleMedium?.copyWith(
                                          color: cs2.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 보고서 내용을 한 번 더 확인해 주세요.',
                                        style: tt2.bodySmall?.copyWith(
                                          color: cs2.onPrimary.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: Icon(Icons.close, color: cs2.onPrimary),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),

                          // Body
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        infoPill(Icons.calendar_today_outlined, '작성일', createdAtText),
                                        infoPill(Icons.label_important_outline, '특이사항', specialText),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    sectionCard(
                                      icon: Icons.email_outlined,
                                      title: '메일 전송 정보',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '제목',
                                            style: tt2.bodySmall?.copyWith(
                                              color: cs2.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: tt2.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: cs2.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: tt2.bodySmall?.copyWith(
                                              color: cs2.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: cs2.surface,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: cs2.outlineVariant.withOpacity(0.6)),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: tt2.bodyMedium?.copyWith(color: cs2.onSurface),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    sectionCard(
                                      icon: Icons.report_problem_outlined,
                                      title: '특이 사항 상세 내용',
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs2.surface,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: cs2.outlineVariant.withOpacity(0.6)),
                                        ),
                                        child: Text(
                                          _contentCtrl.text.trim().isEmpty ? '입력된 특이 사항이 없습니다.' : _contentCtrl.text,
                                          style: tt2.bodyMedium?.copyWith(
                                            height: 1.4,
                                            color: _contentCtrl.text.trim().isEmpty
                                                ? cs2.onSurfaceVariant
                                                : cs2.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    sectionCard(
                                      icon: Icons.edit_outlined,
                                      title: '전자서명 정보',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명자',
                                                      style: tt2.bodySmall?.copyWith(
                                                        color: cs2.onSurfaceVariant,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signName,
                                                      style: tt2.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: cs2.onSurface,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명 일시',
                                                      style: tt2.bodySmall?.copyWith(
                                                        color: cs2.onSurfaceVariant,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signTimeText,
                                                      style: tt2.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: cs2.onSurface,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            height: 140,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: cs2.outlineVariant.withOpacity(0.7)),
                                              color: cs2.surfaceContainerHigh,
                                            ),
                                            child: _signaturePngBytes == null
                                                ? Center(
                                              child: Text(
                                                '서명 이미지가 없습니다. (전자서명 완료 후 제출할 수 있습니다.)',
                                                style: tt2.bodySmall?.copyWith(color: cs2.onSurfaceVariant),
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                                : Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Image.memory(
                                                _signaturePngBytes!,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // 안내(텍스트 복사)
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs2.primaryContainer.withOpacity(0.70),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: cs2.outlineVariant.withOpacity(0.6)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline, size: 18, color: cs2.onPrimaryContainer),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 '
                                                  '텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: tt2.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: cs2.onPrimaryContainer,
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

                          // Bottom actions
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: cs2.surfaceContainerLow,
                              border: Border(top: BorderSide(color: cs2.outlineVariant.withOpacity(0.7))),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(ClipboardData(text: text));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('텍스트가 클립보드에 복사되었습니다.')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('텍스트 복사'),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('닫기'),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('특이사항 여부를 선택해 주세요.')),
      );
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _sending = true);

    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        await _logApiError(
          tag: 'SingleInsideStartReportFormPage._submit',
          message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
          error: Exception('invalid_to'),
          extra: <String, dynamic>{'toRaw': cfg.to},
          tags: const <String>[_tReport, _tReportStart, _tReportEmail],
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.'),
          ),
        );
        return;
      }

      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        await _logApiError(
          tag: 'SingleInsideStartReportFormPage._submit',
          message: '메일 제목이 비어있음(자동 생성 실패)',
          error: Exception('empty_subject'),
          tags: const <String>[_tReport, _tReportStart],
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목이 자동 생성되지 않았습니다.')),
        );
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무시작보고서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메일 전송 완료')));
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._submit',
        message: '업무 시작 보고서 제출 실패(예외)',
        error: e,
        extra: <String, dynamic>{
          'hasSignature': _signaturePngBytes != null,
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'subjectLen': _mailSubjectCtrl.text.trim().length,
        },
        tags: const <String>[_tReport, _tReportStart],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '업무시작보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final regData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(regData);
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._buildPdfBytes',
        message: 'PDF 폰트 로드 실패(Regular)',
        error: e,
        tags: const <String>[_tReport, _tReportStart, _tReportPdf],
      );
    }

    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(boldData);
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._buildPdfBytes',
        message: 'PDF 폰트 로드 실패(Bold) — regular로 대체',
        error: e,
        tags: const <String>[_tReport, _tReportStart, _tReportPdf],
      );
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

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    final fields = <MapEntry<String, String>>[
      MapEntry('특이사항', specialText),
    ];

    pw.Widget buildFieldTable() => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(7),
      },
      children: [
        for (final kv in fields)
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.grey200,
                child: pw.Text(kv.key, style: const pw.TextStyle(fontSize: 11)),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(kv.value, style: const pw.TextStyle(fontSize: 11)),
              ),
            ],
          ),
      ],
    );

    pw.Widget buildSection(String title, String body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(body.isEmpty ? '-' : body, style: const pw.TextStyle(fontSize: 11)),
        ),
      ],
    );

    pw.Widget buildSignature() {
      final name = _signerName.isEmpty ? '이름 미입력' : _signerName;
      final timeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text('전자서명', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('서명자: $name', style: const pw.TextStyle(fontSize: 11))),
              pw.SizedBox(width: 8),
              pw.Text('서명 일시: $timeText', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 120,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: _signaturePngBytes == null
                ? pw.Center(
              child: pw.Text(
                '서명 이미지 없음',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            )
                : pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Image(
                pw.MemoryImage(_signaturePngBytes!),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              '업무 시작 보고서',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[업무 내용]', _contentCtrl.text),
          buildSignature(),
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

    try {
      return doc.save();
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._buildPdfBytes',
        message: 'PDF 생성/저장 실패',
        error: e,
        extra: <String, dynamic>{
          'contentLen': _contentCtrl.text.trim().length,
          'hasSignature': _signaturePngBytes != null,
        },
        tags: const <String>[_tReport, _tReportStart, _tReportPdf],
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
      final client = await GoogleAuthV7.authedClient(const <String>[]);
      final api = gmail.GmailApi(client);

      final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
      final subjectB64 = base64.encode(utf8.encode(subject));

      final attachmentB64 = base64.encode(pdfBytes);
      final attachmentWrapped = _wrapBase64Lines(attachmentB64);

      const crlf = '\r\n';
      final sb = StringBuffer()
        ..write('To: $to$crlf')
        ..write('Subject: =?utf-8?B?$subjectB64?=$crlf')
        ..write('MIME-Version: 1.0$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(body)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: application/pdf; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(attachmentWrapped)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;

      await api.users.messages.send(msg, 'me');
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideStartReportFormPage._sendEmailViaGmail',
        message: 'Gmail 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.trim().length,
          'subjectLen': subject.trim().length,
          'bodyLen': body.trim().length,
          'filename': filename,
          'pdfBytes': pdfBytes.length,
        },
        tags: const <String>[_tReport, _tReportStart, _tReportEmail, _tGmail, _tGmailSend],
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
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Future<void> _openSignatureDialog() async {
    HapticFeedback.selectionClick();
    final cs = Theme.of(context).colorScheme;

    final result = await showGeneralDialog<SignatureResult>(
      context: context,
      barrierLabel: '서명',
      barrierDismissible: false,
      barrierColor: cs.scrim.withOpacity(0.55),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return SignatureFullScreenDialog(
          name: _signerName,
          initialDateTime: _signDateTime,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );

    if (result != null) {
      setState(() {
        _signaturePngBytes = result.pngBytes;
        _signDateTime = result.signDateTime;
      });
    }
  }

  Widget _buildSpecialNoteBody() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget choice({
      required bool value,
      required String label,
    }) {
      final selected = _hasSpecialNote == value;

      return Expanded(
        child: selected
            ? ElevatedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasSpecialNote = value;
              _updateMailSubject();
            });
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          style: SingleReportButtonStyles.primary(context),
          child: Text(label),
        )
            : OutlinedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasSpecialNote = value;
              _updateMailSubject();
            });
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          style: SingleReportButtonStyles.outlined(context),
          child: Text(label),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
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
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
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
          validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            context,
            labelText: '메일 본문(자동 생성)',
            hintText: '작성 시각 정보가 자동으로 입력됩니다.',
          ),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  Widget _buildSignatureBody() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openSignatureDialog,
                icon: const Icon(Icons.border_color),
                label: const Text('서명하기'),
                style: SingleReportButtonStyles.smallPrimary(context),
              ),
              if (_signaturePngBytes != null)
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _signaturePngBytes = null;
                      _signDateTime = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('서명 삭제'),
                  style: SingleReportButtonStyles.smallOutlined(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_signaturePngBytes != null)
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Image.memory(
                    _signaturePngBytes!,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReportPage({
    required String sectionTitle,
    required Widget sectionBody,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK START REPORT',
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.8), width: 1),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded, size: 22, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            '업무 시작 보고서 양식',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 24, color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 4),

                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.',
                                style: textTheme.bodySmall?.copyWith(height: 1.4, color: cs.onSurface),
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
                              style: SingleReportButtonStyles.outlined(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: SingleReportButtonStyles.primary(context),
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('업무 시작 보고서 작성'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.8), width: 1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: SingleReportButtonStyles.smallPrimary(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _currentPageIndex == 3
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
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.8), width: 1)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!_sending && _signaturePngBytes != null) ? _submit : null,
              icon: _sending
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '제출',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: SingleReportButtonStyles.primary(context),
            ),
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
            onPageChanged: (index) {
              setState(() {
                _currentPageIndex = index;
                if (index == 0) {
                  _hasSpecialNote = null;
                  _updateMailSubject();
                }
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
              _buildReportPage(
                sectionTitle: '4. 전자서명',
                sectionBody: _buildSignatureBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
