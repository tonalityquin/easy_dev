// lib/screens/.../home_end_work_report_content.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../utils/snackbar_helper.dart';
// ✅ UsageReporter — 파이어베이스 발생 로직만 계측(READ/WRITE/DELETE)
import '../../../../../../utils/usage_reporter.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// ── Palette (Deep Blue)
const kBase = Color(0xFF0D47A1); // primary
const kDark = Color(0xFF09367D); // 강조 텍스트/아이콘
const kLight = Color(0xFF5472D3); // 톤 변형/보더
const kFg = Color(0xFFFFFFFF); // onPrimary

/// ─────────────────────────────────────────────────────────────────────────
Future<void> showEndWorkReportBottomSheet({
  required BuildContext context,
  required Future<void> Function(String reportType, String content) onReport,
  int? initialVehicleInput,
  int? initialVehicleOutput,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return FractionallySizedBox(
        heightFactor: 1,
        child: _SheetScaffold(
          childBuilder: (scrollController) => HomeEndWorkReportContent(
            onReport: onReport,
            initialVehicleInput: initialVehicleInput,
            initialVehicleOutput: initialVehicleOutput,
            externalScrollController: scrollController,
          ),
        ),
      );
    },
  );
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.childBuilder});

  final Widget Function(ScrollController) childBuilder;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();

    return SafeArea(
      top: false,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: kLight.withOpacity(.35)),
          boxShadow: [
            BoxShadow(
              color: kBase.withOpacity(.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: childBuilder(scrollController),
      ),
    );
  }
}

class HomeEndWorkReportContent extends StatefulWidget {
  final Future<void> Function(String reportType, String content) onReport;
  final int? initialVehicleInput; // 입차
  final int? initialVehicleOutput; // 출차
  final ScrollController? externalScrollController;

  const HomeEndWorkReportContent({
    super.key,
    required this.onReport,
    this.initialVehicleInput,
    this.initialVehicleOutput,
    this.externalScrollController,
  });

  @override
  State<HomeEndWorkReportContent> createState() => _HomeEndWorkReportContentState();
}

