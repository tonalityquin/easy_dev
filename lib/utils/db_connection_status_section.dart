import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firebase_google_auth_bridge.dart';
import 'auth/google_auth_session.dart';

@immutable
class DbConnectionSnapshot {
  final bool storageDbOn;
  final bool liveDbOn;

  const DbConnectionSnapshot({
    required this.storageDbOn,
    required this.liveDbOn,
  });

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
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;

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
            ),
            _StatusChip(
              label: liveLabel,
              value: snapshot.liveDbOn,
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
  });

  final String storageLabel;
  final String liveLabel;
  final double spacing;

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
            ),
            SizedBox(height: spacing),
            _AppBarStatusChip(
              label: storageLabel,
              value: snapshot.storageDbOn,
            ),
          ],
        );
      },
    );
  }
}

class _DbConnectionStatusObserver extends StatefulWidget {
  const _DbConnectionStatusObserver({
    required this.builder,
  });

  final Widget Function(BuildContext context, DbConnectionSnapshot snapshot)
  builder;

  @override
  State<_DbConnectionStatusObserver> createState() =>
      _DbConnectionStatusObserverState();
}

class _DbConnectionStatusObserverState extends State<_DbConnectionStatusObserver> {
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
  });

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    const onColor = Color(0xFF1FAA59);
    const offColor = Color(0xFFD64545);
    final activeColor = value ? onColor : offColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: activeColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: activeColor.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value ? 'ON' : 'OFF',
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: activeColor,
              letterSpacing: 0.2,
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
  });

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const onColor = Color(0xFF1FAA59);
    const offColor = Color(0xFFD64545);
    final activeColor = value ? onColor : offColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activeColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: activeColor.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: activeColor,
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
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value ? 'ON' : 'OFF',
            style: (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
              color: activeColor,
            ),
          ),
        ],
      ),
    );
  }
}
