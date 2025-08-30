import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'monthly_parking_pages/monthly_plate_bottom_sheet.dart';
import '../../../utils/snackbar_helper.dart'; // ✅ 커스텀 스낵바

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() => _MonthlyParkingManagementState();
}

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  String? _selectedDocId;
  final ScrollController _scrollController = ScrollController();
  static const int animationDurationMs = 250;
  final Map<String, GlobalKey> _cardKeys = {};

  void _handleIconTap(BuildContext context, int index) {
    final isEditMode = _selectedDocId != null;

    switch (index) {
      case 0:
        if (!isEditMode) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => const MonthlyPlateBottomSheet(),
          );
        } else {
          FirebaseFirestore.instance.collection('plate_status').doc(_selectedDocId!).get().then((doc) {
            if (doc.exists) {
              final data = doc.data()!;
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (context) => MonthlyPlateBottomSheet(
                  isEditMode: true,
                  initialDocId: _selectedDocId!,
                  initialData: data,
                ),
              );
            } else {
              // ❌ 기존 SnackBar → 커스텀 스낵바
              showFailedSnackbar(context, '선택한 문서를 찾을 수 없습니다.');
            }
          });
        }
        break;

      case 1:
      // ℹ️ 안내용
        showSelectedSnackbar(context, '수정 기능은 준비 중입니다.');
        break;

      case 2:
        if (_selectedDocId == null) {
          // ⚠️ 선택 필요
          showSelectedSnackbar(context, '삭제할 항목을 선택해주세요.');
          return;
        }

        FirebaseFirestore.instance.collection('plate_status').doc(_selectedDocId).delete().then((_) {
          setState(() => _selectedDocId = null);
          // ✅ 성공 메시지
          showSuccessSnackbar(context, '삭제되었습니다.');
        }).catchError((e) {
          // ❌ 실패 메시지
          showFailedSnackbar(context, '삭제 실패: $e');
        });
        break;
    }
  }

  void _scrollToCard(String docId) {
    final key = _cardKeys[docId];
    if (key != null) {
      Future.delayed(Duration(milliseconds: animationDurationMs), () {
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: animationDurationMs),
            alignment: 0.2,
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.read<UserState>().currentArea.trim();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('정기 주차 관리 페이지', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('plate_status')
            .where('type', isEqualTo: '정기')
            .where('area', isEqualTo: currentArea)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('등록된 정기 주차 정보가 없습니다.'));
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final docId = doc.id;
              final data = doc.data() as Map<String, dynamic>;

              final plateNumber = docId.split('_').first;
              final countType = data['countType'] ?? '';
              final regularAmount = data['regularAmount'] ?? 0;
              final duration = data['regularDurationHours'] ?? 0;
              final startDate = data['startDate'] ?? '';
              final endDate = data['endDate'] ?? '';
              final periodUnit = data['periodUnit'] ?? '시간';
              final customStatus = data['customStatus'] ?? '없음';
              final isSelected = docId == _selectedDocId;

              _cardKeys[docId] = _cardKeys[docId] ?? GlobalKey();

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDocId = isSelected ? null : docId;
                  });

                  if (!isSelected) {
                    _scrollToCard(docId);
                  }
                },
                child: Card(
                  key: _cardKeys[docId],
                  elevation: isSelected ? 6 : 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected ? const BorderSide(color: Colors.redAccent, width: 2) : BorderSide.none,
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$plateNumber - $countType',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Icon(
                              isSelected ? Icons.expand_less : Icons.expand_more,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 상세 보기
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: animationDurationMs),
                          crossFadeState: isSelected ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: const SizedBox.shrink(),
                          secondChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.attach_money, size: 20, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text('요금: ₩$regularAmount', style: const TextStyle(fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.schedule, size: 20, color: Colors.blueGrey),
                                  const SizedBox(width: 6),
                                  Text('주차 시간: $duration$periodUnit', style: const TextStyle(fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 20, color: Colors.deepOrange),
                                  const SizedBox(width: 6),
                                  Text('기간: $startDate ~ $endDate', style: const TextStyle(fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 20, color: Colors.purple),
                                  const SizedBox(width: 6),
                                  Text('상태 메시지: $customStatus', style: const TextStyle(fontSize: 16)),
                                ],
                              ),
                              const Divider(height: 24),
                              if (data['payment_history'] != null && data['payment_history'] is List)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('💳 결제 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...List.generate(List<Map<String, dynamic>>.from(data['payment_history']).length,
                                            (i) {
                                          final payments = List<Map<String, dynamic>>.from(data['payment_history']);
                                          final payment = payments.reversed.toList()[i];
                                          final paidAtRaw = payment['paidAt'] ?? '';
                                          String paidAt = '';
                                          try {
                                            paidAt = DateFormat('yyyy.MM.dd HH:mm').format(DateTime.parse(paidAtRaw));
                                          } catch (_) {
                                            paidAt = paidAtRaw;
                                          }

                                          final amount = payment['amount'] ?? 0;
                                          final paidBy = payment['paidBy'] ?? '';
                                          final note = payment['note'] ?? '';
                                          final extended = payment['extended'] == true;

                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.calendar_today, size: 16, color: Colors.blueGrey),
                                                    const SizedBox(width: 6),
                                                    Text(paidAt,
                                                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.person, size: 16, color: Colors.teal),
                                                    const SizedBox(width: 6),
                                                    Text('결제자: $paidBy', style: const TextStyle(fontSize: 14)),
                                                    if (extended)
                                                      Container(
                                                        margin: const EdgeInsets.only(left: 8),
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange.shade100,
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Text('연장',
                                                            style: TextStyle(fontSize: 12, color: Colors.orange)),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.attach_money, size: 16, color: Colors.green),
                                                    const SizedBox(width: 6),
                                                    Text('₩${amount.toString()}',
                                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                                if (note.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Icon(Icons.note, size: 16, color: Colors.deepPurple),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(note, style: const TextStyle(fontSize: 14)),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        }),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: _selectedDocId == null ? const [Icons.add, Icons.delete] : const [Icons.edit, Icons.delete],
        onIconTapped: (index) => _handleIconTap(context, index),
      ),
    );
  }
}
