import 'package:flutter/material.dart';

import '../../app/di/routes.dart';
import '../tutorial/tutorial/app_start_tutorial_lab_screen.dart';
import 'parking_visualization/parking_visualization_lab_screen.dart';
import 'chat/practice_chat_lab_screen.dart';

class PracticeSpaceLabScreen extends StatelessWidget {
  const PracticeSpaceLabScreen({super.key});

  void _goBackToSelector(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }

  void _openExperiment(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Space'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Selector로 이동',
            onPressed: () => _goBackToSelector(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '개발/테스트 영역',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '여기에 기능을 자유롭게 추가하세요.\n이 화면은 운영 기능과 분리된 실험 공간입니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    Card(
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(Icons.local_parking_rounded,
                            color: cs.primary),
                        title: const Text('실험 1: 주차 구역 시각화 모형'),
                        subtitle:
                            const Text('격자(Grid) 기반 주차면 상태(빈칸/점유/차단) 시각화 테스트'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openExperiment(
                          context,
                          const ParkingVisualizationLabScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading:
                            Icon(Icons.chat_bubble_rounded, color: cs.primary),
                        title: const Text('실험 2: 채팅 기능'),
                        subtitle: const Text('로컬 상태 기반 채팅 UI/입력/에코 응답 테스트'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openExperiment(
                          context,
                          const PracticeChatLabScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(Icons.school_rounded, color: cs.primary),
                        title: const Text('실험 3: 앱 시작 튜토리얼'),
                        subtitle: const Text('PageView 기반 온보딩/튜토리얼 플로우 테스트'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openExperiment(
                          context,
                          const AppStartTutorialLabScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Selector로 돌아가기'),
                  onPressed: () => _goBackToSelector(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
