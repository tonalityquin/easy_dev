import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../app/firebase_activity/firebase_activity_monitor.dart';
import '../../selector/application/dev_auth.dart';
import '../data/services/company_bootstrap_service.dart';
import '../data/services/account_initialization_guard.dart';

class InitialAccountSetupDialog extends StatefulWidget {
  const InitialAccountSetupDialog({super.key});

  static Future<void> open(BuildContext context) async {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '최초 계정 설정',
      barrierColor: Colors.black54,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const InitialAccountSetupDialog(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<InitialAccountSetupDialog> createState() =>
      _InitialAccountSetupDialogState();
}

class _InitialAccountSetupDialogState extends State<InitialAccountSetupDialog> {
  final CompanyBootstrapService _service = const CompanyBootstrapService();
  final TextEditingController _password = TextEditingController();
  final List<String> _log = <String>[];
  BootstrapPreview? _preview;
  Set<String>? _retryCompanyIds;
  final Set<String> _completedCompanyIds = <String>{};
  final Set<String> _syncPendingCompanyIds = <String>{};
  InitialAccountCreationResult? _lastResult;
  bool _busy = false;
  bool _authorized = false;
  String _message = '개발자 인증';

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String _errorCode(Object error) {
    if (error is StateError) {
      final value = error.message.toString().split(':').first;
      return RegExp(r'^[A-Z0-9_]+$').hasMatch(value)
          ? value : 'INITIAL_SETUP_STATE_ERROR';
    }
    if (error is FirebaseException) {
      return 'FIREBASE_${error.code.toUpperCase().replaceAll('-', '_')}';
    }
    return error.runtimeType.toString();
  }

  void _record(String message) {
    final safe = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final entry = '[INITIAL_ACCOUNT_SETUP] '
        '${DateTime.now().toIso8601String()} $safe';
    debugPrint(entry);
    _log.add(entry);
    if (mounted) setState(() => _message = safe);
  }

  String? _debugPrintCode() {
    if (!DevAuth.devModeEnabled.value || _log.isEmpty) return null;
    return _log.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  Future<void> _showStatus({
    required bool failure,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final debugCode = _debugPrintCode();
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: title,
        description: message,
        copyText: debugCode,
        copyButtonLabel: 'debugPrint 코드 복사',
        useCommonUi: true,
        isolateCopyText: true,
        visibleDuration: debugCode == null
            ? const Duration(seconds: 4)
            : Duration.zero,
        awaitManualClose: debugCode != null,
      );
      return;
    }
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: message,
      copyText: debugCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      useCommonUi: true,
      isolateCopyText: true,
      visibleDuration: debugCode == null
          ? const Duration(seconds: 3)
          : Duration.zero,
      awaitManualClose: debugCode != null,
    );
  }

  Future<void> _authorizeAndInspect() =>
      FirebaseActivityMonitor.runAction<void>(
        '최초 계정 설정 대상 확인',
        _authorizeAndInspectCore,
      );

  Future<void> _authorizeAndInspectCore() async {
    if (_busy) {
      FirebaseActivityMonitor.noteCurrentActionOutcome(
        FirebaseActionOutcome.skipped,
        code: 'INITIAL_SETUP_BUSY',
      );
      return;
    }
    _log.clear();
    setState(() => _busy = true);
    try {
      _record('개발자 인증을 진행합니다.');
      await CompanyBootstrapService.requireDeveloper(
        source: 'launcher_initial_setup',
      );
      _record('회사를 조회하고 없는 본사 지역은 생성 예정으로 확인합니다.');
      final preview = await _service.preview();
      final inspections = await _service.inspectInitializations(preview);
      final completed = <String>{};
      final syncPending = <String>{};
      for (final entry in inspections.entries) {
        entry.value.requireConsistent();
        if (entry.value.isInitialized) completed.add(entry.key);
        if (entry.value.syncPending) syncPending.add(entry.key);
      }
      final pending = preview.companies.map((company) => company.id).toSet()
        ..removeAll(completed);
      if (!mounted) {
        FirebaseActivityMonitor.noteCurrentActionOutcome(
          FirebaseActionOutcome.cancelled,
          code: 'INITIAL_SETUP_VIEW_DISPOSED',
        );
        return;
      }
      setState(() {
        _preview = preview;
        _authorized = true;
        _retryCompanyIds = completed.isEmpty ? null : pending;
        _lastResult = null;
        _completedCompanyIds.clear();
        _completedCompanyIds.addAll(completed);
        _syncPendingCompanyIds.clear();
        _syncPendingCompanyIds.addAll(syncPending);
      });
      _record('회사 ${preview.companies.length}개 · 지역 '
          '${preview.areaIds.length}개(생성 예정 포함) · 완료 ${completed.length}개 · 남음 ${pending.length}개'
          ' · 동기화 필요 ${syncPending.length}개');
      if (preview.companies.isEmpty) {
        FirebaseActivityMonitor.noteCurrentActionFailure('NO_ACTIVE_COMPANIES');
        await _showStatus(
          failure: true,
          title: '생성 대상 없음',
          message: '활성 회사가 없습니다.',
        );
      }
    } catch (error) {
      _authorized = false;
      _preview = null;
      final code = _errorCode(error);
      FirebaseActivityMonitor.noteCurrentActionFailure(code);
      _record('인증 및 대상 조회 실패: $code');
      await _showStatus(
        failure: true,
        title: '개발자 인증 또는 조회 실패',
        message: '인증 또는 회사·지역 조회를 완료하지 못했습니다. 오류 코드: $code',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _initialize() => FirebaseActivityMonitor.runAction<void>(
        '최초 계정 생성',
        _initializeCore,
      );

  Future<void> _initializeCore() async {
    final preview = _preview;
    final targets = _retryCompanyIds;
    if (_busy || !_authorized || preview == null || preview.pending == 0 ||
        (targets != null && targets.isEmpty)) {
      FirebaseActivityMonitor.noteCurrentActionOutcome(
        FirebaseActionOutcome.skipped,
        code: 'INITIAL_SETUP_NOT_READY',
      );
      return;
    }
    if ((targets == null
            ? preview.companies.any((company) => company.id == 'belivus')
            : targets.contains('belivus')) &&
        _password.text.trim().isEmpty) {
      FirebaseActivityMonitor.noteCurrentActionFailure(
        'INITIAL_ADMIN_PASSWORD_REQUIRED',
      );
      _record('belivus 최초 관리자 비밀번호가 비어 있습니다.');
      await _showStatus(
        failure: true,
        title: '비밀번호 입력 필요',
        message: 'belivus 최초 관리자 비밀번호를 입력하세요.',
      );
      return;
    }
    _log.clear();
    setState(() => _busy = true);
    try {
      _record(targets == null ? '본사 및 최초 관리자 통합 생성 시작' : '남은 회사의 본사 및 초기 관리자 생성 시작');
      final latestPreview = await _service.preview();
      final freshInspections = await _service.inspectInitializations(latestPreview);
      final completedNow = <String>{};
      final pendingNow = <String>{};
      for (final entry in freshInspections.entries) {
        entry.value.requireConsistent();
        if (entry.value.isInitialized) completedNow.add(entry.key);
        if (entry.value.state == AccountInitializationState.uninitialized) {
          pendingNow.add(entry.key);
        }
      }
      final effectiveTargets = targets == null
          ? pendingNow
          : pendingNow.intersection(targets);
      _completedCompanyIds.addAll(completedNow);
      if (effectiveTargets.isEmpty) {
        throw StateError('INITIAL_SETUP_NO_PENDING_COMPANIES');
      }
      final result = await _service.initializeExisting(
        preview: latestPreview,
        targetCompanyIds: effectiveTargets,
        belivusPassword: _password.text,
        onProgress: _record,
      );
      _password.clear();
      final completed = result.completedCompanyIds;
      _completedCompanyIds.addAll(completed);
      final remaining = <String>{
        ...result.failedCompanyIds,
        ...result.pendingCompanyIds,
      };
      if (mounted) {
        setState(() {
          _preview = latestPreview;
          _retryCompanyIds = remaining;
          _lastResult = result;
        });
      }
      final activeTotal = _completedCompanyIds.contains('belivus') ? 1 : 0;
      final pendingTotal = _completedCompanyIds.length - activeTotal;
      _record('누적완료=${_completedCompanyIds.length} '
          '이번완료=${completed.length} 실패=${result.failedCompanyIds.length} '
          '미시도=${result.pendingCompanyIds.length} 활성=$activeTotal '
          '등록대기=$pendingTotal');
      if (result.succeeded) {
        if (result.syncPending) {
          FirebaseActivityMonitor.noteCurrentActionOutcome(
            FirebaseActionOutcome.completedWithWarnings,
            code: result.syncFailureCode ?? 'ACCESS_SYNC_PENDING',
          );
        }
        await _showStatus(
          failure: false,
          title: '본사 및 최초 계정 생성 완료',
          message: '완료 ${_completedCompanyIds.length}개 회사 · '
              '활성 $activeTotal개 · 등록 대기 $pendingTotal개'
              '${result.syncPending ? ' · 접근 목록 재동기화 필요' : ''}',
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        final code = result.failureCode ?? 'INITIAL_SETUP_FAILED';
        FirebaseActivityMonitor.noteCurrentActionOutcome(
          result.newlyCreatedCompanyIds.isNotEmpty
              ? FirebaseActionOutcome.partial
              : FirebaseActionOutcome.failed,
          code: code,
        );
        if (result.syncPending) {
          FirebaseActivityMonitor.noteCurrentActionOutcome(
            FirebaseActionOutcome.completedWithWarnings,
            code: result.syncFailureCode ?? 'ACCESS_SYNC_PENDING',
          );
        }
        await _showStatus(
          failure: true,
          title: _completedCompanyIds.isEmpty ? '최초 계정 생성 실패' : '일부 회사 생성 완료',
          message: '누적 완료 ${_completedCompanyIds.join(', ')}\n'
              '실패 ${result.failedCompanyIds.join(', ')}\n'
              '미시도 ${result.pendingCompanyIds.join(', ')}\n'
              '오류 코드: $code\n'
              '완료된 회사의 데이터는 그대로 두고 남은 회사만 다시 실행할 수 있습니다.',
        );
      }
    } catch (error) {
      final code = _errorCode(error);
      FirebaseActivityMonitor.noteCurrentActionFailure(code);
      _record('최초 계정 생성 실패: $code');
      if (mounted && _retryCompanyIds == null) {
        setState(() {
          _authorized = false;
          _preview = null;
        });
      }
      _password.clear();
      await _showStatus(
        failure: true,
        title: '최초 계정 생성 실패',
        message: '생성 작업을 완료하지 못했습니다. 오류 코드: $code',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final preview = _preview;
    final hasBelivus = preview?.companies.any(
          (company) => company.id == 'belivus',
        ) ?? false;
    final retryIds = _retryCompanyIds;
    final canInitialize = _authorized && preview != null &&
        preview.pending > 0 && (retryIds == null || retryIds.isNotEmpty);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 590),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '최초 계정 설정',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _message,
                    key: ValueKey<String>(_message),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: _busy
                    ? const LinearProgressIndicator()
                    : const SizedBox(width: double.infinity),
              ),
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: preview == null
                    ? const SizedBox.shrink(key: ValueKey('preview-empty'))
                    : Padding(
                        key: const ValueKey('preview-ready'),
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '회사 ${preview.companies.length}개 · '
                              '지역 ${preview.areaIds.length}개(예정 포함)',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: duration,
                              child: _syncPendingCompanyIds.isEmpty
                                  ? const SizedBox.shrink(
                                      key: ValueKey('sync-complete'))
                                  : Text(
                                      '접근 목록 동기화 필요: '
                                      '${_syncPendingCompanyIds.length}개 회사',
                                      key: ValueKey<int>(
                                          _syncPendingCompanyIds.length),
                                      style: theme.textTheme.bodySmall,
                                    ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 210),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: preview.companies.length,
                                itemBuilder: (context, index) {
                                  final company = preview.companies[index];
                                  return TweenAnimationBuilder<double>(
                                    key: ValueKey<String>(company.id),
                                    tween: Tween<double>(begin: 0, end: 1),
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : Duration(milliseconds: 220 + index * 55),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, child) =>
                                        Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, (1 - value) * 8),
                                        child: child,
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(company.id),
                                      leading: AnimatedSwitcher(
                                        duration: duration,
                                        child: Icon(
                                          _completedCompanyIds.contains(company.id)
                                              ? Icons.check_circle_outline_rounded
                                              : (_lastResult?.failedCompanyIds.contains(company.id) ?? false)
                                                  ? Icons.error_outline_rounded
                                                  : Icons.business_outlined,
                                          key: ValueKey<String>(
                                            '${company.id}:${_completedCompanyIds.contains(company.id)}:'
                                            '${_lastResult?.failedCompanyIds.contains(company.id) ?? false}',
                                          ),
                                          size: 19,
                                        ),
                                      ),
                                      trailing: AnimatedSwitcher(
                                        duration: duration,
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: Text(
                                          _completedCompanyIds.contains(company.id)
                                              ? '생성 완료'
                                              : company.headquarter.createOnBootstrap
                                                  ? '본사 생성 예정 · 5/10'
                                                  : '지역 ${company.areaIds.length}개',
                                          key: ValueKey<String>(
                                            '${company.id}:${_completedCompanyIds.contains(company.id)}:${company.headquarter.createOnBootstrap}',
                                          ),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: !(hasBelivus &&
                        (retryIds == null || retryIds.contains('belivus')))
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: _password,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'belivus 초기 관리자 비밀번호',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : canInitialize
                          ? _initialize
                          : _authorizeAndInspect,
                  icon: AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      canInitialize
                          ? Icons.person_add_alt_1_rounded
                          : Icons.verified_user_outlined,
                      key: ValueKey<bool>(canInitialize),
                    ),
                  ),
                  label: AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      canInitialize
                          ? (retryIds == null ? '최초 계정 생성' : '남은 계정 생성')
                          : '개발자 인증 및 대상 확인',
                      key: ValueKey<bool>(canInitialize),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
