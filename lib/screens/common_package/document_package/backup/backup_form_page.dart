import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../utils/google_auth_v7.dart';
import '../../../../../../utils/api/email_config.dart';

import '../../../hubs_mode/dev_package/debug_package/debug_api_logger.dart';
import '../../../hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';
import 'backup_styles.dart';
import 'backup_signature_dialog.dart';

/// 계약 형태
enum ContractType {
  contract, // 계약직
  freelancer, // 프리랜서
}

class BackupFormPage extends StatefulWidget {
  const BackupFormPage({super.key});

  @override
  State<BackupFormPage> createState() => _BackupFormPageState();
}

class _BackupFormPageState extends State<BackupFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 기본 정보 컨트롤러
  final _nameCtrl = TextEditingController();
  final _rrnCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  // 3번 카드: 괄호 안 입력용 컨트롤러
  final _reasonCtrl = TextEditingController(); // 첫 번째 괄호
  final _targetCtrl = TextEditingController(); // 두 번째 괄호
  final _timeCtrl = TextEditingController(); // 세 번째 괄호 (시간대)
  final _processCtrl = TextEditingController(); // 네 번째 괄호 (처리 방식)

  // 메일 제목/본문 컨트롤러
  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  // 포커스 노드
  final _nameNode = FocusNode();
  final _rrnNode = FocusNode();
  final _positionNode = FocusNode();
  final _deptNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  // 계약 형태: null = 미선택
  ContractType? _contractType;

  // SharedPreferences에서 불러오는 선택 영역 (업무명)
  String? _selectedArea;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false;

  // 페이지 컨트롤러 (섹션별 좌우 스와이프)
  final PageController _pageController = PageController();

  // 현재 페이지 인덱스 (0~4)
  int _currentPageIndex = 0;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────

  // DebugBottomSheet에서 tag로 즉시 필터링 가능하도록 "/" 기반 네임스페이스 사용
  static const String _tBackup = 'backup';
  static const String _tBackupForm = 'backup/form';
  static const String _tBackupPdf = 'backup/pdf';
  static const String _tBackupEmail = 'backup/email';
  static const String _tBackupPrefs = 'backup/prefs';
  static const String _tGmail = 'gmail/send';

  static const int _mimeB64LineLength = 76;

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
    } catch (_) {
      // 로깅 실패는 UX에 영향 없도록 무시
    }
  }

  // (선택) 이 페이지에서 DebugBottomSheet 즉시 오픈
  Future<void> _openDebugBottomSheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DebugBottomSheet(),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _updateMailBody(); // 메일 본문 자동 생성
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      if (!mounted) return;
      setState(() {
        _selectedArea = area.isEmpty ? null : area;
      });

      // 사용자가 아직 제목을 입력하지 않은 경우에만 자동 채움
      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    } catch (e) {
      await _logApiError(
        tag: 'BackupFormPage._loadSelectedArea',
        message: 'SharedPreferences에서 selectedArea 로드 실패',
        error: e,
        tags: const <String>[_tBackupPrefs, _tBackup],
      );
      if (!mounted) return;
      setState(() {
        _selectedArea = null;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rrnCtrl.dispose();
    _positionCtrl.dispose();
    _deptCtrl.dispose();

    _reasonCtrl.dispose();
    _targetCtrl.dispose();
    _timeCtrl.dispose();
    _processCtrl.dispose();

    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _nameNode.dispose();
    _rrnNode.dispose();
    _positionNode.dispose();
    _deptNode.dispose();

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

  String _contractTypeText(ContractType? value) {
    if (value == null) return '미선택';
    switch (value) {
      case ContractType.contract:
        return '계약직';
      case ContractType.freelancer:
        return '프리랜서';
    }
  }

  /// 3번 카드: 괄호 4개를 합쳐 실제 문장을 만들어주는 함수
  String _buildBodySentence() {
    final reason = _reasonCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    final time = _timeCtrl.text.trim();
    final process = _processCtrl.text.trim();

    return '$reason으로 인해 $target의 $time 시간 대의 업무에 공백이 발생했습니다. '
        '본 문서를 통해 해당 공백에 대한 인적 지원을 받고자 하오며 향후 이에 대해서는 $process로 처리됨을 인지합니다.';
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _formKey.currentState?.reset();

    _nameCtrl.clear();
    _rrnCtrl.clear();
    _positionCtrl.clear();
    _deptCtrl.clear();

    _reasonCtrl.clear();
    _targetCtrl.clear();
    _timeCtrl.clear();
    _processCtrl.clear();

    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();

    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _contractType = null;
      _currentPageIndex = 0;
    });

    _updateMailSubject();
    _updateMailBody(force: true);

    _pageController.jumpToPage(0);
  }

  /// 계약 형태 + SharedPreferences 선택 영역에 따라 메일 제목 자동 생성
  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixType = '';
    if (_contractType != null) {
      suffixType = ' - ${_contractTypeText(_contractType)}';
    }

    final area = (_selectedArea != null && _selectedArea!.trim().isNotEmpty)
        ? _selectedArea!.trim()
        : '업무';

    _mailSubjectCtrl.text = '$area 연차(결근) 지원 신청서 – ${month}월 ${day}일자$suffixType';
  }

  /// 메일 본문 자동 생성 (작성 일시 포함)
  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text =
    '본 신청서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 연차(결근) 지원 신청서입니다.';
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final contractText = _contractTypeText(_contractType);
    final name = _nameCtrl.text.trim().isEmpty ? '(성명 미입력)' : _nameCtrl.text.trim();
    final rrn = _rrnCtrl.text.trim().isEmpty ? '(주민등록번호 미입력)' : _rrnCtrl.text.trim();
    final position = _positionCtrl.text.trim().isEmpty ? '(직위 미입력)' : _positionCtrl.text.trim();
    final dept = _deptCtrl.text.trim().isEmpty ? '(부서명 미입력)' : _deptCtrl.text.trim();

    final bodySentence = _buildBodySentence();

    return [
      '— 연차(결근) 지원 신청서 —',
      '',
      '계약 형태: $contractText',
      '성명: $name',
      '주민등록번호: $rrn',
      '직위: $position',
      '부서명: $dept',
      '',
      '[업무 공백 및 인력 지원 요청]',
      bodySentence,
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

    final contractText = _contractTypeText(_contractType);
    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);
    final createdAtText = _fmtDT(context, DateTime.now());
    final bodySentence = _buildBodySentence();

    Widget _infoPill(ColorScheme cs, IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
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
        final cs = theme.colorScheme;

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
                      color: cs.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: BoxDecoration(
                              color: cs.primary,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  color: cs.onPrimary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '연차(결근) 지원 신청서 미리보기',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: cs.onPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 신청서 내용을 한 번 더 확인해 주세요.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onPrimary.withOpacity(0.82),
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
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _infoPill(cs, Icons.calendar_today_outlined, '작성일', createdAtText),
                                        _infoPill(cs, Icons.work_outline, '계약 형태', contractText),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // 메일 정보
                                    Container(
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.email_outlined, size: 18, color: cs.primary),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Divider(height: 20, color: cs.outlineVariant.withOpacity(0.9)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '제목',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: cs.surface,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 문장
                                    Container(
                                      decoration: BoxDecoration(
                                        color: cs.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.description_outlined, size: 18, color: cs.primary),
                                              const SizedBox(width: 6),
                                              Text(
                                                '업무 공백 및 인력 지원 문장',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Divider(height: 20, color: cs.outlineVariant.withOpacity(0.9)),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerLow,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                                            ),
                                            child: Text(
                                              bodySentence.trim().isEmpty ? '입력된 문장이 없습니다.' : bodySentence,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                height: 1.4,
                                                color: bodySentence.trim().isEmpty
                                                    ? cs.onSurfaceVariant
                                                    : cs.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 서명
                                    Container(
                                      decoration: BoxDecoration(
                                        color: cs.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.edit_outlined, size: 18, color: cs.primary),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Divider(height: 20, color: cs.outlineVariant.withOpacity(0.9)),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명자',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: cs.onSurfaceVariant,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signName,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                        color: cs.onSurface,
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
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: cs.onSurfaceVariant,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signTimeText,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                        color: cs.onSurface,
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
                                              border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                                              color: cs.surfaceContainerLow,
                                            ),
                                            child: _signaturePngBytes == null
                                                ? Center(
                                              child: Text(
                                                '서명 이미지가 없습니다. (전자서명 완료 후 제출할 수 있습니다.)',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
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

                                    // 안내
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer.withOpacity(0.45),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline, size: 18, color: cs.primary),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 '
                                                  '텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: cs.onSurface,
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
                                top: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                              ),
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
    // 1) 폼 필드 검증
    if (!_formKey.currentState!.validate()) return;

    // 2) 계약 형태 필수 선택
    if (_contractType == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계약 형태(계약직/프리랜서)를 선택해 주세요.')),
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

      // 제출 시점 기준으로 본문 시간 강제 갱신
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목이 자동 생성되지 않았습니다.')),
        );
        return;
      }

      final pdfBytes = await _buildPdfBytes();

      final now = DateTime.now();
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('연차결근지원신청서_${nameForFile}_${_dateTag(now)}');

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
      await _logApiError(
        tag: 'BackupFormPage._submit',
        message: '메일 전송(제출) 실패',
        error: e,
        extra: <String, dynamic>{
          'contractType': _contractTypeText(_contractType),
          'hasSignature': _signaturePngBytes != null,
          'pdfBytes': null, // 민감정보 방지
          'subjectLen': _mailSubjectCtrl.text.trim().length,
          'bodyLen': _mailBodyCtrl.text.trim().length,
        },
        tags: const <String>[_tBackupForm, _tBackup, _tBackupEmail, _tGmail],
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
    final s = raw.trim().isEmpty ? '연차결근지원신청서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ PDF 생성: 실패 시 DebugApiLogger 기록
  // ─────────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdfBytes() async {
    try {
      pw.Font? regular;
      pw.Font? bold;

      try {
        final regData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
        regular = pw.Font.ttf(regData);
      } catch (_) {}

      try {
        final boldData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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

      final contractText = _contractTypeText(_contractType);
      final name = _nameCtrl.text.trim().isEmpty ? '-' : _nameCtrl.text.trim();
      final rrn = _rrnCtrl.text.trim().isEmpty ? '-' : _rrnCtrl.text.trim();
      final position = _positionCtrl.text.trim().isEmpty ? '-' : _positionCtrl.text.trim();
      final dept = _deptCtrl.text.trim().isEmpty ? '-' : _deptCtrl.text.trim();
      final bodySentence = _buildBodySentence();

      final fields = <MapEntry<String, String>>[
        MapEntry('계약 형태', contractText),
        MapEntry('성명', name),
        MapEntry('주민등록번호', rrn),
        MapEntry('직위', position),
        MapEntry('부서명', dept),
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
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
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
        final timeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

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
                  child: pw.Text('서명자: $name', style: const pw.TextStyle(fontSize: 11)),
                ),
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
                '연차(결근) 지원 신청서',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[업무 공백 및 인력 지원 요청]', bodySentence),
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

      final bytes = await doc.save();
      return bytes;
    } catch (e) {
      await _logApiError(
        tag: 'BackupFormPage._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'contractType': _contractTypeText(_contractType),
          'hasSignature': _signaturePngBytes != null,
          'nameLen': _nameCtrl.text.trim().length,
          'rrnLen': _rrnCtrl.text.trim().length, // 원문은 기록하지 않음
        },
        tags: const <String>[_tBackupPdf, _tBackup, _tBackupForm],
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Gmail MIME 생성 유틸
  // ─────────────────────────────────────────────────────────────

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    final subjectB64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$subjectB64?=';
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    try {
      final api = gmail.GmailApi(client);

      final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
      const crlf = '\r\n';

      final pdfB64Wrapped = _wrapBase64Lines(base64.encode(pdfBytes));

      final mime = StringBuffer()
        ..write('To: $to$crlf')
        ..write('Subject: ${_encodeSubjectRfc2047(subject)}$crlf')
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
        ..write(pdfB64Wrapped)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(mime.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;

      await api.users.messages.send(msg, 'me');
    } catch (e) {
      await _logApiError(
        tag: 'BackupFormPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
        },
        tags: const <String>[_tBackupEmail, _tBackup, _tGmail],
      );
      rethrow;
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  InputDecoration _inputDec({
    required String labelText,
    String? hintText,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      // ✅ 다크모드에서 white 고정 금지 → container 계열 사용
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
        borderSide: BorderSide(
          color: cs.primary,
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
      ),
      color: cs.surface,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
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
    try {
      final cs = Theme.of(context).colorScheme;

      final result = await showGeneralDialog<SignatureResult>(
        context: context,
        barrierLabel: '서명',
        barrierDismissible: false,
        // ✅ 다크/라이트 일관된 scrim
        barrierColor: cs.scrim.withOpacity(0.55),
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return SignatureFullScreenDialog(
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
    } catch (e) {
      await _logApiError(
        tag: 'BackupFormPage._openSignatureDialog',
        message: '전자서명 다이얼로그 처리 실패',
        error: e,
        tags: const <String>[_tBackupForm, _tBackup],
      );
      rethrow;
    }
  }

  // ===== 섹션별 본문 위젯들 =====

  Widget _buildContractTypeBody() {
    final cs = Theme.of(context).colorScheme;

    Widget buildChoice(ContractType type, String label) {
      final selected = _contractType == type;

      if (selected) {
        return ElevatedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _contractType = type;
              _updateMailSubject();
            });
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          style: BackupButtonStyles.primary(context),
          child: Text(label),
        );
      }

      return OutlinedButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          setState(() {
            _contractType = type;
            _updateMailSubject();
          });
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        },
        style: BackupButtonStyles.outlined(context),
        child: Text(label, style: TextStyle(color: cs.onSurface)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '지원 신청자의 계약 형태를 선택해 주세요.\n'
              '계약직 또는 프리랜서 중 하나를 선택합니다.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: buildChoice(ContractType.contract, '계약직')),
            const SizedBox(width: 12),
            Expanded(child: buildChoice(ContractType.freelancer, '프리랜서')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildBasicInfoBody() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '성명, 주민등록번호, 직위, 부서명을 입력해 주세요.\n'
              '입력한 정보는 PDF 신청서 및 메일 본문에 함께 포함됩니다.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nameCtrl,
          focusNode: _nameNode,
          decoration: _inputDec(
            labelText: '성명 (필수)',
            hintText: '예: 홍길동',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '성명을 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _rrnCtrl,
          focusNode: _rrnNode,
          decoration: _inputDec(
            labelText: '주민등록번호 (필수)',
            hintText: '예: 900101-1******',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '주민등록번호를 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _positionCtrl,
          focusNode: _positionNode,
          decoration: _inputDec(
            labelText: '직위 (필수)',
            hintText: '예: 매니저, 사원',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '직위를 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _deptCtrl,
          focusNode: _deptNode,
          decoration: _inputDec(
            labelText: '부서명 (필수)',
            hintText: '예: 콜센터팀, 운영팀',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '부서명을 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 6),
        Text(
          '※ 위 정보는 인사/관리 부서에서 근태 및 지원 내역 확인 시 참고됩니다.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildBlankSentenceBody() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sentencePreview = _buildBodySentence();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '다음 고정 문장을 기준으로 괄호 안의 내용만 입력해 주세요.\n'
              '문장 구조(조사, 어미 등)는 수정할 수 없고, 괄호 안 텍스트만 변경 가능합니다.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
          ),
          child: Text(
            '(①   )으로 인해 (②    )의 (③   ) 시간 대의 업무에 공백이 발생했습니다. '
                '본 문서를 통해 해당 공백에 대한 인적 지원을 받고자 하오며 향후 이에 대해서는 (④    )로 처리됨을 인지합니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reasonCtrl,
          decoration: _inputDec(
            labelText: '① (   ) 에 들어갈 내용 (필수)',
            hintText: '예: 개인 사정, 병원 진료, 고객사 교육 등',
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v == null || v.trim().isEmpty) ? '첫 번째 괄호의 내용을 입력해 주세요.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _targetCtrl,
          decoration: _inputDec(
            labelText: '② (    ) 에 들어갈 내용 (필수)',
            hintText: '예: 2025년 11월 26일, 11월 3주차, 주간 야간근무 등',
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v == null || v.trim().isEmpty) ? '두 번째 괄호의 내용을 입력해 주세요.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _timeCtrl,
          decoration: _inputDec(
            labelText: '③ (   ) 시간대에 들어갈 내용 (필수)',
            hintText: '예: 09:00~18:00, 야간, 오전, 오후 등',
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v == null || v.trim().isEmpty) ? '세 번째 괄호의 내용을 입력해 주세요.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _processCtrl,
          decoration: _inputDec(
            labelText: '④ (    ) 로 처리됨을 에 들어갈 내용 (필수)',
            hintText: '예: 연차, 결근, 반차 등',
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v == null || v.trim().isEmpty) ? '네 번째 괄호의 내용을 입력해 주세요.' : null,
        ),
        const SizedBox(height: 12),
        Text(
          '실제 문장 미리보기',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
          ),
          child: Text(
            sentencePreview,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '※ 이 미리보기 문장은 위 4개 필드의 값으로만 구성되며, 문장 구조는 수정되지 않습니다.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
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
            labelText: '메일 제목(자동 생성)',
            hintText: '예: 콜센터 연차(결근) 지원 신청서 – 11월 25일자 - 계약직',
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 본문(자동 생성)',
            hintText: '연차(결근) 신청 일시 정보가 자동으로 입력됩니다.',
          ),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  Widget _buildSignatureBody() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                    style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface),
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
                    style: TextStyle(color: cs.onSurface),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openSignatureDialog,
                icon: const Icon(Icons.border_color),
                label: const Text('서명하기'),
                style: BackupButtonStyles.smallPrimary(context),
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
                  style: BackupButtonStyles.smallOutlined(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_signaturePngBytes != null)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerLow,
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

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
                  '연차(결근) 지원 신청서',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'LEAVE / ABSENCE APPLICATION',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.9),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '연차(결근) 지원 신청서 양식',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 24, color: cs.outlineVariant.withOpacity(0.9)),
                      const SizedBox(height: 4),

                      Container(
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '계약 형태, 신청자 정보, 업무 공백 사유 및 전자서명 정보를 사실에 근거하여 간결하게 작성해 주세요.\n'
                                    '문제 발생 시 상단의 “버그” 버튼에서 API 디버그 로그를 확인할 수 있습니다.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  height: 1.4,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      _gap(20),

                      _sectionCard(
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
                              style: BackupButtonStyles.outlined(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: BackupButtonStyles.primary(context),
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
      // ✅ 하드코딩 배경 제거 → scheme 기반
      backgroundColor: cs.background,
      appBar: AppBar(
        title: const Text('연차(결근) 지원 신청서 작성'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.9), width: 1),
        ),
        actions: [
          IconButton(
            tooltip: 'API 디버그',
            onPressed: _openDebugBottomSheet,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: BackupButtonStyles.smallPrimary(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _currentPageIndex == 4
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
              top: BorderSide(color: cs.outlineVariant.withOpacity(0.9), width: 1),
            ),
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
              style: BackupButtonStyles.primary(context),
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
                  _contractType = null;
                  _updateMailSubject();
                }
              });
            },
            children: [
              _buildReportPage(
                sectionTitle: '1. 계약 형태 선택 (계약직/프리랜서, 필수)',
                sectionBody: _buildContractTypeBody(),
              ),
              _buildReportPage(
                sectionTitle: '2. 신청자 기본 정보 (성명/주민번호/직위/부서명, 필수)',
                sectionBody: _buildBasicInfoBody(),
              ),
              _buildReportPage(
                sectionTitle: '3. 업무 공백 및 인력 지원 문장 (괄호 입력)',
                sectionBody: _buildBlankSentenceBody(),
              ),
              _buildReportPage(
                sectionTitle: '4. 메일 전송 내용',
                sectionBody: _buildMailBody(),
              ),
              _buildReportPage(
                sectionTitle: '5. 전자서명',
                sectionBody: _buildSignatureBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
