import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/chat_account_scope.dart';
import '../controllers/area_chat_inbox_controller.dart';
import 'area_chat_status_dialog.dart';

class AreaChatInboxScope extends StatefulWidget {
  const AreaChatInboxScope({
    super.key,
    required this.areaNames,
    required this.builder,
    this.notificationsEnabled = true,
    this.suppressedAreaNames = const <String>[],
  });

  final List<String> areaNames;
  final Widget Function(
    BuildContext context,
    AreaChatInboxSnapshot snapshot,
    String currentUserId,
  ) builder;
  final bool notificationsEnabled;
  final List<String> suppressedAreaNames;

  @override
  State<AreaChatInboxScope> createState() => _AreaChatInboxScopeState();
}

class _AreaChatInboxScopeState extends State<AreaChatInboxScope> {
  late final AreaChatInboxController _controller;
  String _lastDeveloperErrorSignature = '';

  @override
  void initState() {
    super.initState();
    _controller = AreaChatInboxController()..startReadReceiptStream();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant AreaChatInboxScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaNames.join('\u0001') !=
            widget.areaNames.join('\u0001') ||
        oldWidget.notificationsEnabled != widget.notificationsEnabled ||
        oldWidget.suppressedAreaNames.join('\u0001') !=
            widget.suppressedAreaNames.join('\u0001')) {
      _configure();
    }
  }

  void _configure([ChatAccountScope? providedScope]) {
    final scope = providedScope ??
        ChatAccountScope.fromSession(context.read<UserState>().session);
    _controller.configure(
      division: scope.division,
      selectedArea: scope.selectedArea,
      areaNames: widget.areaNames,
      currentUserId: scope.userId,
      notificationsEnabled: widget.notificationsEnabled,
      suppressedAreaNames: widget.suppressedAreaNames,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final accountScope = ChatAccountScope.fromSession(userState.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configure(accountScope);
    });
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        _showDeveloperChatIndexDialogIfNeeded(snapshot);
        return widget.builder(
          context,
          snapshot,
          accountScope.userId,
        );
      },
    );
  }

  void _showDeveloperChatIndexDialogIfNeeded(AreaChatInboxSnapshot snapshot) {
    final failure = snapshot.failure;
    if (failure == null || !failure.isIndexRequired) {
      _lastDeveloperErrorSignature = '';
      return;
    }
    if (failure.signature == _lastDeveloperErrorSignature) return;
    _lastDeveloperErrorSignature = failure.signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accountScope =
          ChatAccountScope.fromSession(context.read<UserState>().session);
      unawaited(
        AreaChatStatusDialog.showIndexFailure(
          context,
          failure: failure,
          details: <String, Object?>{
            'division': accountScope.division,
            'selectedArea': accountScope.selectedArea,
            'areaNames': widget.areaNames.join(', '),
            'currentUserId': accountScope.userId,
          },
        ),
      );
    });
  }
}
