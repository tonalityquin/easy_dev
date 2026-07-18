import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/config/email_config.dart';
import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class AppStartPermissionSetupScreen extends StatefulWidget {
  const AppStartPermissionSetupScreen({super.key});

  @override
  State<AppStartPermissionSetupScreen> createState() =>
      _AppStartPermissionSetupScreenState();
}

enum _PermissionStepKind {
  welcome,
  notifications,
  location,
  battery,
  camera,
  overlay,
  microphone,
  mailRecipient,
}

enum _PermissionStatusTone {
  neutral,
  success,
  warning,
  danger,
}

class _AppStartPermissionSetupScreenState
    extends State<AppStartPermissionSetupScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final TextEditingController _mailToCtrl = TextEditingController();

  int _index = 0;
  bool _busy = false;

  PermissionStatus? _notifStatus;
  PermissionStatus? _locationStatus;
  PermissionStatus? _batteryStatus;
  PermissionStatus? _cameraStatus;
  PermissionStatus? _microphoneStatus;
  bool? _overlayGranted;
  String _savedMailTo = '';

  final List<_PermissionStepKind> _steps = const [
    _PermissionStepKind.welcome,
    _PermissionStepKind.notifications,
    _PermissionStepKind.location,
    _PermissionStepKind.battery,
    _PermissionStepKind.camera,
    _PermissionStepKind.overlay,
    _PermissionStepKind.microphone,
    _PermissionStepKind.mailRecipient,
  ];

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mailToCtrl.addListener(_handleMailToChanged);
    _loadSavedMailRecipient();
    _refreshForStep(_steps.first);
  }

  void _handleMailToChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSavedMailRecipient() async {
    final cfg = await EmailConfig.load();
    if (!mounted) return;
    final value = cfg.to.trim();
    _mailToCtrl.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() => _savedMailTo = value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _refreshForStep(_steps[_index]);
  }

  Future<void> _refreshForStep(_PermissionStepKind kind) async {
    switch (kind) {
      case _PermissionStepKind.welcome:
        return;
      case _PermissionStepKind.notifications:
        final status = await Permission.notification.status;
        if (!mounted) return;
        setState(() => _notifStatus = status);
        return;
      case _PermissionStepKind.location:
        final status = await Permission.locationWhenInUse.status;
        if (!mounted) return;
        setState(() => _locationStatus = status);
        return;
      case _PermissionStepKind.battery:
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!mounted) return;
        setState(() => _batteryStatus = status);
        return;
      case _PermissionStepKind.camera:
        final status = await Permission.camera.status;
        if (!mounted) return;
        setState(() => _cameraStatus = status);
        return;
      case _PermissionStepKind.overlay:
        await _refreshOverlayPermissionStatus();
        return;
      case _PermissionStepKind.microphone:
        final status = await Permission.microphone.status;
        if (!mounted) return;
        setState(() => _microphoneStatus = status);
        return;
      case _PermissionStepKind.mailRecipient:
        final cfg = await EmailConfig.load();
        if (!mounted) return;
        final value = cfg.to.trim();
        _mailToCtrl.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        setState(() => _savedMailTo = value);
        return;
    }
  }

  Future<void> _refreshOverlayPermissionStatus() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!mounted) return;
    setState(() => _overlayGranted = granted);
  }

  String _statusLabelForPermission(PermissionStatus? status) {
    if (status == null) return '확인 전';
    if (status.isGranted) return '허용됨';
    if (status.isPermanentlyDenied) return '영구 거부됨';
    if (status.isDenied) return '거부됨';
    if (status.isRestricted || status.isLimited) return '제한됨';
    return status.toString();
  }

  _PermissionStatusTone _toneForPermission(PermissionStatus? status) {
    if (status == null) return _PermissionStatusTone.neutral;
    if (status.isGranted) return _PermissionStatusTone.success;
    if (status.isPermanentlyDenied) return _PermissionStatusTone.danger;
    if (status.isDenied || status.isRestricted || status.isLimited) {
      return _PermissionStatusTone.warning;
    }
    return _PermissionStatusTone.neutral;
  }

  String _overlayStatusLabel() {
    if (_overlayGranted == null) return '확인 전';
    return _overlayGranted == true ? '허용됨' : '미허용';
  }

  _PermissionStatusTone _overlayStatusTone() {
    if (_overlayGranted == null) return _PermissionStatusTone.neutral;
    return _overlayGranted == true
        ? _PermissionStatusTone.success
        : _PermissionStatusTone.warning;
  }

  bool _isValidGmailToList(String csv) {
    if (!EmailConfig.isValidToList(csv)) return false;
    final addresses = csv
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    for (final address in addresses) {
      if (!address.toLowerCase().endsWith('@gmail.com')) return false;
    }
    return true;
  }

  String _mailRecipientStatusLabel() {
    final current = _mailToCtrl.text.trim();
    if (current.isEmpty && _savedMailTo.isEmpty) return '미입력';
    if (!_isValidGmailToList(current)) return '지메일만 가능';
    if (current != _savedMailTo) return '저장 필요';
    return '저장됨';
  }

  _PermissionStatusTone _mailRecipientStatusTone() {
    final current = _mailToCtrl.text.trim();
    if (current.isEmpty && _savedMailTo.isEmpty) {
      return _PermissionStatusTone.neutral;
    }
    if (!_isValidGmailToList(current)) return _PermissionStatusTone.danger;
    if (current != _savedMailTo) return _PermissionStatusTone.warning;
    return _PermissionStatusTone.success;
  }

  bool _canProceed(_PermissionStepKind kind) {
    switch (kind) {
      case _PermissionStepKind.welcome:
        return true;
      case _PermissionStepKind.notifications:
        return _notifStatus?.isGranted == true;
      case _PermissionStepKind.location:
        return _locationStatus?.isGranted == true;
      case _PermissionStepKind.battery:
        return _batteryStatus?.isGranted == true;
      case _PermissionStepKind.camera:
        return _cameraStatus?.isGranted == true;
      case _PermissionStepKind.overlay:
        return _overlayGranted == true;
      case _PermissionStepKind.microphone:
        return _microphoneStatus?.isGranted == true;
      case _PermissionStepKind.mailRecipient:
        final current = _mailToCtrl.text.trim();
        return _isValidGmailToList(current) &&
            current.isNotEmpty &&
            current == _savedMailTo;
    }
  }

  Future<void> _showNeedPermissionDialog(String permissionName) async {
    if (!mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '$permissionName 권한 안내',
      builder: (dialogContext) {
        return _PermissionPromptDialog(
          icon: Icons.settings_suggest_rounded,
          title: '$permissionName 권한 필요',
          message: '설정에서 권한을 허용한 뒤 앱으로 돌아와 설정 재확인 버튼을 눌러주세요.',
          secondaryLabel: '닫기',
          onSecondary: () => Navigator.of(dialogContext).pop(),
          primaryLabel: '설정 열기',
          onPrimary: () async {
            await openAppSettings();
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
        );
      },
    );
  }

  Future<void> _showNeedOverlayPermissionDialog() async {
    if (!mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '다른 앱 위 사용 허용 안내',
      builder: (dialogContext) {
        return _PermissionPromptDialog(
          icon: Icons.picture_in_picture_alt_rounded,
          title: '다른 앱 위 사용 허용 필요',
          message:
              '이 권한은 시스템 설정에서 직접 허용해야 합니다. 다른 앱 위에 표시를 허용한 뒤 앱으로 돌아와 설정 재확인 버튼을 눌러주세요.',
          secondaryLabel: '닫기',
          onSecondary: () => Navigator.of(dialogContext).pop(),
          primaryLabel: '설정 열기',
          onPrimary: () async {
            Navigator.of(dialogContext).pop();
            await _openOverlaySettingsHint();
          },
        );
      },
    );
  }

  Future<void> _showNeedMailRecipientDialog() async {
    if (!mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '지메일 수신자 입력 안내',
      builder: (dialogContext) {
        return _PermissionPromptDialog(
          icon: Icons.mail_outline_rounded,
          title: '지메일 수신자 입력 필요',
          message: '수신자(To)를 지메일 주소로 입력하고 저장해 주세요.',
          primaryLabel: '확인',
          onPrimary: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  Future<void> _openSettingsHint() async {
    await openAppSettings();
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '설정에서 허용한 뒤 앱으로 돌아와 설정 재확인을 눌러주세요.',
      usePromptUi: true,
    );
  }

  Future<void> _openOverlaySettingsHint() async {
    await FlutterOverlayWindow.requestPermission();
    if (!mounted) return;
    await _refreshOverlayPermissionStatus();
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '시스템 설정에서 허용한 뒤 앱으로 돌아오면 상태가 반영됩니다.',
      usePromptUi: true,
    );
  }

  Future<void> _requestNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notifStatus = status);
      if (!status.isGranted) await _showNeedPermissionDialog('알림');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!mounted) return;
      setState(() => _locationStatus = status);
      if (!status.isGranted) await _showNeedPermissionDialog('위치');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestBattery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
      setState(() => _batteryStatus = status);
      if (!status.isGranted) {
        await _showNeedPermissionDialog('배터리 최적화 제외');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _cameraStatus = status);
      if (!status.isGranted) await _showNeedPermissionDialog('카메라');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestMicrophone() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.microphone.request();
      if (!mounted) return;
      setState(() => _microphoneStatus = status);
      if (!status.isGranted) {
        await _showNeedPermissionDialog('오디오 · 마이크');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!mounted) return;
    if (granted == true) {
      setState(() => _overlayGranted = true);
      return;
    }

    await _openOverlaySettingsHint();
    if (!mounted) return;
    await _refreshOverlayPermissionStatus();
    if (!mounted || _overlayGranted == true) return;
    await _showNeedOverlayPermissionDialog();
  }

  Future<void> _saveMailRecipient() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final to = _mailToCtrl.text.trim();
      if (!_isValidGmailToList(to)) {
        await _showNeedMailRecipientDialog();
        return;
      }

      await EmailConfig.save(EmailConfig(to: to));
      if (!mounted) return;
      setState(() => _savedMailTo = to);
      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.gmailRecipientSaveSuccess,
        usePromptUi: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recheckCurrent() async {
    if (_busy) return;
    final kind = _steps[_index];
    setState(() => _busy = true);
    try {
      await _refreshForStep(kind);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _moveToPage(int page) {
    if (_reduceMotion) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: PromptUiMotion.layout,
      curve: PromptUiMotion.enter,
    );
  }

  void _goNext() {
    if (_index >= _steps.length - 1) return;
    _moveToPage(_index + 1);
  }

  void _goPrev() {
    if (_index <= 0) return;
    _moveToPage(_index - 1);
  }

  Future<void> _completePermissions() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.startGate,
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPageHeader(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PromptEntrance(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 42, color: tokens.onAccentContainer),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(
              description,
              style: textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(
    BuildContext context, {
    required String label,
    required String status,
    required _PermissionStatusTone tone,
    required Future<void> Function() onRequest,
    Future<void> Function()? onOpenSettings,
  }) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PromptEntrance(
      delay: const Duration(milliseconds: 70),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _PermissionStatusPill(label: status, tone: tone),
              ],
            ),
            const SizedBox(height: 16),
            PromptButton(
              label: _busy ? '처리 중' : '허용 요청',
              icon: Icons.verified_user_rounded,
              onPressed: _busy ? null : onRequest,
              loading: _busy,
              expand: true,
              haptic: PromptHaptic.selection,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 420;
                final settingsButton = PromptButton(
                  label: '설정 열기',
                  icon: Icons.settings_rounded,
                  variant: PromptButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : onOpenSettings ?? _openSettingsHint,
                  expand: true,
                );
                final recheckButton = PromptButton(
                  label: '설정 재확인',
                  icon: Icons.refresh_rounded,
                  variant: PromptButtonVariant.tertiary,
                  onPressed: _busy ? null : _recheckCurrent,
                  expand: true,
                );

                if (stacked) {
                  return Column(
                    children: [
                      settingsButton,
                      const SizedBox(height: 8),
                      recheckButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: settingsButton),
                    const SizedBox(width: 10),
                    Expanded(child: recheckButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMailRecipientCard(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PromptEntrance(
      delay: const Duration(milliseconds: 70),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '지메일 수신자(To)',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _PermissionStatusPill(
                  label: _mailRecipientStatusLabel(),
                  tone: _mailRecipientStatusTone(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mailToCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              scrollPadding: const EdgeInsets.only(bottom: 260),
              decoration: const InputDecoration(
                labelText: '수신자(To)',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              onSubmitted: (_) => _saveMailRecipient(),
            ),
            const SizedBox(height: 14),
            PromptButton(
              label: _busy ? '처리 중' : '지메일 수신자 저장',
              icon: Icons.save_rounded,
              onPressed: _busy ? null : _saveMailRecipient,
              loading: _busy,
              expand: true,
              haptic: PromptHaptic.selection,
            ),
            const SizedBox(height: 10),
            PromptButton(
              label: '저장값 다시 불러오기',
              icon: Icons.restore_rounded,
              variant: PromptButtonVariant.secondary,
              onPressed: _busy ? null : _loadSavedMailRecipient,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableStep(
    BuildContext context, {
    required Widget child,
  }) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            24,
            20,
            math.max(24, media.viewInsets.bottom + 24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  Widget _buildPermissionStep(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String label,
    required String status,
    required _PermissionStatusTone tone,
    required Future<void> Function() onRequest,
    Future<void> Function()? onOpenSettings,
  }) {
    return _buildScrollableStep(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPageHeader(context, icon, title, description),
          const SizedBox(height: 22),
          _buildPermissionCard(
            context,
            label: label,
            status: status,
            tone: tone,
            onRequest: onRequest,
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, _PermissionStepKind kind) {
    switch (kind) {
      case _PermissionStepKind.welcome:
        return _buildScrollableStep(
          context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPageHeader(
                context,
                Icons.verified_user_outlined,
                '권한 설정',
                '서비스 이용에 필요한 권한과 메일 수신자 정보를 순서대로 확인합니다.',
              ),
              const SizedBox(height: 22),
              const _PermissionWelcomePanel(),
            ],
          ),
        );
      case _PermissionStepKind.notifications:
        return _buildPermissionStep(
          context,
          icon: Icons.notifications_active_outlined,
          title: '알림 권한',
          description: '리마인더와 상태 알림을 위해 필요합니다.',
          label: '알림',
          status: _statusLabelForPermission(_notifStatus),
          tone: _toneForPermission(_notifStatus),
          onRequest: _requestNotifications,
        );
      case _PermissionStepKind.location:
        return _buildPermissionStep(
          context,
          icon: Icons.my_location_outlined,
          title: '위치 권한',
          description: '근무와 이동 관련 기능을 위해 필요할 수 있습니다.',
          label: '위치',
          status: _statusLabelForPermission(_locationStatus),
          tone: _toneForPermission(_locationStatus),
          onRequest: _requestLocation,
        );
      case _PermissionStepKind.battery:
        return _buildPermissionStep(
          context,
          icon: Icons.battery_saver_outlined,
          title: '배터리 최적화 제외',
          description: '포그라운드 서비스 안정성을 위해 필요합니다.',
          label: '배터리 최적화 제외',
          status: _statusLabelForPermission(_batteryStatus),
          tone: _toneForPermission(_batteryStatus),
          onRequest: _requestBattery,
        );
      case _PermissionStepKind.camera:
        return _buildPermissionStep(
          context,
          icon: Icons.photo_camera_outlined,
          title: '카메라 권한',
          description: '업무 사진 촬영 기능을 위해 필요합니다.',
          label: '카메라',
          status: _statusLabelForPermission(_cameraStatus),
          tone: _toneForPermission(_cameraStatus),
          onRequest: _requestCamera,
        );
      case _PermissionStepKind.overlay:
        return _buildPermissionStep(
          context,
          icon: Icons.picture_in_picture_alt_outlined,
          title: '다른 앱 위 사용 허용',
          description: '오버레이 표시 기능을 위해 필요합니다.',
          label: '다른 앱 위에 표시',
          status: _overlayStatusLabel(),
          tone: _overlayStatusTone(),
          onRequest: _requestOverlay,
          onOpenSettings: _openOverlaySettingsHint,
        );
      case _PermissionStepKind.microphone:
        return _buildPermissionStep(
          context,
          icon: Icons.mic_none_outlined,
          title: '마이크 권한',
          description: '음성 기능과 무전기 송신 기능을 위해 필요합니다.',
          label: '오디오 · 마이크',
          status: _statusLabelForPermission(_microphoneStatus),
          tone: _toneForPermission(_microphoneStatus),
          onRequest: _requestMicrophone,
        );
      case _PermissionStepKind.mailRecipient:
        return _buildScrollableStep(
          context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPageHeader(
                context,
                Icons.mail_outline_rounded,
                '메일 수신자 등록',
                '서비스 설정과 동일한 방식으로 지메일 수신자(To)를 저장해야 다음으로 진행할 수 있습니다.',
              ),
              const SizedBox(height: 22),
              _buildMailRecipientCard(context),
            ],
          ),
        );
    }
  }

  Widget _buildProgress(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final progress = (_index + 1) / _steps.length;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PromptUiShapes.pill),
            child: TweenAnimationBuilder<double>(
              duration: _reduceMotion ? Duration.zero : PromptUiMotion.component,
              curve: PromptUiMotion.standard,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: tokens.surfaceOverlay,
                  color: tokens.accent,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        AnimatedContainer(
          duration: _reduceMotion ? Duration.zero : PromptUiMotion.selection,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(PromptUiShapes.pill),
            border: Border.all(
              color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
            ),
          ),
          child: Text(
            '${_index + 1}/${_steps.length}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tokens.onAccentContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigation(
    BuildContext context, {
    required bool isLast,
    required bool canNext,
  }) {
    final previous = PromptButton(
      label: '이전',
      icon: Icons.arrow_back_rounded,
      variant: PromptButtonVariant.tertiary,
      onPressed: _index == 0 || _busy ? null : _goPrev,
      expand: true,
    );
    final next = PromptButton(
      label: isLast ? (_busy ? '저장 중' : '정책 확인으로') : '다음',
      icon: isLast ? Icons.policy_rounded : Icons.arrow_forward_rounded,
      onPressed: !_busy && canNext
          ? isLast
              ? _completePermissions
              : _goNext
          : null,
      loading: isLast && _busy,
      expand: true,
      haptic: PromptHaptic.selection,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              next,
              const SizedBox(height: 8),
              previous,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: previous),
            const SizedBox(width: 12),
            Expanded(child: next),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mailToCtrl.removeListener(_handleMailToChanged);
    _mailToCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final kind = _steps[_index];
          final isLast = _index == _steps.length - 1;
          final canNext = _canProceed(kind);
          final iconBrightness =
              tokens.isDark ? Brightness.light : Brightness.dark;

          return PopScope(
            canPop: false,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.surface,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: tokens.borderSubtle,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                resizeToAvoidBottomInset: true,
                appBar: AppBar(
                  title: const Text('권한 설정'),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                ),
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          children: [
                            _buildProgress(context),
                            const SizedBox(height: 14),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tokens.surface,
                                  borderRadius: BorderRadius.circular(
                                    PromptUiShapes.dialog,
                                  ),
                                  border: Border.all(color: tokens.borderSubtle),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: PageView.builder(
                                  controller: _pageController,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  onPageChanged: (index) async {
                                    setState(() => _index = index);
                                    await _refreshForStep(_steps[index]);
                                  },
                                  itemCount: _steps.length,
                                  itemBuilder: (context, index) {
                                    return KeyedSubtree(
                                      key: ValueKey(_steps[index]),
                                      child: _buildStep(
                                        context,
                                        _steps[index],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: tokens.surfaceRaised,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.card,
                                ),
                                border:
                                    Border.all(color: tokens.borderSubtle),
                              ),
                              child: _buildNavigation(
                                context,
                                isLast: isLast,
                                canNext: canNext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PermissionWelcomePanel extends StatelessWidget {
  const _PermissionWelcomePanel();

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PromptEntrance(
      delay: const Duration(milliseconds: 70),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          children: [
            _WelcomeRow(
              icon: Icons.touch_app_rounded,
              title: '한 단계씩 진행',
              description: '각 권한 상태를 확인하고 허용된 경우에만 다음 단계로 이동합니다.',
              tokens: tokens,
              textTheme: textTheme,
            ),
            const SizedBox(height: 14),
            _WelcomeRow(
              icon: Icons.settings_rounded,
              title: '시스템 설정 연동',
              description: '직접 허용이 필요한 권한은 시스템 설정으로 안전하게 연결합니다.',
              tokens: tokens,
              textTheme: textTheme,
            ),
            const SizedBox(height: 14),
            _WelcomeRow(
              icon: Icons.lock_outline_rounded,
              title: '필요한 항목만 확인',
              description: '서비스 동작에 필요한 권한과 메일 수신자 정보만 확인합니다.',
              tokens: tokens,
              textTheme: textTheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeRow extends StatelessWidget {
  const _WelcomeRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.tokens,
    required this.textTheme,
  });

  final IconData icon;
  final String title;
  final String description;
  final PromptUiTokens tokens;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
          ),
          child: Icon(icon, color: tokens.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionStatusPill extends StatelessWidget {
  const _PermissionStatusPill({
    required this.label,
    required this.tone,
  });

  final String label;
  final _PermissionStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colors = switch (tone) {
      _PermissionStatusTone.success => (
          background: tokens.successContainer,
          foreground: tokens.onSuccessContainer,
          border: tokens.success,
          icon: Icons.check_circle_rounded,
        ),
      _PermissionStatusTone.warning => (
          background: tokens.warningContainer,
          foreground: tokens.onWarningContainer,
          border: tokens.warning,
          icon: Icons.warning_amber_rounded,
        ),
      _PermissionStatusTone.danger => (
          background: tokens.dangerContainer,
          foreground: tokens.onDangerContainer,
          border: tokens.danger,
          icon: Icons.error_outline_rounded,
        ),
      _PermissionStatusTone.neutral => (
          background: tokens.surfaceOverlay,
          foreground: tokens.textSecondary,
          border: tokens.borderSubtle,
          icon: Icons.info_outline_rounded,
        ),
    };

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: colors.border.withOpacity(0.58)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(colors.icon, size: 16, color: colors.foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionPromptDialog extends StatelessWidget {
  const _PermissionPromptDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final PromptAction onPrimary;
  final String? secondaryLabel;
  final PromptAction? onSecondary;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tokens.warningContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: tokens.warning, size: 28),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final primary = PromptButton(
                  label: primaryLabel,
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onPrimary,
                  expand: true,
                  haptic: PromptHaptic.selection,
                );
                if (secondaryLabel == null || onSecondary == null) {
                  return primary;
                }
                final secondary = PromptButton(
                  label: secondaryLabel!,
                  variant: PromptButtonVariant.tertiary,
                  onPressed: onSecondary,
                  expand: true,
                );
                if (constraints.maxWidth < 340) {
                  return Column(
                    children: [
                      primary,
                      const SizedBox(height: 8),
                      secondary,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: secondary),
                    const SizedBox(width: 10),
                    Expanded(child: primary),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptEntrance extends StatelessWidget {
  const _PromptEntrance({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final duration = PromptUiMotion.layout + delay;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: PromptUiMotion.enter,
      builder: (context, value, child) {
        final adjusted = delay == Duration.zero
            ? value
            : ((value * duration.inMilliseconds - delay.inMilliseconds) /
                    PromptUiMotion.layout.inMilliseconds)
                .clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: adjusted,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - adjusted)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
