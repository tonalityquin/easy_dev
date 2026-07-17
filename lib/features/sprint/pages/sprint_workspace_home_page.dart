import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_mode_home_page.dart';
import 'sprint_project_archive_page.dart';
import 'sprint_project_completion_page.dart';
import 'sprint_project_home_page.dart';
import 'sprint_project_management_page.dart';
import 'sprint_project_workspace_sheet.dart';

class SprintWorkspaceHomePage extends StatefulWidget {
  const SprintWorkspaceHomePage({
    super.key,
    required this.store,
    this.returnRouteName,
  });

  final SprintModeStore store;
  final String? returnRouteName;

  @override
  State<SprintWorkspaceHomePage> createState() =>
      _SprintWorkspaceHomePageState();
}

class _SprintWorkspaceHomePageState extends State<SprintWorkspaceHomePage>
    with WidgetsBindingObserver {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.store.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.store.flush());
    widget.store.dispose();
    super.dispose();
  }

  Route<void> _route(Widget page) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PageRouteBuilder<void>(
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
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
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openDestination(SprintWorkspacePanelResult result) async {
    widget.store.selectScope(result.scope);
    switch (result.destination) {
      case SprintWorkspacePanelDestination.schedule:
        await Navigator.of(context).push<void>(
          _route(
            SprintModeHomePage(
              store: widget.store,
              disposeStore: false,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.summary:
      case SprintWorkspacePanelDestination.path:
        if (result.scope.type != SprintWorkspaceScopeType.project) return;
        await Navigator.of(context).push<void>(
          _route(
            SprintProjectHomePage(
              store: widget.store,
              initialDestination: result.destination,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.attention:
        await showSprintAttentionSheet(
          context: context,
          store: widget.store,
        );
        return;
      case SprintWorkspacePanelDestination.management:
        if (result.scope.type != SprintWorkspaceScopeType.project) return;
        await Navigator.of(context).push<void>(
          _route(
            SprintProjectManagementPage(
              store: widget.store,
              projectId: result.scope.projectId!,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.completion:
        if (result.scope.type != SprintWorkspaceScopeType.project) return;
        await Navigator.of(context).push<void>(
          _route(
            SprintProjectCompletionPage(
              store: widget.store,
              projectId: result.scope.projectId!,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.archive:
        await Navigator.of(context).push<void>(
          _route(SprintProjectArchivePage(store: widget.store)),
        );
        return;
    }
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    try {
      await widget.store.flush();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final returnRouteName = widget.returnRouteName?.trim();
      if (returnRouteName != null && returnRouteName.isNotEmpty) {
        navigator.pushReplacementNamed(returnRouteName);
        return;
      }
      if (navigator.canPop()) {
        navigator.pop();
        return;
      }
      navigator.pushReplacementNamed(AppRoutes.selector);
    } finally {
      if (mounted) _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        unawaited(_close());
      },
      child: SprintWorkspacePanelPage(
        store: widget.store,
        onClose: () => unawaited(_close()),
        onResult: _openDestination,
      ),
    );
  }
}
