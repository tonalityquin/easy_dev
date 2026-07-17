import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../shared/tts/application/tts_sync_helper.dart';
import '../../../../shared/tts/application/tts_user_filters.dart';
import '../../../dev/application/area_state.dart';

class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  static const _prefsLockedKey = 'dashboard_setting_locked';

  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;
  bool _applying = false;
  bool _refreshing = false;
  bool _locked = true;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadLockState(), _load()]);
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (!mounted) return;
    setState(() => _locked = locked ?? true);
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();
    final prefs = await SharedPreferences.getInstance();
    final lastRefreshAt = DateTime.tryParse(
      prefs.getString(OperationalDataSyncWorkflow.lastSyncAtKey) ?? '',
    );

    try {
      await TtsSyncHelper.apply(
        context,
        loaded,
        save: false,
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('TTS 초기 동기화 실패: $e');
    }

    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _lastRefreshAt = lastRefreshAt;
      _loading = false;
    });
  }

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
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('TTS 적용 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _applying = false);
    }
  }

  Future<void> _resendToForeground() async {
    try {
      await TtsSyncHelper.apply(
        context,
        _filters,
        save: false,
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('FG 재전송 실패: $e');
    }
  }

  Future<void> _manualRefreshAll() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);
    try {
      await OperationalDataSyncWorkflow.run(context: context);
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
    );
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style =
        (base ?? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))
            .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
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
              label: 'screen_tag: Setting',
              child: Text('Setting', style: style),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLock() async {
    final next = !_locked;
    setState(() => _locked = next);
    await _saveLockState(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final currentArea = context.select<AreaState, String>((s) => s.currentArea);

    final bodyList = <Widget>[
      const SizedBox(height: 4),
      const _HeaderBanner(),
      const SizedBox(height: 12),
      if (currentArea.isEmpty)
        const _Section(
          title: '지역 설정 필요',
          icon: Icons.info_outline,
          tone: _Tone.warning,
          child: Text(
            '현재 지역 정보가 비어 있습니다. FG 서비스에서 지역 기반 구독을 사용하는 경우, 지역 설정 완료 후 다시 적용하세요.',
          ),
        ),
      _Section(
        title: 'TTS 알림 설정',
        icon: Icons.record_voice_over_rounded,
        subtitle: '스위치를 변경하면 즉시 저장되고 FG 서비스에 적용됩니다.',
        trailing: _applying
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        child: Column(
          children: [
            _SwitchTile(
              title: '입차 요청',
              subtitle: '입차 요청 발생 시 음성 안내',
              value: _filters.parking,
              onChanged: _applying
                  ? null
                  : (v) => _apply(_filters.copyWith(parking: v)),
              icon: Icons.local_parking_rounded,
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.75)),
            _SwitchTile(
              title: '출차 요청',
              subtitle: '출차 요청 발생 시 음성 안내',
              value: _filters.departure,
              onChanged: _applying
                  ? null
                  : (v) => _apply(_filters.copyWith(departure: v)),
              icon: Icons.exit_to_app_rounded,
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.75)),
            _SwitchTile(
              title: '출차 완료(2회)',
              subtitle: '출차 완료 발생 시 2회 안내',
              value: _filters.completed,
              onChanged: _applying
                  ? null
                  : (v) => _apply(_filters.copyWith(completed: v)),
              icon: Icons.done_all_rounded,
            ),
          ],
        ),
      ),
      _Section(
        title: '현재 지역',
        icon: Icons.place_outlined,
        child: Row(
          children: [
            Expanded(
              child: Text(
                currentArea.isEmpty ? '(미설정)' : currentArea,
                style:
                    (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _loading ? null : _resendToForeground,
              icon: const Icon(Icons.send),
              label: const Text('재적용'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(1, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ],
        ),
      ),
      _Section(
        title: '데이터 새로고침',
        icon: Icons.refresh_rounded,
        subtitle: '주차 구역/정산 데이터를 수동으로 동기화합니다.',
        trailing: _refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (_lastRefreshAt != null
                ? _Pill(text: '마지막: ${_formatLastSync(_lastRefreshAt!)}')
                : null),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading || _refreshing ? null : _manualRefreshAll,
                icon: _refreshing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(cs.onPrimary),
                        ),
                      )
                    : const Icon(Icons.sync),
                label: const Text('지금 새로고침'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
      _Section(
        title: '로그아웃',
        icon: Icons.logout_rounded,
        tone: _Tone.danger,
        subtitle: '포그라운드 서비스를 중지하고 로그인 화면(허브 선택 경유)으로 이동합니다.',
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _loading ? null : _logout,
                icon: const Icon(Icons.logout),
                label: const Text('로그아웃'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];

    final listView = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _manualRefreshAll,
            edgeOffset: 80,
            color: cs.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: bodyList,
            ),
          );

    final content = Stack(
      children: [
        AbsorbPointer(
          absorbing: _locked,
          child: listView,
        ),
        if (_locked)
          Positioned.fill(
            child: Container(
              color: cs.scrim.withOpacity(0.10),
              alignment: Alignment.center,
              child: _LockOverlay(onUnlock: _toggleLock),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('대시보드 설정'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child:
              Container(height: 1, color: cs.outlineVariant.withOpacity(.70)),
        ),
        actions: [
          IconButton(
            tooltip: _locked ? '잠금 해제' : '잠금',
            onPressed: _loading ? null : _toggleLock,
            icon: Icon(_locked ? Icons.lock_rounded : Icons.lock_open_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: content,
    );
  }
}

enum _Tone { neutral, warning, danger }

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle =
        (tt.titleLarge ?? const TextStyle(fontSize: 20)).copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );
    final subStyle = (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
      color: cs.onSurfaceVariant,
      height: 1.25,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.tune_rounded, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('설정', style: titleStyle),
                const SizedBox(height: 4),
                Text('TTS 및 주요 동기화/세션 기능을 제어합니다.', style: subStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final _Tone tone;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Color border;
    Color bg;
    Color iconColor;

    switch (tone) {
      case _Tone.warning:
        border = Colors.amber.withOpacity(.35);
        bg = Color.alphaBlend(Colors.amber.withOpacity(.14), cs.surface);
        iconColor = Colors.amber.shade800;
        break;
      case _Tone.danger:
        border = cs.error.withOpacity(.35);
        bg = cs.errorContainer.withOpacity(.45);
        iconColor = cs.error;
        break;
      case _Tone.neutral:
        border = cs.outlineVariant.withOpacity(.85);
        bg = cs.surfaceContainerLow;
        iconColor = cs.primary;
        break;
    }

    final titleStyle =
        (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurface,
    );
    final subStyle = (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
      color: cs.onSurfaceVariant,
      height: 1.25,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: titleStyle)),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: subStyle),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle = (tt.bodyLarge ?? const TextStyle(fontSize: 14)).copyWith(
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    );
    final subStyle = (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
      color: cs.onSurfaceVariant,
    );

    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      minLeadingWidth: 24,
      leading: Icon(icon, color: cs.primary),
      title: Text(title, style: titleStyle),
      subtitle: (subtitle == null) ? null : Text(subtitle!, style: subStyle),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final style = (tt.labelSmall ?? const TextStyle(fontSize: 11.5)).copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
      ),
      child: Text(text, style: style),
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle =
        (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );
    final bodyStyle =
        (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
      color: cs.onSurfaceVariant,
      height: 1.25,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(.65),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
              ),
              child: Icon(Icons.lock_rounded, color: cs.primary),
            ),
            const SizedBox(height: 10),
            Text('잠금 상태', style: titleStyle),
            const SizedBox(height: 6),
            Text(
              '설정 변경을 막기 위해 화면이 잠겨 있습니다.\n오른쪽 상단의 잠금 버튼 또는 아래 버튼으로 해제할 수 있습니다.',
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('잠금 해제'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
