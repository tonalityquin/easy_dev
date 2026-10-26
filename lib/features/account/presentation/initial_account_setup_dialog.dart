import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/access_gate_diagnostics.dart';
import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';
import '../data/services/company_bootstrap_service.dart';

class InitialAccountSetupDialog extends StatefulWidget {
  const InitialAccountSetupDialog({super.key});

  static Future<void> open(BuildContext context) async {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '최초 계정 설정',
      barrierColor: Colors.black54,
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => const InitialAccountSetupDialog(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<InitialAccountSetupDialog> createState() => _InitialAccountSetupDialogState();
}

class _InitialAccountSetupDialogState extends State<InitialAccountSetupDialog> {
  final CompanyBootstrapService _service = const CompanyBootstrapService();
  final TextEditingController _password = TextEditingController();
  BootstrapPreview? _preview;
  BootstrapSyncProgress? _syncProgress;
  bool _busy = false;
  bool _authorized = false;
  String _message = '실제 Firestore 초기화 시 개발자 Google 인증과 서버 승인이 필요합니다. 디버그 개발자 모드는 그대로 유지됩니다.';
  final List<String> _log = <String>[];

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _record(String value) {
    debugPrint('[INITIAL_ACCOUNT_SETUP] $value');
    _log.add(value);
    if (mounted) setState(() => _message = value);
  }

  Future<void> _showStatus({required bool failure, required String message}) async {
    if (!mounted) return;
    final code = DevAuth.devModeEnabled.value
        ? <String>[...AccessGateDiagnostics.lines, ..._log]
            .map((line) => 'debugPrint(${_quote(line)});')
            .join('\n')
        : null;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '최초 계정 설정 실패',
        description: message,
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        useCommonUi: true,
        visibleDuration: code == null ? const Duration(seconds: 4) : Duration.zero,
        awaitManualClose: code != null,
      );
    } else {
      await StatusDialog.showSuccess(
        context,
        title: '최초 계정 설정 완료',
        description: message,
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        useCommonUi: true,
        visibleDuration: code == null ? const Duration(seconds: 3) : Duration.zero,
        awaitManualClose: code != null,
      );
    }
  }

  String _quote(String s) {
    return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
  }

  Future<void> _loadSyncProgress(int version) async {
    final progress = await _service.syncProgress(version);
    if (mounted) setState(() => _syncProgress = progress);
  }

