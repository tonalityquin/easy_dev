import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/chat_area_key.dart';
import '../controllers/area_chat_inbox_controller.dart';

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
    if (oldWidget.areaNames.join('\u0001') != widget.areaNames.join('\u0001') ||
        oldWidget.notificationsEnabled != widget.notificationsEnabled ||
        oldWidget.suppressedAreaNames.join('\u0001') != widget.suppressedAreaNames.join('\u0001')) {
      _configure();
    }
  }

  void _configure() {
    final currentUserId = context.read<UserState>().session?.id ?? '';
    final suppressedAreaKeys = widget.suppressedAreaNames
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .map(normalizeChatAreaKey)
        .toSet();
    _controller.configure(
      areaNames: widget.areaNames,
      currentUserId: currentUserId,
      notificationsEnabled: widget.notificationsEnabled,
      suppressedAreaKeys: suppressedAreaKeys,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<UserState>().session?.id ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configure();
    });
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return widget.builder(
          context,
          _controller.snapshot,
          currentUserId,
        );
      },
    );
  }
}
