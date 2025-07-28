import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import 'end_work_report_content.dart';

Future<void> showReportDialog(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(20),
          child: EndWorkReportContent(
            onReport: (type, content) async {
              if (type == 'cancel') {
                if (Navigator.canPop(context)) Navigator.pop(context);
                return;
              }

              final area = context.read<AreaState>().currentArea;
              final division = context.read<AreaState>().currentDivision;
              final userName = context.read<UserState>().name;

              if (type == 'end') {
                final parsed = jsonDecode(content);

                final dateStr = DateTime.now().toIso8601String().split('T').first;
                final summaryRef = FirebaseFirestore.instance
                    .collection('fee_summaries')
                    .doc('${division}_$area\_$dateStr');

                final doc = await summaryRef.get();
                if (!doc.exists) {
                  await _updateLockedFeeSummary(division, area);
                }

                final latest = await summaryRef.get();
                final totalLockedFee = latest['totalLockedFee'] ?? 0;

                final reportLog = {
                  'division': division,
                  'area': area,
                  'vehicleCount': {
                    'vehicleInput': int.tryParse(parsed['vehicleInput'].toString()) ?? 0,
                    'vehicleOutput': int.tryParse(parsed['vehicleOutput'].toString()) ?? 0,
                  },
                  'totalLockedFee': totalLockedFee,
                  'timestamp': DateTime.now().toIso8601String(),
                };

                await uploadEndWorkReportJson(
                  report: reportLog,
                  division: division,
                  area: area,
                  userName: userName,
                );

                await deleteLockedDepartureDocs(area);

                if (context.mounted) {
                  Navigator.pop(context);
                  showSuccessSnackbar(
                    context,
                    "업무 종료 보고 업로드 및 출차 초기화 "
                        "(입차: ${parsed['vehicleInput']}, 출차: ${parsed['vehicleOutput']})",
                  );
                }
              } else if (type == 'start') {
                if (context.mounted) {
                  Navigator.pop(context);
                  showSuccessSnackbar(context, "업무 시작 보고 완료: $content");
                }
              } else if (type == 'middle') {
                final user = context.read<UserState>().user;
                if (user == null || user.divisions.isEmpty) {
                  showFailedSnackbar(context, '사용자 정보가 없어 보고를 저장할 수 없습니다.');
                  return;
                }

                await FirebaseFirestore.instance.collection('tasks').add({
                  'creator': user.id,
                  'division': user.divisions.first,
                  'answer': content,
                  'createdAt': DateTime.now().toIso8601String(),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  showSuccessSnackbar(context, "보고란 제출 완료: $content");
                }
              }
            },
          ),
        ),
      );
    },
  );
}

/// 🔄 Firestore 정산 요약 작성 (중복 방지 포함)
Future<void> _updateLockedFeeSummary(String division, String area) async {
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
