// lib/screens/secondary_package/office_mode_package/monthly_parking_management.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import 'monthly_management_package/monthly_plate_bottom_sheet.dart';
import '../../../utils/snackbar_helper.dart'; // ✅ 커스텀 스낵바
// import '../../../utils/usage_reporter.dart';

/// 서비스 로그인 카드와 동일 팔레트(Deep Blue)
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() => _MonthlyParkingManagementState();
}

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  // 좌측 상단(11시) 라벨 텍스트
  static const String _screenTag = 'monthly management';

  String? _selectedDocId;
  final ScrollController _scrollController = ScrollController();
  static const int animationDurationMs = 250;
  final Map<String, GlobalKey> _cardKeys = {};

  // ▼ 플로팅 버튼 위치/간격 조절
  static const double _fabBottomGap = 48.0; // 버튼을 화면 하단에서 띄우는 여백
  static const double _fabSpacing = 10.0; // 버튼 간 간격

  void _scrollToCard(String docId) {
    final key = _cardKeys[docId];
    if (key != null) {
      Future.delayed(const Duration(milliseconds: animationDurationMs), () {
        final ctx = key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: animationDurationMs),
            alignment: 0.2,
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _handlePrimaryAction(BuildContext context) async {
    final isEditMode = _selectedDocId != null;

    // index 0: 추가
    if (!isEditMode) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const FractionallySizedBox(
          heightFactor: 1,
          child: MonthlyPlateBottomSheet(),
        ),
      );
      return;
    }

    // index 0: 수정
    try {
      final docRef = FirebaseFirestore.instance.collection('plate_status').doc(_selectedDocId!);
      final snap = await docRef.get();

      // ✅ 계측: read 1회 (가능한 정확한 area로 보고)
      try {
        /*final data = snap.data();
        final areaFromData = (data?['area'] as String?)?.trim();
        final areaFromId = _inferAreaFromPlateStatusDocId(_selectedDocId!);
        final area = (areaFromData?.isNotEmpty == true)
            ? areaFromData!
            : (areaFromId.isNotEmpty ? areaFromId : (context.read<UserState>().currentArea.trim().isNotEmpty
            ? context.read<UserState>().currentArea.trim()
            : 'unknown'));
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: 1,
          source: 'MonthlyParkingManagement._handlePrimaryAction.docGet',
        );*/
      } catch (_) {}

      if (!snap.exists) {
        if (!mounted) return;
        showFailedSnackbar(context, '선택한 문서를 찾을 수 없습니다.');
        return;
      }

      final data = snap.data()!;
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => FractionallySizedBox(
          heightFactor: 1,
          child: MonthlyPlateBottomSheet(
            isEditMode: true,
            initialDocId: _selectedDocId!,
            initialData: data,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '문서 조회 실패: $e');
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    if (_selectedDocId == null) {
      showSelectedSnackbar(context, '삭제할 항목을 선택해주세요.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('선택한 항목을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ?? false;

    if (!ok) return;

    try {
      await FirebaseFirestore.instance.collection('plate_status').doc(_selectedDocId).delete();

      // ✅ 계측: delete 1회
      try {
        /*final area = areaForReport.isNotEmpty
            ? areaForReport
            : (context.read<UserState>().currentArea.trim().isNotEmpty
            ? context.read<UserState>().currentArea.trim()
            : 'unknown');
        await UsageReporter.instance.report(
          area: area,
          action: 'delete',
          n: 1,
          source: 'MonthlyParkingManagement._handleDelete.delete',
        );*/
      } catch (_) {}

      if (!mounted) return;
      setState(() => _selectedDocId = null);
      showSuccessSnackbar(context, '삭제되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // ✅ 메모리 누수 방지
    super.dispose();
  }

  // 좌측 상단(11시) 라벨 위젯 (LocationManagement와 동일 패턴)
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        )).copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $_screenTag',
              child: Text(_screenTag, style: style),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.read<UserState>().currentArea.trim();
    final won = NumberFormat.decimalPattern('ko_KR');
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        flexibleSpace: _buildScreenTag(context), // ◀️ 11시 라벨 (AppBar에 배치)
        title: const Text('정기 주차 관리 페이지', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          // 얇은 하단 구분선
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
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

          // 🔧 사용하지 않는 키 정리
          final currentIds = docs.map((d) => d.id).toSet();
          _cardKeys.keys.where((k) => !currentIds.contains(k)).toList().forEach(_cardKeys.remove);

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
                  elevation: isSelected ? 6 : 1,
                  surfaceTintColor: _SvcColors.light,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected
                        ? const BorderSide(color: _SvcColors.base, width: 2)
                        : BorderSide(color: Colors.black.withOpacity(0.06)),
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
                            Text(
                              '$plateNumber - $countType',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Icon(
                              isSelected ? Icons.expand_less : Icons.expand_more,
                              color: Colors.black.withOpacity(0.45),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 상세 보기
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: animationDurationMs),
                          crossFadeState:
                          isSelected ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: const SizedBox.shrink(),
                          secondChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  _InfoIcon(icon: Icons.attach_money, color: _SvcColors.base),
                                  SizedBox(width: 6),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text('요금: ₩${won.format(regularAmount)}',
                                    style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: const [
                                  _InfoIcon(icon: Icons.schedule, color: _SvcColors.dark),
                                  SizedBox(width: 6),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text('주차 시간: $duration$periodUnit',
                                    style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: const [
                                  _InfoIcon(icon: Icons.calendar_today, color: _SvcColors.light),
                                  SizedBox(width: 6),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text('기간: $startDate ~ $endDate',
                                    style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const _InfoIcon(icon: Icons.info_outline, color: _SvcColors.base),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text('상태 메시지: $customStatus',
                                        style: const TextStyle(fontSize: 16)),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),

                              // 결제 내역
                              if (data['payment_history'] != null &&
                                  data['payment_history'] is List)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '💳 결제 내역',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    ...(() {
                                      final payments =
                                      List<Map<String, dynamic>>.from(data['payment_history']);
                                      final reversed = payments.reversed.toList(); // ✅ 역순 1회
                                      return reversed.map((payment) {
                                        final paidAtRaw = payment['paidAt'] ?? '';
                                        String paidAt;
                                        try {
                                          paidAt = DateFormat('yyyy.MM.dd HH:mm')
                                              .format(DateTime.parse(paidAtRaw));
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
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: _SvcColors.base.withOpacity(0.18),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.04),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const _InfoIcon(
                                                      icon: Icons.calendar_today,
                                                      size: 16,
                                                      color: _SvcColors.dark),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    paidAt,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.black.withOpacity(0.55),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const _InfoIcon(
                                                      icon: Icons.person,
                                                      size: 16,
                                                      color: _SvcColors.base),
                                                  const SizedBox(width: 6),
                                                  Text('결제자: $paidBy',
                                                      style: const TextStyle(fontSize: 14)),
                                                  if (extended)
                                                    Container(
                                                      margin: const EdgeInsets.only(left: 8),
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: _SvcColors.light.withOpacity(.16),
                                                        borderRadius: BorderRadius.circular(999),
                                                        border: Border.all(
                                                          color: _SvcColors.light.withOpacity(.35),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        '연장',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: _SvcColors.dark,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const _InfoIcon(
                                                      icon: Icons.attach_money,
                                                      size: 16,
                                                      color: _SvcColors.base),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '₩${won.format(amount)}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (note.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const _InfoIcon(
                                                        icon: Icons.note,
                                                        size: 16,
                                                        color: _SvcColors.dark),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        note,
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }).toList();
                                    })(),
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

      // ▼ FAB: 선택 없음 → 추가 / 선택 있음 → 수정·삭제
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: _selectedDocId != null,
        onPrimary: () => _handlePrimaryAction(context), // 추가/수정
        onDelete: _selectedDocId != null ? () => _handleDelete(context) : null, // 삭제
        cs: cs,
      ),
    );
  }
}

class _InfoIcon extends StatelessWidget {
  const _InfoIcon({
    required this.icon,
    this.size = 20,
    this.color = _SvcColors.base,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color);
  }
}

/// 현대적인 파브 세트(라운드 필 버튼 스타일 + 하단 spacer로 위치 조절)
class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onPrimary,
    required this.onDelete,
    required this.cs,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onPrimary; // 선택 없음: 추가 / 선택 있음: 수정
  final VoidCallback? onDelete; // 선택 있음에서만 사용
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: _SvcColors.base,
      // ✅ 서비스 팔레트 반영
      foregroundColor: Colors.white,
      elevation: 3,
      shadowColor: _SvcColors.dark.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasSelection) ...[
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ] else ...[
          _ElevatedPillButton.icon(
            icon: Icons.add,
            label: '추가',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
        ],
        SizedBox(height: bottomGap), // ▼ 하단 여백으로 버튼 위치 올리기
      ],
    );
  }
}

/// 둥근 알약 형태의 현대적 버튼 래퍼 (ElevatedButton 기반)
class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  // ✅ const 생성자 대신 factory로 위임(상수 제약 회피)
  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
    Key? key,
  }) {
    return _ElevatedPillButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

/// 아이콘 + 라벨(간격/정렬 최적화)
class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label, Key? key}) : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

/// plate_status 문서 ID에서 area 추출: 규칙이 'plateNumber_area' 라고 가정.
/// 규칙이 다르면 'unknown' 반환.
/*String _inferAreaFromPlateStatusDocId(String docId) {
  final idx = docId.lastIndexOf('_');
  if (idx <= 0 || idx >= docId.length - 1) return 'unknown';
  return docId.substring(idx + 1);
}*/
