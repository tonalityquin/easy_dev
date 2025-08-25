import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

class EndWorkReportContent extends StatefulWidget {
  final Future<void> Function(String reportType, String content) onReport;

  // ✅ 입차/출차 차량 수 초기값을 외부에서 주입받아 TextField에 표시
  final int? initialVehicleInput;   // 입차 차량 수
  final int? initialVehicleOutput;  // 출차 차량 수

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
  final TextEditingController _vehicleCountController = TextEditingController();       // 입차
  final TextEditingController _exitVehicleCountController = TextEditingController();   // 출차

  void _update() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // ✅ 다이얼로그 오픈 전에 계산된 초기값 주입
    if (widget.initialVehicleInput != null) {
      _vehicleCountController.text = widget.initialVehicleInput.toString();
    }
    if (widget.initialVehicleOutput != null) {
      _exitVehicleCountController.text = widget.initialVehicleOutput.toString();
    }
    _vehicleCountController.addListener(_update);
    _exitVehicleCountController.addListener(_update);
  }

  @override
  void dispose() {
    _vehicleCountController.dispose();
    _exitVehicleCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _vehicleCountController.text.trim().isNotEmpty &&
            _exitVehicleCountController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('업무 종료 보고', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _vehicleCountController, // 입차 차량 수
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '입차 차량 수',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _exitVehicleCountController, // 출차 차량 수
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '출차 차량 수',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('제출'),
            onPressed: canSubmit ? _handleSubmit : null,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final user = Provider.of<UserState>(context, listen: false).user;
    final division = user?.divisions.first;
    final area = user?.currentArea;

    if (division == null || area == null) return;

    final entry = int.tryParse(_vehicleCountController.text.trim());
    final exit = int.tryParse(_exitVehicleCountController.text.trim());

    if (entry == null || exit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입차/출차 차량 수는 숫자만 입력 가능합니다.')),
      );
      return;
    }

    // ✅ 요약 문서는 “전체 누적” 키를 사용(날짜 대신 _all)
    final summaryRef = FirebaseFirestore.instance
        .collection('fee_summaries')
        .doc('${division}_${area}_all');

    // ✅ 보고 직전 최신 상태로 전체 누적 요약 갱신
    await updateLockedFeeSummary(division, area);

    final summary = await summaryRef.get();
    final data = summary.data();
    final lockedFee = (data?['totalLockedFee'] ?? 0) is num
        ? (data?['totalLockedFee'] as num).round()
        : 0;

    final reportMap = {
      "vehicleInput": entry,
      "vehicleOutput": exit,
      "totalLockedFee": lockedFee,
    };

    final content = jsonEncode(reportMap);

    await widget.onReport('end', content);
  }
}

/// ✅ “시간 제한 없이” 전체 누적 기준으로 요약을 작성/갱신.
/// 조건:
/// - type == 'departure_completed'
/// - isLockedFee == true
/// - area == 전달 인자
/// 합계 산출:
/// - lockedFeeAmount 우선, 없으면 logs 마지막 lockedFee 사용
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

  final summaryRef =
  firestore.collection('fee_summaries').doc('${division}_${area}_all'); // ✅ 전체 집계 키

  await summaryRef.set({
    'division': division,
    'area': area,
    'scope': 'all',                           // 전체 누적임을 명시
    'totalLockedFee': total,                  // 전체 잠금요금 합계
    'lockedVehicleCount': count,              // 전체 잠금요금 발생 차량 수
    'lastUpdated': FieldValue.serverTimestamp(), // 서버 시각
  }, SetOptions(merge: true));
}

/// 내부 헬퍼: 문서에서 잠금요금을 안전 추출
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

Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final fileName = 'ToDoReports_$dateStr.json';
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
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}

Future<void> deleteLockedDepartureDocs(String area) async {
  final firestore = FirebaseFirestore.instance;
  final snapshot = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  for (final doc in snapshot.docs) {
    await doc.reference.delete();
    debugPrint("🔥 Firestore 삭제 완료: ${doc.id}");
  }
}
