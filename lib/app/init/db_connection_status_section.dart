import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../design_system/prompt_ui/prompt_ui_theme.dart';
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
    this.usePromptUi = false,
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;
  final bool usePromptUi;

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
              usePromptUi: usePromptUi,
            ),
            _StatusChip(
              label: liveLabel,
              value: snapshot.liveDbOn,
              usePromptUi: usePromptUi,
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
    this.usePromptUi = false,
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;
  final bool usePromptUi;

  @override
  Widget build(BuildContext context) {
    return _DbConnectionStatusObserver(
      builder: (context, snapshot) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AppBarStatusChip(
              label: liveLabel,
              value: snapshot.liveDbOn,
              usePromptUi: usePromptUi,
            ),
            SizedBox(height: spacing),
            _AppBarStatusChip(
              label: storageLabel,
              value: snapshot.storageDbOn,
              usePromptUi: usePromptUi,
            ),
          ],
        );
      },
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
  required bool usePromptUi,
}) {
  if (usePromptUi) {
    final tokens = PromptUiTheme.of(context);
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
    required this.usePromptUi,
  });

  final String label;
  final bool value;
  final bool usePromptUi;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = _resolveStatusColors(
      context,
      value: value,
      usePromptUi: usePromptUi,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
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
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
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

class _AppBarStatusChip extends StatelessWidget {
  const _AppBarStatusChip({
    required this.label,
    required this.value,
    required this.usePromptUi,
  });

  final String label;
  final bool value;
  final bool usePromptUi;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = _resolveStatusColors(
      context,
      value: value,
      usePromptUi: usePromptUi,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1,
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            child: Text(
              value ? 'ON' : 'OFF',
              key: ValueKey<bool>(value),
              style:
                  (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
