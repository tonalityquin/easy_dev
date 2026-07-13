import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../application/chat_account_scope.dart';
import '../application/chat_area_key.dart';
import 'area_chat_alert_watcher.dart';
import 'headquarter_chat_alert_watcher.dart';

class WorkChatAlertHost extends StatelessWidget {
  const WorkChatAlertHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final scope = ChatAccountScope.fromSession(userState.session);
    final enabled = userState.isLoggedIn && scope.isWorking && scope.isValid;

    if (!enabled) return child;

    return _WorkChatAlertActive(
      key: ValueKey<String>(scope.key),
      scope: scope,
      child: child,
    );
  }
}

class _WorkChatAlertActive extends StatefulWidget {
  const _WorkChatAlertActive({
    super.key,
    required this.scope,
    required this.child,
  });

  final ChatAccountScope scope;
  final Widget child;

  @override
  State<_WorkChatAlertActive> createState() => _WorkChatAlertActiveState();
}

class _WorkChatAlertActiveState extends State<_WorkChatAlertActive>
    with WidgetsBindingObserver {
  List<String> _areaNames = const <String>[];
  bool _activeLifecycle = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _areaNames = _baseAreaNames(widget.scope);
    _loadAreaNames();
  }

  @override
  void didUpdateWidget(covariant _WorkChatAlertActive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.key != widget.scope.key) {
      _areaNames = _baseAreaNames(widget.scope);
      _loadAreaNames();
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached && _activeLifecycle) {
      setState(() {
        _activeLifecycle = false;
      });
    }
  }

  List<String> _baseAreaNames(ChatAccountScope scope) {
    if (scope.isHeadquarter) return const <String>[];
    return scope.selectedArea.isEmpty
        ? const <String>[]
        : <String>[scope.selectedArea];
  }

  List<String> _uniqueAreas(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final area = value.trim();
      if (area.isEmpty || isHeadquarterChatAreaName(area)) continue;
      final areaKey = normalizeChatAreaKey(area);
      if (areaKey.isEmpty || !seen.add(areaKey)) continue;
      result.add(area);
    }
    result.sort();
    return result;
  }

  bool _sameList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _loadAreaNames() async {
    final generation = ++_loadGeneration;
    final scope = widget.scope;

    if (!scope.isHeadquarter) {
      final resolved = _baseAreaNames(scope);
      if (!mounted || generation != _loadGeneration) return;
      if (_sameList(_areaNames, resolved)) return;
      setState(() {
        _areaNames = resolved;
      });
      return;
    }

    var resolved = const <String>[];
    try {
      final areaRepository = context.read<AreaRepository>();
      final fetched =
          await areaRepository.getAreaNamesByDivision(scope.division);
      resolved = _uniqueAreas(
        fetched.where(
          (area) => !sameChatIdentity(area, scope.division),
        ),
      );
    } catch (_) {
      resolved = const <String>[];
    }

    if (!mounted || generation != _loadGeneration || !_activeLifecycle) return;
    if (_sameList(_areaNames, resolved)) return;
    setState(() {
      _areaNames = resolved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeLifecycle && widget.scope.isValid;
    return HeadquarterChatAlertWatcher(
      enabled: active && widget.scope.isHeadquarter,
      child: AreaChatAlertWatcher(
        areaNames: _areaNames,
        enabled: active && _areaNames.isNotEmpty,
        child: widget.child,
      ),
    );
  }
}
