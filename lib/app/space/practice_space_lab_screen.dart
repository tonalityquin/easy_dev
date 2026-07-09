import 'package:flutter/material.dart';

import '../../app/di/routes.dart';
import 'image_ai_model_test/image_ai_model_test_lab_screen.dart';

class PracticeSpaceLabScreen extends StatelessWidget {
  const PracticeSpaceLabScreen({super.key});

  static const List<_PracticeExperimentItem> _experiments = [
    _PracticeExperimentItem(
      icon: Icons.image_search_rounded,
      title: '이미지 AI 모델 테스트',
      subtitle: '번호판 이미지 인식, 결과 삽입, 성공/실패 로그 출력 테스트',
      page: ImageAiModelTestLabScreen(),
    ),
  ];

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
                '운영 기능과 분리된 이미지 AI 모델 테스트 공간입니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: _experiments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final experiment = _experiments[index];

                    return _PracticeExperimentCard(
                      experiment: experiment,
                      iconColor: cs.primary,
                      onTap: () => _openExperiment(context, experiment.page),
                    );
                  },
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

class _PracticeExperimentItem {
  const _PracticeExperimentItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
}

class _PracticeExperimentCard extends StatelessWidget {
  const _PracticeExperimentCard({
    required this.experiment,
    required this.iconColor,
    required this.onTap,
  });

  final _PracticeExperimentItem experiment;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(experiment.icon, color: iconColor),
        title: Text(experiment.title),
        subtitle: Text(experiment.subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
