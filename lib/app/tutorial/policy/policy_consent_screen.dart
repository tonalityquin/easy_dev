import 'package:flutter/material.dart';
import '../../di/routes.dart';
import '../../init/app_start_flow_prefs.dart';
import 'policy_documents.dart';

export 'policy_documents.dart';

class PolicyConsentScreen extends StatefulWidget {
  const PolicyConsentScreen({
    super.key,
    required this.kind,
  });

  final PolicyConsentKind kind;

  @override
  State<PolicyConsentScreen> createState() => _PolicyConsentScreenState();
}

class _PolicyConsentScreenState extends State<PolicyConsentScreen> {
  final ScrollController _documentScrollController = ScrollController();
  bool _readToEnd = false;
  bool _agreed = false;
  bool _busy = false;

  PolicyDocumentSpec get _spec => policyDocumentOf(widget.kind);

  @override
  void initState() {
    super.initState();
    _documentScrollController.addListener(_handleDocumentScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  void _handleDocumentScroll() {
    if (_readToEnd || !_documentScrollController.hasClients) return;
    final position = _documentScrollController.position;
    if (position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24) {
      setState(() => _readToEnd = true);
    }
  }

  void _markReadIfNeeded() {
    if (!mounted || _readToEnd || !_documentScrollController.hasClients) return;
    final position = _documentScrollController.position;
    if (position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24) {
      setState(() => _readToEnd = true);
    }
  }

  Future<void> _saveAgreement() async {
    switch (widget.kind) {
      case PolicyConsentKind.termsOfService:
        await AppStartFlowPrefs.setTermsOfServiceAgreed(true);
        return;
      case PolicyConsentKind.privacyPolicy:
        await AppStartFlowPrefs.setPrivacyPolicyAgreed(true);
        return;
      case PolicyConsentKind.accountDeletion:
        await AppStartFlowPrefs.setAccountDeletionPolicyAgreed(true);
        return;
    }
  }

  String _nextRoute() {
    switch (widget.kind) {
      case PolicyConsentKind.termsOfService:
        return AppRoutes.privacyPolicyConsent;
      case PolicyConsentKind.privacyPolicy:
        return AppRoutes.accountDeletionPolicyConsent;
      case PolicyConsentKind.accountDeletion:
        return AppRoutes.startGate;
    }
  }

  Future<void> _complete() async {
    if (_busy || !_agreed) return;
    setState(() => _busy = true);
    try {
      await _saveAgreement();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        _nextRoute(),
        (route) => false,
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _spec.step / _spec.totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_spec.step}/${_spec.totalSteps}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            _spec.icon,
            color: colorScheme.onPrimaryContainer,
            size: 36,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _spec.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _spec.subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDocument(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Scrollbar(
          controller: _documentScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _documentScrollController,
            padding: const EdgeInsets.fromLTRB(18, 18, 28, 18),
            child: Text(
              _spec.body.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.55,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgreement(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = _readToEnd && !_busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_readToEnd)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '문서를 끝까지 스크롤하면 동의 체크가 가능합니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest,
          child: CheckboxListTile(
            value: _agreed,
            onChanged: enabled
                ? (value) => setState(() => _agreed = value ?? false)
                : null,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              _spec.agreeLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _agreed && !_busy ? _complete : null,
            child: Text(_busy ? '저장 중' : _spec.actionLabel),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _documentScrollController.removeListener(_handleDocumentScroll);
    _documentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_spec.title),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 20),
                    Expanded(child: _buildDocument(context)),
                    const SizedBox(height: 12),
                    _buildAgreement(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
