import 'dart:convert';
import 'dart:io';
import 'dart:math'; // ✅ 고유 ID 생성을 위해 추가

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../repositories/plate/plate_count_service.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

class EndWorkReportContent extends StatefulWidget {
  final Future<void> Function(String reportType, String content) onReport;

  // ✅ 입차/출차 차량 수 초기값
  final int? initialVehicleInput; // 입차: parking_completed 전체
  final int? initialVehicleOutput; // 출차: departure_completed && isLockedFee 전체

  const EndWorkReportContent({
    super.key,
    required this.onReport,
    this.initialVehicleInput,
    this.initialVehicleOutput,
  });

  @override
  State<EndWorkReportContent> createState() => _EndWorkReportContentState();
}

class _EndWorkReportContentState extends State<EndWorkReportContent> {
  final _formKey = GlobalKey<FormState>();
  final _inputCtrl = TextEditingController(); // 입차
  final _outputCtrl = TextEditingController(); // 출차
  final _inputFocus = FocusNode();
  final _outputFocus = FocusNode();

  bool _submitting = false;
  bool _reloadingInput = false;
  bool _reloadingOutput = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialVehicleInput != null) {
      _inputCtrl.text = widget.initialVehicleInput.toString();
    }
    if (widget.initialVehicleOutput != null) {
      _outputCtrl.text = widget.initialVehicleOutput.toString();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    _inputFocus.dispose();
    _outputFocus.dispose();
    super.dispose();
  }

  Future<void> _refetchInput() async {
    final area = context.read<AreaState>().currentArea;
    setState(() => _reloadingInput = true);
    try {
      final v = await PlateCountService().getParkingCompletedCountAll(area);
      _inputCtrl.text = v.toString();
      HapticFeedback.selectionClick();
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _reloadingInput = false);
    }
  }

  Future<void> _refetchOutput() async {
    final area = context.read<AreaState>().currentArea;
    setState(() => _reloadingOutput = true);
    try {
      final v = await PlateCountService().getLockedDepartureCountAll(area);
      _outputCtrl.text = v.toString();
      HapticFeedback.selectionClick();
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _reloadingOutput = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = context.watch<AreaState>().currentArea;
    final division = context.watch<AreaState>().currentDivision;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag Handle + Close ──────────────────────────────
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 6, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              const Text('업무 종료 보고', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 메타 정보 Chip (정렬/스타일 개선)
          Center(
            child: ChipTheme(
              data: ChipTheme.of(context).copyWith(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                labelStyle: const TextStyle(fontSize: 13),
                shape: StadiumBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.center, // 중앙 정렬
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(Icons.place, area.isEmpty ? '지역 미지정' : area),
                  _infoChip(Icons.domain, division.isEmpty ? '부서 미지정' : division),
                  if (widget.initialVehicleInput != null || widget.initialVehicleOutput != null)
                    _infoChip(Icons.auto_awesome, '자동 채움 완료', color: Colors.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 입력 폼 ───────────────────────────────────────────
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _LabeledNumberField(
                        label: '입차 차량 수',
                        controller: _inputCtrl,
                        focusNode: _inputFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_outputFocus),
                        validator: _numberValidator,
                        suffix: _reloadingInput
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : IconButton(
                          tooltip: '입차 수 재계산',
                          icon: const Icon(Icons.refresh),
                          onPressed: _refetchInput,
                        ),
                        helper: '현재 지역의 parking_completed 전체 문서 기준 자동 집계',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledNumberField(
                        label: '출차 차량 수',
                        controller: _outputCtrl,
                        focusNode: _outputFocus,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                        validator: _numberValidator,
                        suffix: _reloadingOutput
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : IconButton(
                          tooltip: '출차 수 재계산',
                          icon: const Icon(Icons.refresh),
                          onPressed: _refetchOutput,
                        ),
                        helper: '현재 지역의 departure_completed & 잠금요금(true) 전체 문서 기준',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 제출 버튼
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _submitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.send),
                    label: Text(_submitting ? '제출 중…' : '제출'),
                    onPressed: _submitting
                        ? null
                        : () async {
                      if (!(_formKey.currentState?.validate() ?? false)) {
                        HapticFeedback.lightImpact();
                        return;
                      }
                      await _handleSubmit();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 칩 렌더 헬퍼
  Widget _infoChip(IconData icon, String text, {Color? color}) {
    final Color base = color ?? Colors.black87;
    return Chip(
      avatar: Icon(icon, size: 16, color: base),
      label: Text(text),
      labelStyle: TextStyle(color: base),
      backgroundColor: color == null ? null : base.withOpacity(0.08),
      side: BorderSide(color: (color ?? Colors.grey).withOpacity(0.35)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return '값을 입력하세요';
    final ok = RegExp(r'^\d+$').hasMatch(v.trim());
    if (!ok) return '숫자만 입력 가능합니다';
    return null;
  }

  Future<void> _handleSubmit() async {
    setState(() => _submitting = true);
    try {
      final user = Provider.of<UserState>(context, listen: false).user;
      final division = user?.divisions.first;
      final area = context.read<AreaState>().currentArea;

      if (division == null || area.isEmpty) return;

      final entry = int.tryParse(_inputCtrl.text.trim());
      final exit = int.tryParse(_outputCtrl.text.trim());

      if (entry == null || exit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차/출차 차량 수는 숫자만 입력 가능합니다.')),
        );
        return;
      }

      // 전체 누적 요약 갱신
      final summaryRef = FirebaseFirestore.instance.collection('fee_summaries').doc('${division}_${area}_all');

      await updateLockedFeeSummary(division, area);

      final summary = await summaryRef.get();
      final data = summary.data();
      final lockedFee = (data?['totalLockedFee'] ?? 0) is num ? (data?['totalLockedFee'] as num).round() : 0;

      final reportMap = {
        "vehicleInput": entry,
        "vehicleOutput": exit,
        "totalLockedFee": lockedFee,
      };

      await widget.onReport('end', jsonEncode(reportMap));
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widget: 라벨 + 숫자 필드 + 보조문구 + suffix (재계산 버튼/로딩)
// ─────────────────────────────────────────────────────────────────────────────
class _LabeledNumberField extends StatelessWidget {
  const _LabeledNumberField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.textInputAction,
    required this.onFieldSubmitted,
    required this.validator,
    required this.helper,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputAction textInputAction;
  final void Function(String) onFieldSubmitted;
  final String? Function(String?) validator;
  final String helper;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 집계/업로드 관련 유틸
// ─────────────────────────────────────────────────────────────────────────────

Future<void> updateLockedFeeSummary(String division, String area) async {
  final firestore = FirebaseFirestore.instance;

  final snapshot = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  int total = 0;
  int count = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final fee = _extractLockedFeeAmount(data);
    total += fee;
    count++;
  }

  final summaryRef = firestore.collection('fee_summaries').doc('${division}_${area}_all');

  await summaryRef.set({
    'division': division,
    'area': area,
    'scope': 'all',
    'totalLockedFee': total,
    'lockedVehicleCount': count,
    'lastUpdated': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

int _extractLockedFeeAmount(Map<String, dynamic> data) {
  final top = data['lockedFeeAmount'];
  if (top is num) return top.round();

  final logs = data['logs'];
  if (logs is List) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final item = logs[i];
      if (item is Map<String, dynamic>) {
        final lf = item['lockedFee'];
        if (lf is num) return lf.round();
      }
    }
  }
  return 0;
}

// ✅ 랜덤 ID 생성 헬퍼 (영문소문자+숫자)
String _randomId([int length = 10]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rnd = Random.secure();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

// GCS 업로드
Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;

  // ✅ 파일명 앞에 고유 번호(prefix) 부여 → 캐시/덮어쓰기 이슈 방지
  final uid = _randomId(10);
  final fileName = '${uid}_ToDoReports_$dateStr.json';
  final destinationPath = '$division/$area/reports/$fileName';

  report['timestamp'] = dateStr;
  final jsonString = jsonEncode(report);

  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final client = await clientViaServiceAccount(
    accountCredentials,
    [StorageApi.devstorageFullControlScope],
  );
  final storage = StorageApi(client);

  final media = Media(
    tempFile.openRead(),
    tempFile.lengthSync(),
    contentType: 'application/json',
  );

  final object = await storage.objects.insert(
    Object()
      ..name = destinationPath
      ..contentDisposition = 'attachment'
    // (선택) 캐시 억제 필요 시 주석 해제
    // ..cacheControl = 'no-cache, no-store, max-age=0, must-revalidate'
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();
  // (선택) 임시 파일 삭제: await tempFile.delete();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}

Future<String?> uploadEndLogJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;

  // ✅ 파일명 앞에 고유 번호(prefix) 부여 → 캐시/덮어쓰기 이슈 방지
  final uid = _randomId(10);
  final fileName = '${uid}_ToDoLogs_$dateStr.json';
  final destinationPath = '$division/$area/logs/$fileName';

  report['timestamp'] = dateStr;
  final jsonString = jsonEncode(report);

  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final client = await clientViaServiceAccount(
    accountCredentials,
    [StorageApi.devstorageFullControlScope],
  );
  final storage = StorageApi(client);

  final media = Media(
    tempFile.openRead(),
    tempFile.lengthSync(),
    contentType: 'application/json',
  );

  final object = await storage.objects.insert(
    Object()
      ..name = destinationPath
      ..contentDisposition = 'attachment'
    // (선택) 캐시 억제 필요 시 주석 해제
    // ..cacheControl = 'no-cache, no-store, max-age=0, must-revalidate'
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();
  // (선택) 임시 파일 삭제: await tempFile.delete();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}
