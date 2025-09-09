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
    load: RoadmapLoad.heavy,
    title: '태블릿 모드 작업',
    notes: [
      '페이지 생성',
      '모드 생성',
      '라우트 연결',
    ],
    status: RoadmapStatus.done,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '출퇴근 모드 작업',
    notes: [
      '페이지 생성',
      '모드 생성',
      '라우트 연결',
    ],
    status: RoadmapStatus.done,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '종합 라우트 페이지 설계',
    notes: [
      '페이지 생성',
      '모드 생성',
      '라우트 연결',
      '추가 기능 및 로직들 삽입',
    ],
    status: RoadmapStatus.done,
  ),
  RoadmapItem(
    load: RoadmapLoad.medium,
    title: 'API 외부 삽입 로직 강화',
    notes: [
      'Google Calendar API',
      'Google Excel API',
      'Google Accounts',
      'Kakao URL',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: 'FAQ 키워드 단어 페이지 별 삽입',
    notes: [
      '페이지 별로 FAQ 키워드 단어 삽입',
      '사용자가 어려움 혹은 오류 발생 시 키워드를 검색해서 대처할 수 있도록',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '뒤로가기 앱 꺼짐 방지 로직 재삽입',
    notes: [
      '모든 화면에서 뒤로가기 시 앱 꺼짐 로직 방지 코드 점검 및 삽입',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '입차 완료 현황 심화 열람 limit 확장',
    notes: [
      'Goal.개발자 모드 페이지에서 각 지역 별로 limit 지정',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: 'Calendar Page 진입 로직 보안 강화',
    notes: [
      '앱을 사용하는 임의의 사용자가 다른 사람의 구글 계정만 인지하면 계정의 캘린더 진입 가능'
      'Goal.진입할 수 있는 구글 계정 명과 ',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: 'Block Dialog 삽입 과정 추가',
    notes: [
      '번호판 생성 수정 등 실시간에 민감한 로직에 방어 코드 삽입',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '디버그 경로 통일',
    notes: [
      '커뮤니티 내 디버그 액션 카드로 통일',
      '문제 발생 시에만 메서드 혹은 함수 알림',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '기술 조사(출퇴근 로그인)',
    notes: [
      'Prob.마이발렛 앱 설계 한계',
      '- 핸드폰에서 마이발렛을 기본 프로그램으로 인식하지 않음',
      'Goal.출퇴근 & 휴게시간 저장을 외부에서 할 수 있도록',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.medium,
    title: '중복 번호판 데이터 생성',
    notes: [
      'Condition',
      '1.동일한 날짜',
      '2.동일한 번호판',
      'Prob.동일한 테이블에서 관리하고 있어 이중 데이터 생성 불가능'
          'Goal.동일한 날짜에서 기존 로직에 방해 없이 새롭게 데이터 생성'
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.light,
    title: '가이드북 생성 및 액션 카드 추가',
    notes: [
      '앱에서 캡처 등을 통해 특정 난이도 있는 행동들에 대한 가이드 북 삽입',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.medium,
    title: '사진 촬영 시 불안정한 화소 해결',
    notes: [
      'Prob.촬영 후 사진은 정상이나 촬영 시 포커싱에서의 문제가 불특정 기기에서 발생',
      'Goal.촬영 전과 후의 카메라 페이지가 동일한 성능을 가지도록',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: 'QR 코드 생성(태블릿 모드)',
    notes: [
      'Case A.사용자가 QR코드를 촬영하여 받은 일회성 페이지에서 특정 번호판을 입차 완료에서 출차 요청으로 변경',
      'Case B.사용자가 출차 요청한 후, 발급받은 QR코드를 촬영하여 출차 완료가 되면 알림 수신',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '기술 조사(서비스 - 번호판 생성 - 음성 인식)',
    notes: [
      '음성 인식으로 번호판 컨트롤러에 데이터 삽입',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '기술 조사(서비스 - 번호판 생성 - OCR)',
    notes: [
      '촬영한 사진에 적혀 있는 번호판 데이터가 번호판 컨트롤러에 삽입',
      'Requirement.로컬 AI 모델 사용',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.medium,
    title: '로컬에 저장한 출근, 퇴근 시간 알림 기능',
    notes: [
      'Goal.퇴근 10분 전 등 특정 시간에 맞춰서 핸드폰에서 알람이 울리도록',
      'Requirement.로컬 AI 모델 사용',
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
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
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
                    controller: controller,
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
