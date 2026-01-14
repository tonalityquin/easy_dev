import 'package:flutter/material.dart';

import '../../utils/tts/tts_sync_helper.dart';
import '../../utils/tts/tts_user_filters.dart';

class TtsFilterSheet extends StatefulWidget {
  const TtsFilterSheet({super.key});

  @override
  State<TtsFilterSheet> createState() => _TtsFilterSheetState();
}

class _TtsFilterSheetState extends State<TtsFilterSheet> {
  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;

  // ✅ 토글 연타 방지
  bool _applying = false;

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

  /// DashboardSetting 기준의 실시간 반영:
  /// save → PlateTTS(setEnabled/updateFilters) → FG(sendDataToTask) → snackbar_helper
  Future<void> _apply(TtsUserFilters next) async {
    if (_applying) return;

    setState(() {
      _filters = next;
      _applying = true;
    });

    try {
      await TtsSyncHelper.apply(
        context,
        next,
        save: true,
        showSnackbar: true,
        successMessage: 'TTS 알림 설정이 적용되었습니다.',
      );
    } catch (_) {
      // 실패 스낵바는 helper가 처리
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'TTS 알림 설정',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_applying)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _SwitchTile(
              title: '입차 요청',
              value: _filters.parking,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(parking: v)),
            ),
            _SwitchTile(
              title: '출차 요청',
              value: _filters.departure,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(departure: v)),
            ),
            _SwitchTile(
              title: '출차 완료(2회)',
              value: _filters.completed,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(completed: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
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
