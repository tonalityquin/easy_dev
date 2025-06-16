import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

// 중략: import 부분은 기존과 동일

class ParkingReportContent extends StatefulWidget {
  final void Function(String reportType, String content) onReport;

  const ParkingReportContent({super.key, required this.onReport});

  @override
  State<ParkingReportContent> createState() => _ParkingReportContentState();
}

class _ParkingReportContentState extends State<ParkingReportContent> {
  int _selectedTabIndex = 0;
  bool _canSubmit = false;

  final TextEditingController _vehicleCountController = TextEditingController();
  final TextEditingController _exitVehicleCountController = TextEditingController();
  final TextEditingController _startReportController = TextEditingController();
  final TextEditingController _middleReportController = TextEditingController();

  List<Map<String, dynamic>> _issues = [];

  @override
  void initState() {
    super.initState();
    _vehicleCountController.addListener(_updateSubmitState);
    _exitVehicleCountController.addListener(_updateSubmitState);
    _startReportController.addListener(_updateSubmitState);
    _middleReportController.addListener(_updateSubmitState);

    _fetchIssues(); // 이슈 불러오기
  }

  Future<int>? _feeSummaryFuture;

  Future<void> updateLockedFeeSummary(String division, String area) async {
    final firestore = FirebaseFirestore.instance;
    final date = DateTime.now();
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

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
      final fee = data['lockedFeeAmount'];
      if (fee is int) {
        total += fee;
        count++;
      } else if (fee is double) {
        total += fee.round();
        count++;
      }
    }

