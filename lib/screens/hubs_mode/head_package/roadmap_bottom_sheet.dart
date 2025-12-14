import 'package:flutter/material.dart';

enum RoadmapStatus { planned, inProgress, done }

enum RoadmapLoad { light, medium, heavy }

class RoadmapItem {
  final String? date;
  final RoadmapLoad? load;
  final String title;
  final List<String> notes;
  final RoadmapStatus status;

  const RoadmapItem({
    this.date,
    this.load,
    required this.title,
    required this.notes,
    required this.status,
  });
}

const List<RoadmapItem> _roadmapData = [
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '가이드북 생성 및 액션 카드 추가',
    notes: [
      '앱에서 캡처 등을 통해 특정 난이도 있는 행동들에 대한 가이드 북 삽입',
    ],
    status: RoadmapStatus.done,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '홈페이지 모드 지원',
    notes: [
      '홈페이지로 출차 요청 및 업무 보조 지원',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '근무지 현황 카드 리팩토링',
    notes: [
      '지역 별 최근 출근 찍은 직원들 목록 나열'
          '\n지역 별 현재 근무 차량 수 표기',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: 'QR 코드 지원',
    notes: [
      'Case A.사용자가 QR코드를 촬영하여 받은 일회성 페이지에서 특정 번호판을 입차 완료에서 출차 요청으로 변경',
      'Case B.사용자가 출차 요청한 후, 발급받은 QR코드를 촬영하여 출차 완료가 되면 알림 수신',
    ],
    status: RoadmapStatus.planned,
  ),
];

class RoadmapBottomSheet extends StatelessWidget {
  const RoadmapBottomSheet({super.key});

  Color _statusColor(BuildContext context, RoadmapStatus s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case RoadmapStatus.planned:
        return cs.secondary;
      case RoadmapStatus.inProgress:
        return cs.primary;
      case RoadmapStatus.done:
        return cs.tertiary;
    }
  }

  String _statusLabel(RoadmapStatus s) {
    switch (s) {
      case RoadmapStatus.planned:
        return '계획';
      case RoadmapStatus.inProgress:
        return '진행 중';
      case RoadmapStatus.done:
        return '완료';
    }
  }

  Color _loadColor(BuildContext context, RoadmapLoad l) {
    final cs = Theme.of(context).colorScheme;
    switch (l) {
      case RoadmapLoad.light:
        return cs.tertiary;
      case RoadmapLoad.medium:
        return cs.secondary;
      case RoadmapLoad.heavy:
        return cs.error;
    }
  }

  String _loadLabel(RoadmapLoad l) {
    switch (l) {
      case RoadmapLoad.light:
        return '여유';
      case RoadmapLoad.medium:
        return '보통';
      case RoadmapLoad.heavy:
        return '과중';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      // ⬇️ 열자마자 최상단까지
      initialChildSize: 1.0,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: true, // 상태바 아래까지 안전하게
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.timeline_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '프로세스 로드맵',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '실시간 갱신 X',
                        style: text.labelMedium?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 레전드(상태)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _legendChip(context,
                          label: _statusLabel(RoadmapStatus.inProgress),
                          color: _statusColor(context, RoadmapStatus.inProgress)),
                      _legendChip(context,
                          label: _statusLabel(RoadmapStatus.planned),
                          color: _statusColor(context, RoadmapStatus.planned)),
                      _legendChip(context,
                          label: _statusLabel(RoadmapStatus.done), color: _statusColor(context, RoadmapStatus.done)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),

                Expanded(
                  child: ListView.builder(
                    controller: controller, // ⬅️ 제공된 스크롤러 사용
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _roadmapData.length,
                    itemBuilder: (context, i) => _TimelineTile(
                      item: _roadmapData[i],
                      statusColor: _statusColor(context, _roadmapData[i].status),
                      statusLabel: _statusLabel(_roadmapData[i].status),
                      loadColor: _roadmapData[i].load == null ? null : _loadColor(context, _roadmapData[i].load!),
                      loadLabel: _roadmapData[i].load == null ? null : _loadLabel(_roadmapData[i].load!),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _legendChip(BuildContext context, {required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final RoadmapItem item;
  final Color statusColor;
  final String statusLabel;
  final Color? loadColor;
  final String? loadLabel;

  const _TimelineTile({
    required this.item,
    required this.statusColor,
    required this.statusLabel,
    this.loadColor,
    this.loadLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(width: 4, height: 6, color: Colors.transparent),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                ),
                Container(
                  width: 2,
                  height: 90,
                  margin: const EdgeInsets.only(top: 6),
                  color: cs.outlineVariant,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if ((item.date ?? '').isNotEmpty) _chip(text: item.date!, bg: Colors.black.withOpacity(.06)),
                      if (loadLabel != null && loadColor != null)
                        _chip(text: loadLabel!, bg: loadColor!.withOpacity(.16)),
                      _chip(text: statusLabel, bg: statusColor.withOpacity(.16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(item.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ...item.notes.map(
                    (n) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(n, style: text.bodyMedium)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String text, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
