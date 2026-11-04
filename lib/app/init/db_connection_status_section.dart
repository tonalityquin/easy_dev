import 'dart:async';

import '../diagnostics/firebase_activity_meter.dart';
import '../diagnostics/firebase_activity_center_dialog.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../auth/google_auth_session.dart';

@immutable
class DbConnectionSnapshot {
  const DbConnectionSnapshot({
    required this.storageDbOn,
    required this.liveDbOn,
  });

  final bool storageDbOn;
  final bool liveDbOn;

  factory DbConnectionSnapshot.read() {
    final googleUser = GoogleAuthSession.instance.currentUser;
    final storageDbOn =
        googleUser != null && !GoogleAuthSession.instance.isSessionBlocked;

    final firebaseUser = FirebaseGoogleAuthBridge.instance.currentUser;
    final liveDbOn = firebaseUser != null && !firebaseUser.isAnonymous;

    return DbConnectionSnapshot(
      storageDbOn: storageDbOn,
      liveDbOn: liveDbOn,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DbConnectionSnapshot &&
        other.storageDbOn == storageDbOn &&
        other.liveDbOn == liveDbOn;
  }

  @override
  int get hashCode => Object.hash(storageDbOn, liveDbOn);
}

class DbConnectionStatusSection extends StatelessWidget {
  const DbConnectionStatusSection({
    super.key,
    this.storageLabel = '스토리지 DB',
    this.liveLabel = 'live DB',
    this.spacing = 8,
    this.useCommonUi = false,
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;
  final bool useCommonUi;

  @override
  Widget build(BuildContext context) {
    return _DbConnectionStatusObserver(
      builder: (context, snapshot) {
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: 6,
          children: [
            _StatusChip(
              label: storageLabel,
              value: snapshot.storageDbOn,
              useCommonUi: useCommonUi,
            ),
            _StatusChip(
              label: liveLabel,
              value: snapshot.liveDbOn,
              useCommonUi: useCommonUi,
            ),
          ],
        );
      },
    );
  }
}

class DbConnectionStatusAppBarSection extends StatelessWidget {
  const DbConnectionStatusAppBarSection({
    super.key,
    this.storageLabel = '스토리지 DB',
    this.liveLabel = 'live DB',
    this.spacing = 4,
    this.useCommonUi = false,
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;
  final bool useCommonUi;

  @override
  Widget build(BuildContext context) {
    return _DbConnectionStatusObserver(
      builder: (context, snapshot) {
        return ValueListenableBuilder<FirebaseActivitySummary>(
          valueListenable: FirebaseActivityMeter.instance.summary,
          builder: (context, activity, _) {
            final reduceMotion =
                MediaQuery.maybeOf(context)?.disableAnimations ?? false;
            final tokens = Theme.of(context).colorScheme;
            final duration = reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220);
            void openActivityCenter() {
              unawaited(FirebaseActivityCenterDialog.open(context));
            }

            return Semantics(
              button: true,
              label: 'Firebase Activity Center, '
                  'LIVE DB ${snapshot.liveDbOn ? 'ON' : 'OFF'}, '
                  'STORAGE DB ${snapshot.storageDbOn ? 'ON' : 'OFF'}, '
                  'READ ${activity.read}, WRITE ${activity.write}, '
                  'DELETE ${activity.delete}, SNAP ${activity.snap}, '
                  'LISTEN ${activity.activeListeners}, '
                  'STORAGE ${activity.storage}',
              onTap: openActivityCenter,
              child: ExcludeSemantics(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: openActivityCenter,
                    child: AnimatedContainer(
                      width: 116,
                      height: 48,
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _ActivityConnectionLine(
                              'LIVE DB',
                              snapshot.liveDbOn,
                              reduceMotion: reduceMotion,
                              showChevron: true,
                            ),
                          ),
                          Expanded(
                            child: _ActivityConnectionLine(
                              'STORAGE DB',
                              snapshot.storageDbOn,
                              reduceMotion: reduceMotion,
                            ),
                          ),
                          Expanded(
                            child: _ActivityCountsLine(
                              'R ${_compactActivityCount(activity.read)}  ·  '
                              'W ${_compactActivityCount(activity.write)}  ·  '
                              'D ${_compactActivityCount(activity.delete)}',
                              duration: duration,
                            ),
                          ),
                          Expanded(
                            child: _ActivityCountsLine(
                              'SN ${_compactActivityCount(activity.snap)}  ·  '
                              'L ${_compactActivityCount(activity.activeListeners)}  ·  '
                              'ST ${_compactActivityCount(activity.storage)}',
                              duration: duration,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _compactActivityCount(int value) {
  if (value < 1000) return '$value';
  if (value < 10000) return '${(value / 1000).toStringAsFixed(1)}K';
  if (value < 1000000) return '${(value / 1000).round()}K';
  if (value < 10000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value < 1000000000) return '${(value / 1000000).round()}M';
  return '${(value / 1000000000).toStringAsFixed(1)}B';
}

class _ActivityConnectionLine extends StatelessWidget {
  const _ActivityConnectionLine(
    this.label,
    this.connected, {
    required this.reduceMotion,
    this.showChevron = false,
  });

  final String label;
  final bool connected;
  final bool reduceMotion;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF1FAA59) : const Color(0xFFD64545);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    return Row(
      children: [
        AnimatedContainer(
          duration: duration,
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 8.3,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(width: 4),
        AnimatedSwitcher(
          duration: duration,
          child: Text(
            connected ? 'ON' : 'OFF',
            key: ValueKey<bool>(connected),
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 8.3,
              fontWeight: FontWeight.w800,
              height: 1,
              color: color,
            ),
          ),
        ),
        if (showChevron) ...[
          const Spacer(),
          Icon(
            Icons.chevron_right_rounded,
            size: 11,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

class _ActivityCountsLine extends StatelessWidget {
  const _ActivityCountsLine(this.value, {required this.duration});

  final String value;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              value,
              key: ValueKey<String>(value),
              textAlign: TextAlign.right,
              textScaler: TextScaler.noScaling,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DbConnectionStatusObserver extends StatefulWidget {
  const _DbConnectionStatusObserver({required this.builder});

  final Widget Function(BuildContext context, DbConnectionSnapshot snapshot)
      builder;

  @override
  State<_DbConnectionStatusObserver> createState() =>
      _DbConnectionStatusObserverState();
}

class _DbConnectionStatusObserverState
    extends State<_DbConnectionStatusObserver> {
  late final ValueNotifier<DbConnectionSnapshot> _snapshotNotifier;
  StreamSubscription<User?>? _firebaseSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _snapshotNotifier = ValueNotifier<DbConnectionSnapshot>(
      DbConnectionSnapshot.read(),
    );

    _firebaseSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _refresh();
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refresh();
    });
  }

  void _refresh() {
    final next = DbConnectionSnapshot.read();
    if (next != _snapshotNotifier.value) {
      _snapshotNotifier.value = next;
    }
  }

  @override
  void dispose() {
    _firebaseSub?.cancel();
    _pollTimer?.cancel();
    _snapshotNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DbConnectionSnapshot>(
      valueListenable: _snapshotNotifier,
      builder: (context, snapshot, _) => widget.builder(context, snapshot),
    );
  }
}

class _StatusColors {
  const _StatusColors({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color accent;
  final Color border;
}

_StatusColors _resolveStatusColors(
  BuildContext context, {
  required bool value,
  required bool useCommonUi,
}) {
  if (useCommonUi) {
    final tokens = CommonUiTheme.of(context);
    final accent = value ? tokens.success : tokens.danger;
    return _StatusColors(
      background: value ? tokens.successContainer : tokens.dangerContainer,
      foreground:
          value ? tokens.onSuccessContainer : tokens.onDangerContainer,
      accent: accent,
      border: accent.withOpacity(tokens.isDark ? 0.58 : 0.34),
    );
  }

  const onColor = Color(0xFF1FAA59);
  const offColor = Color(0xFFD64545);
  final accent = value ? onColor : offColor;
  return _StatusColors(
    background: accent.withOpacity(0.10),
    foreground: Theme.of(context).colorScheme.onSurface,
    accent: accent,
    border: accent.withOpacity(0.20),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.useCommonUi,
  });

  final String label;
  final bool value;
  final bool useCommonUi;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = _resolveStatusColors(
      context,
      value: value,
      useCommonUi: useCommonUi,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Text(
              value ? 'ON' : 'OFF',
              key: ValueKey<bool>(value),
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.accent,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