    final summaryRef = firestore.collection('fee_summaries').doc('${division}_$area\_$dateStr');
    await summaryRef.set({
      'division': division,
      'area': area,
      'date': dateStr,
      'totalLockedFee': total,
      'vehicleCount': count,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  Future<int> fetchCachedLockedFeeTotal(String division, String area) async {
    final date = DateTime.now();
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final docId = "${division}_$area\_$dateStr";

    final doc = await FirebaseFirestore.instance.collection('fee_summaries').doc(docId).get();

    if (doc.exists) {
      return doc['totalLockedFee'] ?? 0;
    } else {
      return 0;
    }
  }

  Future<void> _fetchIssues() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final user = Provider.of<UserState>(context, listen: false).user;

      if (user == null || user.divisions.isEmpty) return;

      final division = user.divisions.first;

      final snapshot = await firestore.collection('tasks').where('division', isEqualTo: division).get();

      final fetched = snapshot.docs
          .map((doc) {
            final data = doc.data();
            if (!data.containsKey('issue')) return null;

            final issueMap = data['issue'];
            final title = issueMap is Map ? issueMap['title'] : null;

            return {
              'title': title?.toString() ?? '(제목 없음)',
              'createdAt': data['createdAt'] ?? '',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      fetched.sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt']) ?? DateTime(0);
        final bDate = DateTime.tryParse(b['createdAt']) ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _issues = fetched;
      });
    } catch (e) {
      debugPrint('❌ 이슈 불러오기 실패: $e');
    }
  }

  void _updateSubmitState() {
    bool shouldEnable = false;

    if (_selectedTabIndex == 0) {
      shouldEnable = _startReportController.text.trim().isNotEmpty;
    } else if (_selectedTabIndex == 1) {
      shouldEnable = _middleReportController.text.trim().isNotEmpty && _issues.isNotEmpty;
      // ⬆️ 이슈 존재 조건 추가됨
    } else {
      shouldEnable =
          _vehicleCountController.text.trim().isNotEmpty && _exitVehicleCountController.text.trim().isNotEmpty;
    }

    if (_canSubmit != shouldEnable) {
      setState(() {
        _canSubmit = shouldEnable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '업무 보고',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('업무 시작')),
                ButtonSegment(value: 1, label: Text('보고란')),
                ButtonSegment(value: 2, label: Text('업무 종료')),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (newSelection) {
                setState(() => _selectedTabIndex = newSelection.first);
                _updateSubmitState();
              },
            ),
            const SizedBox(height: 16),
            if (_selectedTabIndex == 0)
              _buildStartReportField()
            else if (_selectedTabIndex == 1)
              _buildMiddleReportField()
            else
              _buildEndReportField(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    if (_selectedTabIndex == 0) {
                      _startReportController.clear();
                    } else if (_selectedTabIndex == 1) {
                      _middleReportController.clear();
                    } else {
                      _vehicleCountController.clear();
                      _exitVehicleCountController.clear();
                    }
                  },
                  child: const Text('지우기'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('제출'),
                  onPressed: _canSubmit ? _handleSubmit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartReportField() {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _startReportController,
        decoration: const InputDecoration(
          labelText: '업무 시작 내용',
          hintText: '예: "근무지" "몇 명" 정상 출근 건강 이상 없습니다.',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
    );
  }

  Widget _buildMiddleReportField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_issues.isNotEmpty)
          ..._issues.map((issue) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(
                  child: Text(
                    '📌 ${issue['title']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              )),
        const SizedBox(height: 8),
        Center(
          child: SizedBox(
            width: 300,
            child: TextField(
              controller: _middleReportController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: '코멘트 섹션',
                hintText: '예: 게시된 이슈에 대한 약식 답변',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ),
        ),
      ],
    );
  }

  // 이 필드는 클래스의 상태 변수로 선언되어야 합니다.

  Widget _buildEndReportField() {
    final user = Provider.of<UserState>(context, listen: false).user;
    final division = user?.divisions.first;
    final area = user?.currentArea;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _vehicleCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '입차 차량 수',
                  hintText: '예: 24',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _exitVehicleCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '출차 차량 수',
                  hintText: '예: 21',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ✅ 버튼 또는 결과 표시
        if (_feeSummaryFuture == null)
          ElevatedButton(
            onPressed: () async {
              if (division == null || area == null) return;

              final dateStr = DateTime.now().toIso8601String().split('T').first;
              final summaryRef =
                  FirebaseFirestore.instance.collection('fee_summaries').doc('${division}_$area\_$dateStr');

              final doc = await summaryRef.get();
              if (!doc.exists) {
                await updateLockedFeeSummary(division, area);
              }

              setState(() {
                _feeSummaryFuture = fetchCachedLockedFeeTotal(division, area);
              });
            },
            child: const Text('최종 정산 금액 확인하기'),
          )
        else
          FutureBuilder<int>(
            future: _feeSummaryFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData) {
                return const Text('정산 금액을 불러올 수 없습니다.');
              }
              return Text(
                '🔒 총 정산금: ₩${snapshot.data}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              );
            },
          ),
      ],
    );
  }

  void _handleSubmit() {
    late String type;
    late String content;

    if (_selectedTabIndex == 0) {
      type = 'start';
      content = _startReportController.text.trim();
    } else if (_selectedTabIndex == 1) {
      type = 'middle';
      content = _middleReportController.text.trim();
    } else {
      type = 'end';
      final entry = int.tryParse(_vehicleCountController.text.trim());
      final exit = int.tryParse(_exitVehicleCountController.text.trim());

      if (entry == null || exit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차/출차 차량 수는 숫자만 입력 가능합니다.')),
        );
        return;
      }

      final reportMap = {
        "vehicleInput": entry,
        "vehicleOutput": exit,
      };
      content = jsonEncode(reportMap);
    }

    widget.onReport(type, content);
  }
}

// ==== GCS 업로드 메서드 ====

Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final fileName = 'ToDoReports_$dateStr.json';
  final destinationPath = '$division/$area/reports/$fileName';

  // 타임스탬프 추가
  report['timestamp'] = dateStr;

  // JSON 문자열로 변환
  final jsonString = jsonEncode(report);

  // 임시 파일에 저장
  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  // 서비스 계정 인증
  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final scopes = [StorageApi.devstorageFullControlScope];
  final client = await clientViaServiceAccount(accountCredentials, scopes);
  final storage = StorageApi(client);

  // 업로드 미디어
  final media = Media(
    tempFile.openRead(),
    tempFile.lengthSync(),
    contentType: 'application/json',
  );

  // ✅ 업로드 객체 설정: 다운로드 강제
  final object = await storage.objects.insert(
    Object()
      ..name = destinationPath
      ..contentDisposition = 'attachment' // 여기서 다운로드를 유도
      ..acl = [
        ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();

  final uploadedUrl = 'https://storage.googleapis.com/$kBucketName/${object.name}';
  debugPrint('✅ GCS 업로드 완료: $uploadedUrl');
  return uploadedUrl;
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