  Future<void> _authorizeAndInspect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _record('개발자 Google 인증을 시작합니다.');
      await CompanyBootstrapService.requireDeveloper(source: 'launcher_initial_setup');
      _authorized = true;
      _record('서버에서 전체 회사와 지역 목록을 확인합니다.');
      final preview = await _service.preview();
      if (!mounted) return;
      setState(() => _preview = preview);
      await _loadSyncProgress(preview.catalogVersion);
      _record('회사 ${preview.companies.length}개 · 초기화 ${preview.pending}개 · 복구 필요 ${preview.recoveryRequired}개 · 확인 필요 ${preview.reviewRequired}개');
    } catch (error) {
      _authorized = false;
      _record('인증 또는 대상 조회 실패: ${error.runtimeType}');
      await _showStatus(failure: true, message: '개발자 인증 또는 서버 데이터 확인에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resynchronize() async {
    if (_busy || !_authorized || _preview == null) return;
    setState(() => _busy = true);
    try {
      await CompanyBootstrapService.requireDeveloper(source: 'launcher_initial_setup_sync', forceAccountSelection: false);
      _record('전체 초기 관리자 접근 목록 재동기화를 시작합니다.');
      await _service.synchronizeInitialAdmins(onProgress: _record);
      await _loadSyncProgress(_preview!.catalogVersion);
      _record('전체 초기 관리자 접근 목록 재동기화 완료');
      await _showStatus(failure: false, message: '초기 관리자 접근 목록을 다시 확인했습니다.');
    } catch (error) {
      _record('접근 목록 동기화 실패: ${error.runtimeType}');
      if (_preview != null) {
        try {
          await _loadSyncProgress(_preview!.catalogVersion);
        } catch (_) {}
      }
      await _showStatus(failure: true, message: '접근 목록을 완전히 동기화하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    if (_busy || !_authorized || _preview == null) return;
    final preview = _preview!;
    if (preview.recoveryRequired == 0) return;
    final belivusMissing = preview.companies.any((company) =>
        company.id == 'belivus' && company.needsRecovery &&
        !company.initialAdminExists);
    if (belivusMissing && _password.text.trim().isEmpty) {
      await _showStatus(
        failure: true,
        message: 'belivus 초기 관리자 원본 계정 복구에 사용할 비밀번호를 입력해 주세요.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      _record('복구 대상 초기 관리자 문서의 정합성을 재확인합니다.');
      final completed = await _service.recoverInitialAdmins(
        preview: preview,
        belivusPassword: _password.text,
        onProgress: _record,
      );
      _password.clear();
      final refreshed = await _service.preview();
      if (!mounted) return;
      setState(() => _preview = refreshed);
      await _loadSyncProgress(refreshed.catalogVersion);
      _record('회사 ${completed.length}개의 표시·집계 참조 문서를 복구했습니다.');
      await _showStatus(
        failure: false,
        message: '복구 ${completed.length}개 완료 · 추가 확인 ${refreshed.reviewRequired}개',
      );
    } catch (error) {
      _record('관리자 복구 실패: ${error.runtimeType}');
      await _showStatus(
        failure: true,
        message: '복구가 중단됐습니다. 대상 문서 또는 인증 상태를 확인해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuildCounts() async {
    if (_busy || !_authorized || _preview == null) return;
    final targets = _preview!.companies
        .where((company) => !company.metaConsistent && !company.needsReview)
        .toList(growable: false);
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    try {
      _record('계정 집계 정합성 재구축을 시작합니다.');
      for (final company in targets) {
        await _service.rebuildAccountCounts(
          companyId: company.id,
          onProgress: _record,
        );
      }
      final refreshed = await _service.preview();
      if (!mounted) return;
      setState(() => _preview = refreshed);
      await _loadSyncProgress(refreshed.catalogVersion);
      _record('계정 집계 ${targets.length}개 회사 재구축 완료');
      await _showStatus(
        failure: false,
        message: '계정 집계 정합성 검사와 재구축이 완료됐습니다.',
      );
    } catch (error) {
      _record('계정 집계 재구축 실패: ${error.runtimeType}');
      await _showStatus(
        failure: true,
        message: '집계 재구축을 중단했습니다. 회사 상태와 오류 원인을 확인해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _initialize() async {
    if (_busy || !_authorized || _preview == null) return;
    final preview = _preview!;
    if (preview.pending == 0) return;
    if (preview.companies.any((c) => c.id == 'belivus' && c.needsInitialization) &&
        _password.text.trim().isEmpty) {
      await _showStatus(failure: true, message: 'belivus 초기 관리자 비밀번호를 입력해야 합니다.');
      return;
    }
    setState(() => _busy = true);
    try {
      await CompanyBootstrapService.requireDeveloper(source: 'launcher_initial_setup_commit', forceAccountSelection: false);
      final completed = await _service.initializeExisting(
        preview: preview,
        belivusPassword: _password.text,
        onProgress: _record,
      );
      _password.clear();
      _record('초기 계정 ${completed.length}개를 생성했습니다.');
      if (!mounted) return;
      await _showStatus(failure: false, message: '회사 ${completed.length}개의 초기 계정 설정이 완료되었습니다.');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _record('초기화 중 오류: ${error.runtimeType}');
      await _showStatus(failure: true, message: '초기화 중 일부 작업이 완료되지 않았습니다. 다시 상태를 확인해 주세요.');
      if (mounted) setState(() {
        _preview = null;
        _syncProgress = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final syncProgress = _syncProgress;
    final needPassword = preview?.companies.any((company) =>
        company.id == 'belivus' && (company.needsInitialization ||
        (company.needsRecovery && !company.initialAdminExists))) == true;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 590),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.admin_panel_settings_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('최초 계정 설정', style: theme.textTheme.titleLarge)),
                IconButton(
                  tooltip: '닫기',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 230),
                child: Text(_message, key: ValueKey<String>(_message)),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (preview != null) ...[
                const SizedBox(height: 12),
                Text('회사 ${preview.companies.length}개 · 지역 ${preview.areaIds.length}개 · 생성 ${preview.pending}개 · 복구 ${preview.recoveryRequired}개 · 확인 ${preview.reviewRequired}개'),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  child: syncProgress == null
                      ? const SizedBox.shrink(key: ValueKey<String>('sync-none'))
                      : Padding(
                          key: ValueKey<String>('sync-${syncProgress.status}-${syncProgress.completedCount}'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('접근 동기화 ${syncProgress.status} · ${syncProgress.completedCount}/${syncProgress.totalCount} 완료'),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: syncProgress.totalCount == 0 ? 1 :
                                    (syncProgress.completedCount / syncProgress.totalCount)
                                        .clamp(0.0, 1.0).toDouble(),
                              ),
                              if (syncProgress.pendingCompanyIds.isNotEmpty)
                                Text('미완료 회사 ${syncProgress.pendingCompanyIds.length}개'),
                            ],
                          ),
                        ),
                ),
                Flexible(child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: preview.companies.length,
                  itemBuilder: (context, index) {
                    final company = preview.companies[index];
                    return ListTile(
                      dense: true,
                      title: Text(company.id),
                      trailing: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          company.needsRecovery
                              ? Icons.build_circle_outlined
                              : company.needsReview
                                  ? Icons.report_problem_outlined
                                  : company.needsInitialization
                                      ? Icons.add_circle_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                          key: ValueKey<String>(
                            '${company.id}:${company.needsRecovery}:${company.needsReview}:${company.needsInitialization}',
                          ),
                        ),
                      ),
                      subtitle: Text(company.needsRecovery
                          ? '완료 기록과 관리자 참조 문서 불일치 · 복구 필요'
                          : company.needsReview
                              ? '계정은 있지만 완료 기록 없음 · 확인 필요'
                              : company.initialized
                                  ? '이미 초기화됨'
                                  : '초기화 대상'),
                    );
                  },
                )),
                if (needPassword) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'belivus 초기 관리자 비밀번호',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              if (preview != null) ...[
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (preview.companies.any((company) =>
                        !company.metaConsistent && !company.needsReview))
                      TextButton.icon(
                        onPressed: _busy ? null : _rebuildCounts,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            _busy ? '집계 검사 중' : '계정 집계 재구축',
                            key: ValueKey<bool>(_busy),
                          ),
                        ),
                      ),
                    if (preview.recoveryRequired > 0)
                      TextButton.icon(
                        onPressed: _busy ? null : _recover,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('초기 관리자 복구'),
                      ),
                    TextButton.icon(
                      onPressed: _busy ? null : _resynchronize,
                      icon: const Icon(Icons.sync_rounded),
                      label: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          syncProgress?.needsRetry == true
                              ? '미완료 동기화 재시도' : '접근 목록 재동기화',
                          key: ValueKey<bool>(syncProgress?.needsRetry == true),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _busy ? null : _authorizeAndInspect,
                  child: Text(preview == null ? '개발자 인증 및 대상 확인' : '다시 확인'),
                )),
                if (preview != null && preview.pending > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(
                    onPressed: _busy ? null : _initialize,
                    child: const Text('초기 계정 생성'),
                  )),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
