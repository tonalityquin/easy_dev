import '../../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../../features/account/presentation/widgets/permission_detail_list.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../features/account/domain/models/account_permission_policy.dart';
import '../../../../../features/account/data/services/company_grade_policy_service.dart';
import '../../../../../features/selector/application/dev_auth.dart';

class DocumentAccessPolicyDialog extends StatefulWidget {
  const DocumentAccessPolicyDialog({
    super.key,
    required this.companyId,
    this.initialDocumentPath = '',
  });

  final String companyId;
  final String initialDocumentPath;

  static Future<void> open(
    BuildContext context, {
    required String companyId,
    String initialDocumentPath = '',
  }) async {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '문서별 접근 권한',
      barrierColor: Colors.black54,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          DocumentAccessPolicyDialog(
        companyId: companyId,
        initialDocumentPath: initialDocumentPath,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
  State<DocumentAccessPolicyDialog> createState() =>
      _DocumentAccessPolicyDialogState();
}

class _DocumentAccessPolicyDialogState
    extends State<DocumentAccessPolicyDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TextEditingController _path;
  final TextEditingController _accountId = TextEditingController();
  Map<String, dynamic>? _loaded;
  String _selectedGrade = 'custom_1';
  Map<String, CompanyGradePolicy> _gradePolicies = <String, CompanyGradePolicy>{};
  bool _gradeLoading = false;
  String _target = 'grade';
  final String _action = 'deny';
  bool _loading = false;
  bool _saving = false;
  final Map<String, Map<String, dynamic>> _policies =
      <String, Map<String, dynamic>>{};
  Set<String> _dirtyPermissions = <String>{};

  static const Map<String, String> _roots = <String, String>{
    'user_accounts': 'accounts',
    'user_accounts_show': 'accounts',
    'user_account_codes': 'accounts',
    'voice_channels': 'voice_channels',
  };

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.initialDocumentPath);
    _loadGrades();
    if (widget.initialDocumentPath.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _loadGrades() async {
    setState(() => _gradeLoading = true);
    try {
      final policies = await CompanyGradePolicyService(firestore: _firestore)
          .loadAll(widget.companyId);
      if (!mounted) return;
      setState(() {
        _gradePolicies = policies;
        _gradeLoading = false;
        if (!_gradePolicies.containsKey(_selectedGrade) && policies.isNotEmpty) {
          _selectedGrade = policies.keys.first;
        }
      });
      _loadSelection();
    } catch (error, stackTrace) {
      debugPrint('[DOCUMENT-ACL] grade load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _gradeLoading = false);
      await _status(error, stackTrace, failure: true);
    }
  }

  @override
  void dispose() {
    _path.dispose();
    _accountId.dispose();
    super.dispose();
  }

  String get _policyKey =>
      'acl${_action == 'deny' ? 'Deny' : 'Grant'}By${_target == 'grade' ? 'Grade' : 'Account'}';

  String get _subject => _target == 'grade'
      ? _selectedGrade
      : _accountId.text.trim();

  String get _normalizedPath => _path.text.trim();

  String get _collectionPrefix {
    final parts = _normalizedPath.split('/');
    if (parts.isEmpty) return '';
    if (parts.first == 'voice_channels' && parts.length >= 4 &&
        parts[2] == 'messages') {
      return 'voice.messages';
    }
    return _roots[parts.first] ?? parts.first;
  }

  bool get _validPath {
    final parts = _normalizedPath.split('/');
    return parts.length >= 2 && parts.length.isEven &&
        parts.every((segment) => segment.isNotEmpty) &&
        !parts.any((segment) => segment == '.' || segment == '..') &&
        AccountPermissionPolicy.keys.any(
          (key) => key.startsWith('$_collectionPrefix.'),
        );
  }

  List<String> get _availablePermissions =>
      AccountPermissionPolicy.keys
          .where((key) => key.startsWith('$_collectionPrefix.'))
          .toList(growable: false)
        ..sort();

  Map<String, dynamic> _parsePolicy(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): entry.value is List
            ? List<String>.from(
                (entry.value as List).map((item) => item.toString()))
            : <String>[],
    };
  }

  void _loadSelection() {
    final policy = _policies[_policyKey] ?? <String, dynamic>{};
    final chosen = policy[_subject];
    setState(() {
      _dirtyPermissions = chosen is List
          ? List<String>.from(chosen).toSet()
          : <String>{};
    });
  }

