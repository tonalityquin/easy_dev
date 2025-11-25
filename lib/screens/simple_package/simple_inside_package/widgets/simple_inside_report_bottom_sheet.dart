// lib/screens/simple_package/simple_inside_package/widgets/simple_inside_report_bottom_sheet.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ✅ 1. 풀스크린 바텀시트를 여는 헬퍼 함수
///    - SimpleInsideReportButtonSection 에서 호출
void showSimpleInsideReportFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SimpleInsideReportFormPage(),
    ),
  );
}

/// ✅ 2. 실제 업무 보고 폼 페이지 (업무 종료 보고서 제출 포함)
class SimpleInsideReportFormPage extends StatefulWidget {
  const SimpleInsideReportFormPage({super.key});

  @override
  State<SimpleInsideReportFormPage> createState() =>
      _SimpleInsideReportFormPageState();
}

class _SimpleInsideReportFormPageState
    extends State<SimpleInsideReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 보고 유형 / 제목 / 내용 상태
  String _reportType = '업무 종료 보고';
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 기본값을 "업무 종료 보고"에 맞게 프리셋
    _titleController.text = '업무 종료 보고서';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// 실제 “업무 종료 보고서”를 서버/백엔드로 보내는 부분
  ///
  /// - true  → 전송 성공
  /// - false → 전송 실패
  ///
  /// TODO: 여기에 실제 API 호출/Firestore 기록 등을 붙이면 됩니다.
  Future<bool> _sendWorkEndReport() async {
    try {
      final type = _reportType;
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();

      // 🔹 여기에서 실제 전송 로직 수행
      // 예)
      // await WorkReportService.instance.sendEndOfWorkReport(
      //   type: type,
      //   title: title,
      //   content: content,
      // );
      //
      // 지금은 데모로 0.8초 딜레이 후 성공으로 가정
      await Future.delayed(const Duration(milliseconds: 800));

      debugPrint('[REPORT] type="$type", title="$title", len=${content.length}');
      return true;
    } catch (e, st) {
      debugPrint('[REPORT] sendWorkEndReport error: $e');
      debugPrint(st.toString());
      return false;
    }
  }

  /// “업무 종료 보고서 제출” 버튼을 눌렀을 때 로직
  ///
  /// - 검증 통과 → _sendWorkEndReport()
  /// - 성공하면: 앱 종료
  /// - 실패하면: 앱은 그대로 두고, 다른 방법을 안내
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _submitting = true);

    try {
      final success = await _sendWorkEndReport();
      if (!mounted) return;

      if (success) {
        // 🔹 전송 성공 → 앱 종료
        //    (원하시면 종료 직전에 SnackBar/Toast를 잠깐 보여줄 수도 있지만
        //     대부분 바로 종료하길 원하셔서 즉시 종료로 처리)
        if (Platform.isAndroid) {
          // 안드로이드: 홈으로 나가며 앱 프로세스 종료 방향
          await SystemNavigator.pop();
        } else {
          // iOS 에서는 공식적으로 권장되진 않지만,
          // 요구사항상 “앱을 끄는 것”이므로 강제 종료
          exit(0);
        }
      } else {
        // 🔹 전송 실패 → 앱은 그대로 두고, 다른 방법 안내
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '업무 종료 보고서 전송에 실패했습니다.\n'
                  '네트워크 상태를 확인 후 다시 시도하시거나,\n'
                  '전화/메신저 등 다른 방법으로 보고해 주세요.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            // 상단 앱바 영역
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '업무 종료 보고서',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // 🔹 “업무 종료 보고서 제출” 버튼
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text(
                      '업무 종료 보고서 제출',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 폼 영역
            Expanded(
              child: SingleChildScrollView(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 보고 유형 선택 (원하시면 고정해도 됨)
                      Text(
                        '보고 유형',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _reportType,
                        items: const [
                          DropdownMenuItem(
                            value: '업무 종료 보고',
                            child: Text('업무 종료 보고'),
                          ),
                          DropdownMenuItem(
                            value: '일반 업무 보고',
                            child: Text('일반 업무 보고'),
                          ),
                          DropdownMenuItem(
                            value: '이상/사고 보고',
                            child: Text('이상/사고 보고'),
                          ),
                          DropdownMenuItem(
                            value: '기타',
                            child: Text('기타'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _reportType = v);
                          }
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 제목
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(),
                          hintText: '예: 2월 27일 야간 근무 종료 보고',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return '제목을 입력해주세요.';
                          }
                          if (v.trim().length < 3) {
                            return '제목을 3자 이상 입력해주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 내용
                      TextFormField(
                        controller: _contentController,
                        decoration: const InputDecoration(
                          labelText: '보고 내용',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          hintText:
                          '오늘 근무 시간, 처리한 업무, 특이사항 등을 간단히 정리해주세요.',
                        ),
                        minLines: 8,
                        maxLines: 16,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return '내용을 입력해주세요.';
                          }
                          if (v.trim().length < 10) {
                            return '내용을 조금 더 자세히 입력해주세요. (10자 이상)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // 안내 텍스트
                      Text(
                        '※ 업무 종료 보고서가 정상적으로 전송되면 앱이 자동으로 종료됩니다.\n'
                            '※ 전송 실패 시 앱은 계속 유지되며, 다른 방법으로 보고하시도록 안내가 표시됩니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