class _HomeEndWorkReportContentState extends State<HomeEndWorkReportContent> {
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
    if (!mounted) return;
    setState(() => _reloadingInput = true);
    try {
      final v = await PlateCountService().getParkingCompletedCountAll(area);

      // ⛑️ 언마운트되었으면 UI 업데이트 중단
      if (!mounted) return;

      _inputCtrl.text = v.toString();

      // 🔎 UI 레이어는 흔적만 남김(카운트 증가 X)
      try {
        await UsageReporter.instance.annotate(
          area: area,
          source: 'HomeEndWorkReportContent._refetchInput.parking_completed.aggregate',
          extra: {'value': v},
        );
      } catch (_) {}

      if (!mounted) return;
      HapticFeedback.selectionClick();
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _reloadingInput = false);
    }
  }

  Future<void> _refetchOutput() async {
    final area = context.read<AreaState>().currentArea;
    if (!mounted) return;
    setState(() => _reloadingOutput = true);
    try {
      final v = await PlateCountService().getDepartureCompletedCountAll(area);

      // ⛑️ 언마운트되었으면 UI 업데이트 중단
      if (!mounted) return;

      _outputCtrl.text = v.toString();

      // 🔎 UI 레이어는 흔적만 남김(카운트 증가 X)
      try {
        await UsageReporter.instance.annotate(
          area: area,
          source: 'HomeEndWorkReportContent._refetchOutput.departure_completed.aggregate',
          extra: {'value': v},
        );
      } catch (_) {}

      if (!mounted) return;
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

    final bottomPad = MediaQuery.of(context).viewInsets.bottom + 16;

    return SingleChildScrollView(
      controller: widget.externalScrollController,
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle + Close
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 6, bottom: 12),
            decoration: BoxDecoration(
              color: kLight.withOpacity(.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Text(
                '업무 종료 보고',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                    .copyWith(color: kDark),
              ),
              const Spacer(),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                color: kDark,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 메타 정보 Chip
          Center(
            child: ChipTheme(
              data: ChipTheme.of(context).copyWith(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                shape: StadiumBorder(side: BorderSide(color: kLight.withOpacity(.35))),
                backgroundColor: kLight.withOpacity(.06),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
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

          // 입력 폼
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(kBase),
                          ),
                        )
                            : IconButton(
                          tooltip: '입차 수 재계산',
                          icon: const Icon(Icons.refresh),
                          color: kDark,
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(kBase),
                          ),
                        )
                            : IconButton(
                          tooltip: '출차 수 재계산',
                          icon: const Icon(Icons.refresh),
                          color: kDark,
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
                    style: FilledButton.styleFrom(
                      backgroundColor: kBase,
                      foregroundColor: kFg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
    final Color baseColor = color ?? kDark;
    return Chip(
      avatar: Icon(icon, size: 16, color: baseColor),
      label: Text(text),
      labelStyle: TextStyle(color: baseColor, fontWeight: FontWeight.w800),
      backgroundColor:
      color == null ? kLight.withOpacity(.06) : baseColor.withOpacity(0.08),
      side: BorderSide(color: (color ?? kLight).withOpacity(0.35)),
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
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final user = Provider.of<UserState>(context, listen: false).user;
      final division = user?.divisions.first;
      final area = context.read<AreaState>().currentArea;

      if (division == null || area.isEmpty) {
        if (!mounted) return;
        showFailedSnackbar(context, '지역/부서 정보가 없습니다.');
        return;
      }

      final entry = int.tryParse(_inputCtrl.text.trim());
      final exit = int.tryParse(_outputCtrl.text.trim());

      if (entry == null || exit == null) {
        if (!mounted) return;
        showFailedSnackbar(context, '입차/출차 차량 수는 숫자만 입력 가능합니다.');
        return;
      }

      // 전체 누적 요약 갱신
      final summaryRef = FirebaseFirestore.instance
          .collection('fee_summaries')
          .doc('${division}_${area}_all');

      await updateLockedFeeSummary(division, area);
      if (!mounted) return;

      final summary = await summaryRef.get();
      if (!mounted) return;

      // ✅ Firestore READ (fee_summaries doc 1건)
      try {
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: 1,
          source: 'HomeEndWorkReportContent._handleSubmit.fee_summaries.get',
        );
      } catch (_) {}

      final data = summary.data();
      final lockedFee = (data?['totalLockedFee'] ?? 0) is num
          ? (data?['totalLockedFee'] as num).round()
          : 0;

      final reportMap = {
        "vehicleInput": entry,
        "vehicleOutput": exit,
        "totalLockedFee": lockedFee,
      };

      await widget.onReport('end', jsonEncode(reportMap));
      if (!mounted) return;

      await _refetchOutput();
      if (!mounted) return;

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showSuccessSnackbar(context, '업무 종료 보고를 제출했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '보고 제출 실패: $e');
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
        filled: true,
        fillColor: kLight.withOpacity(.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kLight.withOpacity(.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kLight.withOpacity(.35)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: kBase, width: 1.6),
        ),
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

  // ✅ Firestore READ: plates 쿼리
  try {
    await UsageReporter.instance.report(
      area: area,
      action: 'read',
      n: snapshot.docs.length,
      source:
      'updateLockedFeeSummary.plates.query(departure_completed&lockedFee)',
    );
  } catch (_) {}

  int total = 0;
  int count = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final fee = _extractLockedFeeAmount(data);
    total += fee;
    count++;
  }

  final summaryRef =
  firestore.collection('fee_summaries').doc('${division}_${area}_all');

  await summaryRef.set({
    'division': division,
    'area': area,
    'scope': 'all',
    'totalLockedFee': total,
    'lockedVehicleCount': count,
    'lastUpdated': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // ✅ Firestore WRITE: fee_summaries upsert 1건
  try {
    await UsageReporter.instance.report(
      area: area,
      action: 'write',
      n: 1,
      source: 'updateLockedFeeSummary.fee_summaries.upsert',
    );
  } catch (_) {}
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

// 보정치(재생성 이벤트 카운터) 초기화
Future<void> resetDepartureCompletedExtras(String area) async {
  final countersRef =
  FirebaseFirestore.instance.collection('plate_counters').doc('area_$area');

  await countersRef.set({
    'departureCompletedEvents': 0,
    'lastResetAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // ✅ Firestore WRITE: plate_counters 1건
  try {
    await UsageReporter.instance.report(
      area: area,
      action: 'write',
      n: 1,
      source: 'resetDepartureCompletedExtras.plate_counters.set',
    );
  } catch (_) {}
}

// 랜덤 ID 생성(영문소문자+숫자)
String _randomId([int length = 10]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rnd = Random.secure();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

// GCS 업로드: EndWork Report
// ⚠️ Firebase가 아니므로 UsageReporter 계측(READ/WRITE/DELETE)을 **하지 않습니다**.
Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final uid = _randomId(10);
  final fileName = '${uid}_ToDoReports_$dateStr.json';
  final destinationPath = '$division/$area/reports/$fileName';

  report['timestamp'] = dateStr;
  final jsonString = jsonEncode(report);

  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials =
  ServiceAccountCredentials.fromJson(credentialsJson);
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
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();
  // await tempFile.delete();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}

// GCS 업로드: End Logs
// ⚠️ Firebase가 아니므로 UsageReporter 계측(READ/WRITE/DELETE)을 **하지 않습니다**.
Future<String?> uploadEndLogJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final uid = _randomId(10);
  final fileName = '${uid}_ToDoLogs_$dateStr.json';
  final destinationPath = '$division/$area/logs/$fileName';

  report['timestamp'] = dateStr;
  final jsonString = jsonEncode(report);

  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials =
  ServiceAccountCredentials.fromJson(credentialsJson);
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
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();
  // await tempFile.delete();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}
