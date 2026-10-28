import '../../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../../features/account/presentation/widgets/permission_detail_list.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../features/account/domain/models/account_permission_policy.dart';
import '../../../../../features/account/data/services/company_bootstrap_service.dart';
import '../../../../../features/account/data/services/company_grade_policy_service.dart';
import '../../../../../features/selector/application/dev_auth.dart';

class AccountGradePolicyDialog extends StatefulWidget {
  const AccountGradePolicyDialog({
    super.key,
    required this.companyId,
  });

  final String companyId;

  static Future<void> open(BuildContext context, String companyId) async {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '계정 등급별 권한 설정',
      barrierColor: Colors.black54,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          AccountGradePolicyDialog(companyId: companyId),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AccountGradePolicyDialog> createState() =>
      _AccountGradePolicyDialogState();
}

class _AccountGradePolicyDialogState extends State<AccountGradePolicyDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Set<String>> _permissions = <String, Set<String>>{};
  final Map<String, int> _versions = <String, int>{};
  final Map<String, bool> _enabled = <String, bool>{};
  final Map<String, String> _names = <String, String>{};
  final Set<String> _changed = <String>{};
  String _selectedGrade = 'custom_1';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  DocumentReference<Map<String, dynamic>> _reference(String grade) =>
      _firestore.collection('company_grade_policies')
          .doc(widget.companyId).collection('grades').doc(grade);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await const CompanyBootstrapService()
          .ensureGeneralGradePolicies(widget.companyId);
      final policies = await CompanyGradePolicyService(firestore: _firestore)
          .loadAll(widget.companyId);
      if (!mounted) return;
      _permissions.clear();
      _versions.clear();
      _enabled.clear();
      _names.clear();
      for (final policy in policies.values) {
        _permissions[policy.gradeId] = Set<String>.of(policy.permissionKeys);
        _versions[policy.gradeId] = policy.version;
        _enabled[policy.gradeId] = policy.enabled;
        _names[policy.gradeId] = policy.name;
      }
      if (!_permissions.containsKey(_selectedGrade) && _permissions.isNotEmpty) {
        _selectedGrade = _permissions.keys.first;
      }
      _changed.clear();
    } catch (error, stackTrace) {
      debugPrint('[GRADE-POLICY] load failed: $error\n$stackTrace');
      if (mounted) {
        _error = error.toString();
        await _showStatus(error, stackTrace, failure: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showStatus(Object error, StackTrace? stackTrace, {
    required bool failure,
  }) async {
    if (!mounted) return;
    final lines = <String>[
      'company=${widget.companyId}',
      'grade=$_selectedGrade',
      'operation=${failure ? 'failed' : 'success'}',
      'detail=$error',
      if (stackTrace != null) 'stack=$stackTrace',
    ];
    for (final line in lines) {
      debugPrint('[GRADE-POLICY] $line');
    }
    final copyText = DevAuth.devModeEnabled.value
        ? lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n')
        : null;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '등급별 권한 설정 실패',
        description: '등급별 권한 설정 내용을 저장하지 못했습니다.',
        copyText: copyText,
        copyButtonLabel: 'debugPrint 코드 복사',
        useCommonUi: true,
        visibleDuration: copyText == null
            ? const Duration(seconds: 4)
            : Duration.zero,
        awaitManualClose: copyText != null,
      );
    } else {
      await StatusDialog.showSuccess(
        context,
        title: '등급별 권한 설정 완료',
        description: '${_names[_selectedGrade] ?? AccountPermissionPolicy.gradeLabel(_selectedGrade)} 권한을 저장했습니다.',
        copyText: copyText,
        copyButtonLabel: 'debugPrint 코드 복사',
        useCommonUi: true,
        visibleDuration: copyText == null
            ? const Duration(seconds: 3)
            : Duration.zero,
        awaitManualClose: copyText != null,
      );
    }
  }

  Future<void> _save() async {
    if (_loading || _saving || !_changed.contains(_selectedGrade)) return;
    setState(() => _saving = true);
    final grade = _selectedGrade;
    final selected = Set<String>.of(_permissions[grade] ?? const <String>{});
    final expectedVersion = _versions[grade] ?? 0;
    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final reference = _reference(grade);
        final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(reference), source: 'account_grade_policy_dialog.get');
        final data = snapshot.data();
        if (data == null || data['version'] != expectedVersion ||
            data['companyId'] != widget.companyId ||
            data['gradeId'] != grade) {
          throw StateError('ACCOUNT_GRADE_POLICY_CHANGED');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => transaction.update(reference, <String, dynamic>{
          'permissionKeys': selected.toList(growable: false)..sort(),
          'version': expectedVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }), source: 'account_grade_policy_dialog.runTransaction');
      if (!mounted) return;
      _versions[grade] = expectedVersion + 1;
      _changed.remove(grade);
      await _showStatus('saved ${selected.length} permissions', null, failure: false);
    } catch (error, stackTrace) {
      if (mounted) await _showStatus(error, stackTrace, failure: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewPolicyDifference() async {
    if (_loading || _saving) return;
    final grade = _selectedGrade;
    if (!AccountPermissionPolicy.presets.containsKey(grade)) return;
    final stored = _permissions[grade] ?? const <String>{};
    final recommended = AccountPermissionPolicy.presetPermissions(grade);
    final onlyStored = stored.difference(recommended).toList()..sort();
    final onlyRecommended = recommended.difference(stored).toList()..sort();
    final sensitive = <String>{
      'plates.fee.update',
      'locationSlotReservations.delete',
    };
    final removable = onlyStored.where(sensitive.contains).toList(growable: false);
    if (!mounted) return;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final apply = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '등급별 기본 권한 비교',
      barrierColor: Colors.black54,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => AlertDialog(
        title: Text('${_names[grade] ?? AccountPermissionPolicy.gradeLabel(grade)} 기본 권한 비교'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 390),
          child: AnimatedSize(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('회사에 저장된 권한 ${stored.length}개 · 현재 기본 권한 ${recommended.length}개'),
                  const SizedBox(height: 10),
                  Text('저장 정책에만 있는 권한 ${onlyStored.length}개'),
                  ...onlyStored.map((key) => Text(key)),
                  const SizedBox(height: 10),
                  Text('기본 정책에만 있는 권한 ${onlyRecommended.length}개'),
                  ...onlyRecommended.map((key) => Text(key)),
                  if (removable.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('민감 권한 제거 후보'),
                    ...removable.map((key) => Text(key)),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          if (removable.isNotEmpty &&
              (grade == 'custom_4' || grade == 'custom_5' || grade == 'custom_6'))
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('민감 권한 선택 해제'),
            ),
        ],
      ),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (!mounted || apply != true) return;
    setState(() {
      _permissions[grade]?.removeAll(removable);
      _changed.add(grade);
    });
    debugPrint('[GRADE-POLICY] review company=${widget.companyId} grade=$grade removals=$removable');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = _permissions[_selectedGrade] ?? const <String>{};
    final csvDefault = AccountPermissionPolicy.presets[_selectedGrade];
    final csvGranted = csvDefault == null
        ? 0 : selected.difference(csvDefault).length;
    final csvRemoved = csvDefault == null
        ? 0 : csvDefault.difference(selected).length;
    final keys = AccountPermissionPolicy.generalPermissionKeys.toList()
      ..sort((a, b) {
        final aSelected = selected.contains(a);
        final bSelected = selected.contains(b);
        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return a.compareTo(b);
      });
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('등급별 권한 관리 · ${widget.companyId}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 230),
                curve: Curves.easeInOutCubic,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _names.keys.map((grade) =>
                      ChoiceChip(
                        label: Text(_names[grade] ?? AccountPermissionPolicy.gradeLabel(grade)),
                        selected: _selectedGrade == grade,
                        onSelected: _saving ? null : (_) => setState(() {
                          _selectedGrade = grade;
                        }),
                      )).toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text('권한 정보를 확인하지 못했습니다. $_error'))
                        : AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 210),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(.025, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: PermissionDetailList(
                              key: ValueKey<String>(_selectedGrade),
                              permissions: keys,
                              selected: selected,
                              enabled: !_saving && _enabled[_selectedGrade] == true,
                              onToggle: (permission) => setState(() {
                                final next = _permissions[_selectedGrade]!;
                                if (next.contains(permission)) {
                                  next.remove(permission);
                                } else {
                                  next.add(permission);
                                }
                                _changed.add(_selectedGrade);
                              }),
                            ),
                          ),
              ),
              const SizedBox(height: 12),
              if (csvDefault != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Text(
                      'CSV 초기값 대비 추가 허용 $csvGranted개 · 허용 해제 $csvRemoved개',
                      key: ValueKey<String>('$_selectedGrade-$csvGranted-$csvRemoved'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              Row(
                children: [
                  Text('허용 ${selected.length}개 / 거부 ${keys.length - selected.length}개 / 전체 ${keys.length}개 권한',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving || csvDefault == null ? null : _reviewPolicyDifference,
                    child: const Text('기본 권한과 비교'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: !_loading && !_saving &&
                            _changed.contains(_selectedGrade)
                        ? _save : null,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('권한 저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
