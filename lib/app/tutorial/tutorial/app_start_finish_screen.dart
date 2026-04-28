import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/startup_tasks.dart';
class AppStartFinishScreen extends StatefulWidget {
  const AppStartFinishScreen({super.key});

  @override
  State<AppStartFinishScreen> createState() => _AppStartFinishScreenState();
}

class _AppStartFinishScreenState extends State<AppStartFinishScreen> {
  bool _busy = false;

  Future<void> _complete(bool done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    try {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      await AppStartFlowPrefs.setSelectorScreenTutorialDone(done);
      await StartupTasks.runAfterPermissions();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.selector,
        (route) => false,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selector 화면 안내 튜토리얼'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 96, color: cs.primary),
                        const SizedBox(height: 18),
                        Text(
                          '마지막 단계',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Selector 화면 안내 튜토리얼을 완료했습니까?',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _complete(true),
                            icon: const Icon(Icons.thumb_up_rounded),
                            label: const Text('예'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _complete(false),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('아니요'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
