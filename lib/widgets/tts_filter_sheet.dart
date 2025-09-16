import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../states/area/area_state.dart';
import '../../utils/tts/tts_user_filters.dart';

class TtsFilterSheet extends StatefulWidget {
  const TtsFilterSheet({super.key});

  @override
  State<TtsFilterSheet> createState() => _TtsFilterSheetState();
}

class _TtsFilterSheetState extends State<TtsFilterSheet> {
  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await TtsUserFilters.load();
    if (!mounted) return;
    setState(() {
      _filters = f;
      _loading = false;
    });
  }

  Future<void> _apply(TtsUserFilters next) async {
    setState(() => _filters = next);
    await _filters.save();

    final area = context.read<AreaState>().currentArea;
    final payload = {
      'area': area, // area를 함께 보내면 FG에서 같은 area면 재구독 없이 필터만 갱신됨
      'ttsFilters': _filters.toMap(),
    };
    FlutterForegroundTask.sendDataToTask(payload);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TTS 알림 설정이 적용되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 12),
            Text('TTS 알림 설정', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _SwitchTile(
              title: '입차 요청',
              value: _filters.parking,
              onChanged: (v) => _apply(_filters.copyWith(parking: v)),
            ),
            _SwitchTile(
              title: '출차 요청',
              value: _filters.departure,
              onChanged: (v) => _apply(_filters.copyWith(departure: v)),
            ),
            _SwitchTile(
              title: '출차 완료(2회)',
              value: _filters.completed,
              onChanged: (v) => _apply(_filters.copyWith(completed: v)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