  Future<void> _status(Object error, StackTrace? stack, {
    required bool failure,
  }) async {
    debugPrint('[DOCUMENT-ACL] company=${widget.companyId}');
    debugPrint('[DOCUMENT-ACL] path=$_normalizedPath action=$_action target=$_target');
    debugPrint('[DOCUMENT-ACL] result=$error');
    if (stack != null) debugPrint('[DOCUMENT-ACL] stack=$stack');
    if (!mounted) return;
    final copyText = DevAuth.devModeEnabled.value
        ? <String>[
            'company=${widget.companyId}',
            'path=$_normalizedPath',
            'action=$_action',
            'target=$_target',
            'subject=$_subject',
            'result=$error',
            if (stack != null) 'stack=$stack',
          ].map((line) => 'debugPrint(${jsonEncode(line)});').join('\n')
        : null;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '문서 접근 권한 처리 실패',
        description: '문서 접근 권한을 확인하거나 저장하지 못했습니다.',
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
        title: '문서 접근 권한 저장 완료',
        description: '문서별 접근 권한을 저장했습니다.',
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

  Future<void> _load() async {
    if (_loading || !_validPath) return;
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.doc(_normalizedPath)
          .get(const GetOptions(source: Source.server)), source: 'document_access_policy_dialog.get');
      if (!snapshot.exists) throw StateError('DOCUMENT_ACCESS_TARGET_NOT_FOUND');
      final data = snapshot.data() ?? <String, dynamic>{};
      final company = (data['companyId'] ?? data['division'] ??
          data['company'] ?? '').toString().trim();
      if (company != widget.companyId) {
        throw StateError('DOCUMENT_ACCESS_COMPANY_MISMATCH');
      }
      for (final key in <String>[
        'aclDenyByGrade', 'aclDenyByAccount',
        'aclGrantByGrade', 'aclGrantByAccount',
      ]) {
        _policies[key] = _parsePolicy(data[key]);
      }
      _loaded = Map<String, dynamic>.from(data);
      if (mounted) _loadSelection();
    } catch (error, stack) {
      await _status(error, stack, failure: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _loaded == null ||
        !_validPath || _subject.isEmpty) return;
    setState(() => _saving = true);
    final path = _normalizedPath;
    final key = _policyKey;
    final subject = _subject;
    final values = _dirtyPermissions.toList(growable: false)..sort();
    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final reference = _firestore.doc(path);
        final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(reference), source: 'document_access_policy_dialog.get');
        final current = snapshot.data();
        if (current == null) throw StateError('DOCUMENT_ACCESS_TARGET_NOT_FOUND');
        final company = (current['companyId'] ?? current['division'] ??
            current['company'] ?? '').toString().trim();
        if (company != widget.companyId) {
          throw StateError('DOCUMENT_ACCESS_COMPANY_MISMATCH');
        }
        final policy = _parsePolicy(current[key]);
        if (values.isEmpty) {
          policy.remove(subject);
        } else {
          policy[subject] = values;
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(reference, <String, dynamic>{key: policy}));
      }), source: 'document_access_policy_dialog.runTransaction');
      if (!mounted) return;
      await _load();
      if (mounted) await _status('saved', null, failure: false);
    } catch (error, stack) {
      if (mounted) await _status(error, stack, failure: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final keys = _availablePermissions;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.admin_panel_settings_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('문서별 접근 권한 · ${widget.companyId}',
                    style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _path,
                decoration: const InputDecoration(labelText: '문서 경로'),
                onChanged: (_) => setState(() {
                  _loaded = null;
                  _dirtyPermissions = <String>{};
                }),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _validPath && !_loading && !_saving ? _load : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('문서 권한 조회'),
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSize(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 230),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in <String>['grade', 'account'])
                      ChoiceChip(
                        label: Text(type == 'grade' ? '계정 등급' : '개별 계정'),
                        selected: _target == type,
                        onSelected: (_) {
                          _target = type;
                          _loadSelection();
                        },
                      ),
                    const Chip(label: Text('접근 차단')),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Text('등급에서 허용한 권한도 문서에서 차단할 수 있습니다. 명시적 차단과 등급 거부는 예외 허용보다 우선합니다.'),
              ),
              if (_target == 'grade')
                DropdownButtonFormField<String>(
                  value: _gradePolicies.containsKey(_selectedGrade)
                      ? _selectedGrade : null,
                  decoration: const InputDecoration(labelText: '계정 등급'),
                  items: _gradePolicies.entries
                      .map((entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value.name),
                          ))
                      .toList(growable: false),
                  onChanged: _gradeLoading ? null : (grade) {
                    if (grade == null) return;
                    _selectedGrade = grade;
                    _loadSelection();
                  },
                ),
              if (_target == 'account')
                TextField(
                  controller: _accountId,
                  decoration: const InputDecoration(labelText: '프로젝트 계정 ID'),
                  onChanged: (_) => _loadSelection(),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
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
                          key: ValueKey<String>('$_collectionPrefix-$_target-$_action-$_subject'),
                          permissions: keys,
                          selected: _dirtyPermissions,
                          enabled: _loaded != null && !_saving,
                          onToggle: (permission) => setState(() {
                            if (_dirtyPermissions.contains(permission)) {
                              _dirtyPermissions.remove(permission);
                            } else {
                              _dirtyPermissions.add(permission);
                            }
                          }),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('닫기'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loaded != null && !_saving && !_loading &&
                      _subject.isNotEmpty ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('문서 권한 저장'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
