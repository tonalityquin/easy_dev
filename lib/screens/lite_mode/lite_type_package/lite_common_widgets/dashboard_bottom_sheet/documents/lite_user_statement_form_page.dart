import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../../../utils/google_auth_v7.dart';
import '../../../../../../utils/api/email_config.dart';
import 'sections/lite_user_statement_styles.dart';
import 'sections/lite_user_statement_signature_dialog.dart';

class UserStatementFormPage extends StatefulWidget {
  const UserStatementFormPage({super.key});

  @override
  State<UserStatementFormPage> createState() => _UserStatementFormPageState();
}

class _UserStatementFormPageState extends State<UserStatementFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  DateTime? _eventDateTime;

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
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

  Future<void> _pickDateTime() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _eventDateTime ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventDateTime ?? now),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    setState(() {
      _eventDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
      _eventDateTime = null;
      _signaturePngBytes = null;
      _signDateTime = null;
    });
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';
    return [
      '— 경위서 —',
      '',
      '소속: ${(_deptCtrl.text).trim()}',
      '성명: ${(_nameCtrl.text).trim()}',
      '직책: ${(_positionCtrl.text).trim()}',
      '일시: ${_fmtDT(context, _eventDateTime)}',
      '',
      '[내용(육하원칙 기반)]',
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
    final text = _buildPreviewText(context);

    // 화면에 표시할 항목들 가공
    final createdAtText = _fmtDT(context, DateTime.now());
    final eventAtText = _fmtDT(context, _eventDateTime);

    final dept = _deptCtrl.text.trim().isEmpty ? '미입력' : _deptCtrl.text.trim();
    final name = _nameCtrl.text.trim().isEmpty ? '미입력' : _nameCtrl.text.trim();
    final position =
    _positionCtrl.text.trim().isEmpty ? '미입력' : _positionCtrl.text.trim();

    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText =
    _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

    Widget _infoPill(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
        final theme = Theme.of(ctx);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 상단 헤더 바
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: const BoxDecoration(
                              color: UserStatementColors.dark,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '경위서 미리보기',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 경위서 내용을 한 번 더 확인해 주세요.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                          Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),

                          // 본문 스크롤 영역
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    // 상단 요약 배지들
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _infoPill(
                                          Icons.calendar_today_outlined,
                                          '작성일',
                                          createdAtText,
                                        ),
                                        _infoPill(
                                          Icons.schedule_outlined,
                                          '사건 일시',
                                          eventAtText,
                                        ),
                                        _infoPill(
                                          Icons.badge_outlined,
                                          '작성자',
                                          '$dept / $position / $name',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // 메일 정보 카드
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                          Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.email_outlined,
                                                size: 18,
                                                color:
                                                UserStatementColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight:
                                                  FontWeight.w600,
                                                  color:
                                                  UserStatementColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Text(
                                            '제목',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: theme
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding:
                                            const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                              BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey
                                                    .withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text.trim().isEmpty
                                                  ? '입력된 메일 본문이 없습니다.'
                                                  : _mailBodyCtrl.text,
                                              style: theme
                                                  .textTheme.bodyMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 경위 내용 카드
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                          Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.description_outlined,
                                                size: 18,
                                                color:
                                                UserStatementColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '경위 내용 (육하원칙 기반)',
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight:
                                                  FontWeight.w600,
                                                  color:
                                                  UserStatementColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          // 기본 정보 간단 요약
                                          Text(
                                            '기본 정보',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            width: double.infinity,
                                            padding:
                                            const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                              const Color(0xFFFBFBFB),
                                              borderRadius:
                                              BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey
                                                    .withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              '소속: $dept\n'
                                                  '성명: $name\n'
                                                  '직책: $position\n'
                                                  '일시: $eventAtText',
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '상세 경위',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding:
                                            const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                              const Color(0xFFFBFBFB),
                                              borderRadius:
                                              BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey
                                                    .withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _contentCtrl.text
                                                  .trim()
                                                  .isEmpty
                                                  ? '입력된 경위 내용이 없습니다.'
                                                  : _contentCtrl.text,
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                height: 1.4,
                                                color: _contentCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                    ? Colors.grey[600]
                                                    : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 서명 정보 + 이미지
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                          Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color:
                                                UserStatementColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight:
                                                  FontWeight.w600,
                                                  color:
                                                  UserStatementColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                                  children: [
                                                    Text(
                                                      '서명자',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                        color:
                                                        Colors.grey[700],
                                                        fontWeight:
                                                        FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signName,
                                                      style: theme
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                        FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                                  children: [
                                                    Text(
                                                      '서명 일시',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                        color:
                                                        Colors.grey[700],
                                                        fontWeight:
                                                        FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signTimeText,
                                                      style: theme
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                        FontWeight.w500,
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
                                              borderRadius:
                                              BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey
                                                    .withOpacity(0.4),
                                              ),
                                              color:
                                              const Color(0xFFFAFAFA),
                                            ),
                                            child: _signaturePngBytes == null
                                                ? Center(
                                              child: Text(
                                                '서명 이미지가 없습니다. (전자서명 완료 후 제출할 수 있습니다.)',
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                  color:
                                                  Colors.grey[600],
                                                ),
                                                textAlign:
                                                TextAlign.center,
                                              ),
                                            )
                                                : Padding(
                                              padding:
                                              const EdgeInsets.all(
                                                  8),
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

                                    // 원본 텍스트 안내
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius:
                                        BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                            color: Color(0xFF4F46E5),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 '
                                                  '텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                height: 1.4,
                                                color:
                                                const Color(0xFF1F2937),
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

                          // 하단 액션 영역
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(
                                16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(
                                        ClipboardData(text: text));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content:
                                        Text('텍스트가 클립보드에 복사되었습니다.'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                  ),
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

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.',
            ),
          ),
        );
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('메일 제목을 입력해 주세요.'),
          ),
        );
        return;
      }

      if (_eventDateTime == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('일시를 선택해 주세요.'),
          ),
        );
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile =
      _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename =
      _safeFileName('경위서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '경위서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final regData = await rootBundle
          .load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(regData);
    } catch (_) {}

    try {
      final boldData =
      await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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
    final fields = <MapEntry<String, String>>[
      MapEntry('소속', _deptCtrl.text),
      MapEntry('성명', _nameCtrl.text),
      MapEntry('직책', _positionCtrl.text),
      MapEntry('일시', _fmtCompact(_eventDateTime!)),
    ];

    pw.Widget buildFieldTable() => pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
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
                child: pw.Text(
                  kv.key,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  kv.value,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
      ],
    );

    pw.Widget buildSection(String title, String body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey400,
              width: 0.5,
            ),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            body.isEmpty ? '-' : body,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );

    pw.Widget buildSignature() {
      final name = _signerName.isEmpty ? '이름 미입력' : _signerName;
      final timeText =
      _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(
            '전자서명',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '서명자: $name',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '서명 일시: $timeText',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 120,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: PdfColors.grey400,
                width: 0.5,
              ),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: _signaturePngBytes == null
                ? pw.Center(
              child: pw.Text(
                '서명 이미지 없음',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey,
                ),
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
              '경위서',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[내용(육하원칙 기반)]', _contentCtrl.text),
          buildSignature(),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '생성 시각: ${_fmtCompact(DateTime.now())}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ),
      ),
    );

    return doc.save();
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

    final boundary =
        'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
    final subjectB64 = base64.encode(utf8.encode(subject));

    final sb = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: =?utf-8?B?$subjectB64?=')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 7bit')
      ..writeln()
      ..writeln(body)
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: application/pdf; name="$filename"')
      ..writeln('Content-Disposition: attachment; filename="$filename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(base64.encode(pdfBytes))
      ..writeln('--$boundary--');

    final raw =
    base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  InputDecoration _inputDec({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: UserStatementColors.base,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 12,
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      color: Colors.white,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
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
    final result = await showGeneralDialog<UserStatementSignatureResult>(
      context: context,
      barrierLabel: '서명',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return UserStatementSignatureFullScreenDialog(
          name: _signerName,
          initialDateTime: _signDateTime,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      // 바깥 배경
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('경위서 작성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: UserStatementButtonStyles.smallPrimary(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black12, width: 1),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '제출',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: UserStatementButtonStyles.primary(),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 상단 문서 헤더
                          Text(
                            '경위서',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'STATEMENT FORM',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                              color: Colors.black54,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 실제 "종이" 느낌의 경위서 카드
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: UserStatementColors.light
                                    .withOpacity(0.8),
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
                            padding:
                            const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                              children: [
                                // 상단 메타 정보 라인
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.description_outlined,
                                      size: 22,
                                      color: UserStatementColors.dark,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '경위서 양식',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color:
                                        UserStatementColors.dark,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '작성일 ${_fmtCompact(DateTime.now())}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Divider(height: 24),
                                const SizedBox(height: 4),

                                // 안내 문구
                                Container(
                                  decoration: BoxDecoration(
                                    color: UserStatementColors.light
                                        .withOpacity(0.12),
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    border: Border.all(
                                      color: UserStatementColors.light
                                          .withOpacity(0.8),
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
                                        color: UserStatementColors.dark,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '사실에 근거해 간결하고 명확하게 작성해 주세요.\n'
                                              '육하원칙(누가, 언제, 어디서, 무엇을, 왜, 어떻게)에 따라 '
                                              '경위와 당시 상황을 구체적으로 작성하면 검토에 도움이 됩니다.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                _gap(20),

                                // 섹션 1. 기본 정보
                                _sectionCard(
                                  title: '1. 기본 정보',
                                  margin: const EdgeInsets.only(
                                      bottom: 16),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _deptCtrl,
                                              focusNode: _deptNode,
                                              decoration: _inputDec(
                                                labelText:
                                                '소속 (필수)',
                                                hintText:
                                                '예: 본사 IT본부',
                                              ),
                                              textInputAction:
                                              TextInputAction.next,
                                              onFieldSubmitted: (_) =>
                                                  _nameNode
                                                      .requestFocus(),
                                              validator: (v) => (v ==
                                                  null ||
                                                  v
                                                      .trim()
                                                      .isEmpty)
                                                  ? '소속을 입력하세요.'
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextFormField(
                                              controller: _nameCtrl,
                                              focusNode: _nameNode,
                                              decoration: _inputDec(
                                                labelText:
                                                '성명 (필수)',
                                                hintText: '예: 홍길동',
                                              ),
                                              textInputAction:
                                              TextInputAction.next,
                                              onFieldSubmitted: (_) =>
                                                  _positionNode
                                                      .requestFocus(),
                                              validator: (v) => (v ==
                                                  null ||
                                                  v
                                                      .trim()
                                                      .isEmpty)
                                                  ? '성명을 입력하세요.'
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      _gap(12),
                                      TextFormField(
                                        controller: _positionCtrl,
                                        focusNode: _positionNode,
                                        decoration: _inputDec(
                                          labelText: '직책 (필수)',
                                          hintText:
                                          '예: 매니저 / 대리 / 주임 등',
                                        ),
                                        textInputAction:
                                        TextInputAction.next,
                                        onFieldSubmitted: (_) =>
                                            FocusScope.of(context)
                                                .unfocus(),
                                        validator: (v) => (v == null ||
                                            v.trim().isEmpty)
                                            ? '직책을 입력하세요.'
                                            : null,
                                      ),
                                      _gap(12),
                                      InkWell(
                                        onTap: _pickDateTime,
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                            BorderRadius.circular(
                                                12),
                                            border: Border.all(
                                              color: Colors.grey,
                                            ),
                                          ),
                                          padding: const EdgeInsets
                                              .symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.event_outlined,
                                              ),
                                              const SizedBox(width: 10),
                                              const Text(
                                                '일시 (필수)',
                                                style: TextStyle(
                                                  fontWeight:
                                                  FontWeight.w600,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                _fmtDT(
                                                  context,
                                                  _eventDateTime,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 섹션 2. 사실 관계 (육하원칙)
                                _sectionCard(
                                  title:
                                  '2. 사실 관계 (육하원칙 기반, 필수)',
                                  margin: const EdgeInsets.only(
                                      bottom: 16),
                                  child: TextFormField(
                                    controller: _contentCtrl,
                                    focusNode: _contentNode,
                                    decoration: _inputDec(
                                      labelText: '내용',
                                      hintText:
                                      '누가/언제/어디서/무엇을/왜/어떻게 순으로 구체적으로 작성해 주세요.',
                                    ),
                                    keyboardType:
                                    TextInputType.multiline,
                                    minLines: 8,
                                    maxLines: 16,
                                    validator: (v) => (v == null ||
                                        v.trim().isEmpty)
                                        ? '내용을 입력하세요.'
                                        : null,
                                  ),
                                ),

                                // 섹션 3. 메일 전송 내용
                                _sectionCard(
                                  title: '3. 메일 전송 내용',
                                  margin: const EdgeInsets.only(
                                      bottom: 16),
                                  child: Column(
                                    children: [
                                      TextFormField(
                                        controller: _mailSubjectCtrl,
                                        decoration: _inputDec(
                                          labelText:
                                          '메일 제목(필수)',
                                          hintText:
                                          '예: 경위서 – ${DateTime.now().month}월 ${DateTime.now().day}일 건',
                                        ),
                                        textInputAction:
                                        TextInputAction.next,
                                        validator: (v) => (v == null ||
                                            v.trim().isEmpty)
                                            ? '메일 제목을 입력하세요.'
                                            : null,
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        controller: _mailBodyCtrl,
                                        decoration: _inputDec(
                                          labelText: '메일 본문',
                                          hintText:
                                          '메일 본문을 입력하세요. (선택)',
                                        ),
                                        minLines: 3,
                                        maxLines: 8,
                                      ),
                                    ],
                                  ),
                                ),

                                // 섹션 4. 전자서명
                                _sectionCard(
                                  title: '4. 전자서명',
                                  margin: const EdgeInsets.only(
                                      bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding:
                                        const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.black12,
                                          ),
                                          borderRadius:
                                          BorderRadius.circular(
                                              12),
                                        ),
                                        child: Wrap(
                                          spacing: 16,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize:
                                              MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.person_outline,
                                                  size: 18,
                                                ),
                                                const SizedBox(
                                                    width: 6),
                                                Text(
                                                  '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                                                  style:
                                                  const TextStyle(
                                                    fontWeight:
                                                    FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize:
                                              MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.access_time,
                                                  size: 18,
                                                ),
                                                const SizedBox(
                                                    width: 6),
                                                Text(
                                                  '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                                                  style:
                                                  const TextStyle(
                                                    color:
                                                    Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            ElevatedButton.icon(
                                              onPressed:
                                              _openSignatureDialog,
                                              icon: const Icon(
                                                Icons.border_color,
                                              ),
                                              label:
                                              const Text('서명하기'),
                                              style:
                                              UserStatementButtonStyles
                                                  .smallPrimary(),
                                            ),
                                            if (_signaturePngBytes !=
                                                null)
                                              OutlinedButton.icon(
                                                onPressed: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  setState(() {
                                                    _signaturePngBytes =
                                                    null;
                                                    _signDateTime =
                                                    null;
                                                  });
                                                },
                                                icon: const Icon(Icons
                                                    .delete_outline),
                                                label: const Text(
                                                    '서명 삭제'),
                                                style:
                                                UserStatementButtonStyles
                                                    .smallOutlined(),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (_signaturePngBytes != null)
                                        Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black12,
                                            ),
                                            borderRadius:
                                            BorderRadius.circular(
                                                12),
                                          ),
                                          padding:
                                          const EdgeInsets.all(8),
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
                                  ),
                                ),

                                _gap(12),

                                // 하단 보조 액션 (초기화 / 미리보기)
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed:
                                        _sending ? null : _reset,
                                        icon: const Icon(
                                            Icons.refresh_outlined),
                                        label: const Text('초기화'),
                                        style:
                                        UserStatementButtonStyles
                                            .outlined(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _sending
                                            ? null
                                            : _showPreview,
                                        icon: const Icon(Icons
                                            .visibility_outlined),
                                        label: const Text('미리보기'),
                                        style:
                                        UserStatementButtonStyles
                                            .primary(),
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
            },
          ),
        ),
      ),
    );
  }
}
