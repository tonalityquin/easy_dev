import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../dev/application/area_state.dart';
import '../schedule/weekly_work_schedule_editor.dart';

enum MyInfoEntrySource {
  hqDashboard,
}

Future<void> showMyInfoDialog({
  required BuildContext context,
  required MyInfoEntrySource source,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '내 정보 닫기',
    barrierColor: Colors.black54,
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => MyInfoDialog(source: source),
    transitionBuilder: (_, animation, __, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class MyInfoDialog extends StatefulWidget {
  const MyInfoDialog({
    super.key,
    required this.source,
  });

  final MyInfoEntrySource source;

  @override
  State<MyInfoDialog> createState() => _MyInfoDialogState();
}

class _MyInfoDialogState extends State<MyInfoDialog> {
  bool _loading = true;
  String _name = '';
  String _phone = '';
  String _area = '';
  String _division = '';
  String _role = '';
  String _position = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _printDebug('open');
    });
    _loadPrefs();
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  bool get _weeklyScheduleVisible =>
      widget.source == MyInfoEntrySource.hqDashboard;

  String get _sourceKey {
    switch (widget.source) {
      case MyInfoEntrySource.hqDashboard:
        return 'hq_dashboard';
    }
  }

  String _debugMessage(String event) {
    final fields = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'source': _sourceKey,
      'event': event,
      'profileVisible': true,
      'operationalDataVisible': false,
      'sessionLogoutVisible': false,
      'weeklyScheduleVisible': _weeklyScheduleVisible,
      'areaConfigured': _area.trim().isNotEmpty,
      'divisionConfigured': _division.trim().isNotEmpty,
      'loading': _loading,
    };
    return '[MY_INFO] ${fields.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}';
  }

  void _printDebug(String event) {
    debugPrint(_debugMessage(event));
  }

  Future<void> _showDeveloperDebugStatus() async {
    HapticFeedback.mediumImpact();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '내정보 상태',
      initialMessage: '내 정보 Dialog 상태를 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    trace.log('component=my_info_dialog', progress: 0.18);
    trace.log('source=$_sourceKey', progress: 0.32);
    trace.log('profileVisible=true', progress: 0.46);
    trace.log('weeklyScheduleVisible=$_weeklyScheduleVisible', progress: 0.6);
    trace.log('areaConfigured=${_area.trim().isNotEmpty}', progress: 0.72);
    trace.log(
      'divisionConfigured=${_division.trim().isNotEmpty}',
      progress: 0.84,
    );
    trace.log('loading=$_loading', progress: 0.94);
    await trace.succeed('내 정보 Dialog 상태 확인을 완료했습니다.');
  }

  Future<void> _loadPrefs() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final currentArea = context.read<AreaState>().currentArea.trim();
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeJsonMap(prefs.getString('cachedUserJson') ?? '');
    final prefsPhone = (prefs.getString('phone') ?? '').trim();
    final prefsArea = (prefs.getString('selectedArea') ?? '').trim();
    final effectiveArea = currentArea.isNotEmpty ? currentArea : prefsArea;
    final name = ((cached['name'] as String?) ?? '').trim();
    final phoneFromCached = ((cached['phone'] as String?) ?? '').trim();

    if (!mounted) return;
    setState(() {
      _name = name;
      _phone = prefsPhone.isNotEmpty ? prefsPhone : phoneFromCached;
      _area = effectiveArea;
      _division = (prefs.getString('division') ?? '').trim();
      _role = (prefs.getString('role') ?? '').trim();
      _position = (prefs.getString('position') ?? '').trim();
      _loading = false;
    });
    _printDebug('local_state_loaded');
  }

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;

    Widget reveal(int order, Widget child) {
      if (reduceMotion) return child;
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Duration(milliseconds: 240 + (order * 55)),
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, value, animatedChild) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 10),
              child: Transform.scale(
                scale: 0.985 + (0.015 * value),
                alignment: Alignment.topCenter,
                child: animatedChild,
              ),
            ),
          );
        },
      );
    }

    Widget loadingBody() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.action),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '근무자 정보를 불러오는 중입니다.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final loadedContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        reveal(
          0,
          _UserInfoCard(
            name: _name,
            position: _position,
            role: _role,
            phone: _phone,
            area: _area,
            division: _division,
          ),
        ),
        if (_weeklyScheduleVisible) ...[
          const SizedBox(height: 14),
          reveal(
            1,
            const WeeklyWorkScheduleEditor(
              source: 'hq_my_info',
              initiallyExpanded: true,
            ),
          ),
        ],
        const SizedBox(height: 14),
        reveal(
          _weeklyScheduleVisible ? 2 : 1,
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: palette.panel,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('닫기'),
            ),
          ),
        ),
      ],
    );

    final content = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (reduceMotion) return child;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _loading
          ? KeyedSubtree(
              key: const ValueKey<String>('loading'),
              child: loadingBody(),
            )
          : KeyedSubtree(
              key: ValueKey<String>('content-$_sourceKey'),
              child: loadedContent,
            ),
    );

    return Dialog(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: media.size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogConsoleHeader(
              area: _area,
              loading: _loading,
              onClose: () => Navigator.of(context).pop(),
              onLongPress: _showDeveloperDebugStatus,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsPalette {
  const _OpsPalette({
    required this.ink,
    required this.muted,
    required this.canvas,
    required this.panel,
    required this.line,
    required this.action,
    required this.softLabel,
    required this.headerBorder,
  });

  final Color ink;
  final Color muted;
  final Color canvas;
  final Color panel;
  final Color line;
  final Color action;
  final Color softLabel;
  final Color headerBorder;

  factory _OpsPalette.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseCanvas = cs.brightness == Brightness.dark
        ? cs.surface
        : const Color(0xFFF3F6FA);
    return _OpsPalette(
      ink: cs.brightness == Brightness.dark
          ? const Color(0xFFF0F4F8)
          : const Color(0xFF101828),
      muted: cs.brightness == Brightness.dark
          ? const Color(0xFFAAB6C5)
          : const Color(0xFF667085),
      canvas: Color.alphaBlend(
        cs.primary.withOpacity(cs.brightness == Brightness.dark ? .08 : .03),
        baseCanvas,
      ),
      panel: cs.surface,
      line: Color.alphaBlend(cs.primary.withOpacity(.04), cs.outlineVariant),
      action: cs.primary,
      softLabel: const Color(0xFFB8C2D6),
      headerBorder: const Color(0xFF2B3A4F),
    );
  }
}

class _DialogConsoleHeader extends StatelessWidget {
  const _DialogConsoleHeader({
    required this.area,
    required this.loading,
    required this.onClose,
    required this.onLongPress,
  });

  final String area;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final cs = Theme.of(context).colorScheme;
    final areaLabel =
        area.trim().isEmpty ? '운영 지점 미설정' : '${area.trim()} 운영 콘솔';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF101828),
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.24),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.action,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(.14)),
                  ),
                  child: Icon(
                    Icons.badge_rounded,
                    color: cs.onPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '내 정보',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loading ? '근무자 프로필을 준비하고 있습니다.' : areaLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: palette.softLabel,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  tooltip: '닫기',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({
    required this.name,
    required this.position,
    required this.role,
    required this.phone,
    required this.area,
    required this.division,
  });

  final String name;
  final String position;
  final String role;
  final String phone;
  final String area;
  final String division;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return _OpsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.assignment_ind_rounded,
            title: '근무자 정보',
            subtitle: '계정과 현장 배정 정보를 확인합니다.',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF101828),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.headerBorder),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: palette.softLabel,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _safeText(name),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                        color: palette.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InfoPill(
                          icon: Icons.workspace_premium_rounded,
                          label: '직책',
                          value: _safeText(position),
                        ),
                        _InfoPill(
                          icon: Icons.admin_panel_settings_rounded,
                          label: '권한',
                          value: _safeText(role),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: palette.line),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.phone_rounded,
                label: '연락처',
                value: _safeText(phone),
                expanded: true,
              ),
              _InfoPill(
                icon: Icons.location_on_rounded,
                label: '지역',
                value: _safeText(area),
                expanded: true,
              ),
              _InfoPill(
                icon: Icons.apartment_rounded,
                label: '구역',
                value: _safeText(division),
                expanded: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpsPanel extends StatelessWidget {
  const _OpsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.line),
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF101828),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: palette.softLabel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.action.withOpacity(.025),
          palette.panel,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: palette.muted),
          const SizedBox(width: 7),
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: palette.muted,
            ),
          ),
          Flexible(
            child: Text(
              _safeText(value),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: palette.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (!expanded) return content;
    return SizedBox(width: 170, child: content);
  }
}

String _safeText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '-' : trimmed;
}
