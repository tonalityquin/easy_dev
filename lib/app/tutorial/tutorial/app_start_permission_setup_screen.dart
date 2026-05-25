import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/config/email_config.dart';
import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/utils/status_dialog.dart';

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
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    _refreshForStep(_steps[_index]);
  }

  Future<void> _refreshForStep(_PermissionStepKind kind) async {
    switch (kind) {
      case _PermissionStepKind.welcome:
        return;
      case _PermissionStepKind.notifications:
        final s = await Permission.notification.status;
        if (!mounted) return;
        setState(() => _notifStatus = s);
        return;
      case _PermissionStepKind.location:
        final s = await Permission.locationWhenInUse.status;
        if (!mounted) return;
        setState(() => _locationStatus = s);
        return;
      case _PermissionStepKind.battery:
        final s = await Permission.ignoreBatteryOptimizations.status;
        if (!mounted) return;
        setState(() => _batteryStatus = s);
        return;
      case _PermissionStepKind.camera:
        final s = await Permission.camera.status;
        if (!mounted) return;
        setState(() => _cameraStatus = s);
        return;
      case _PermissionStepKind.overlay:
        await _refreshOverlayPermissionStatus();
        return;
      case _PermissionStepKind.microphone:
        final s = await Permission.microphone.status;
        if (!mounted) return;
        setState(() => _microphoneStatus = s);
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

  String _statusLabelForPermission(PermissionStatus? s) {
    if (s == null) return '확인 전';
    if (s.isGranted) return '허용됨';
    if (s.isPermanentlyDenied) return '영구 거부됨';
    if (s.isDenied) return '거부됨';
    if (s.isRestricted) return '제한됨';
    if (s.isLimited) return '제한됨';
    return s.toString();
  }

  String _overlayStatusLabel() {
    if (_overlayGranted == null) return '확인 전';
    return _overlayGranted == true ? '허용됨' : '미허용';
  }

  bool _isValidGmailToList(String csv) {
    if (!EmailConfig.isValidToList(csv)) return false;
    final list = csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    for (final addr in list) {
      if (!addr.toLowerCase().endsWith('@gmail.com')) {
        return false;
      }
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

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('$permissionName 권한 필요'),
          content: const Text(
            '설정에서 권한을 허용한 뒤 앱으로 돌아와 “설정 재확인” 버튼을 눌러주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () async {
                await openAppSettings();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('설정 열기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showNeedOverlayPermissionDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('다른 앱 위 사용 허용 필요'),
          content: const Text(
            '이 권한은 일반 권한처럼 앱 안에서 바로 허용되지 않습니다.\n\n'
            '시스템 설정 화면에서 “다른 앱 위에 표시”를 허용한 뒤 앱으로 돌아와 “설정 재확인” 버튼을 눌러주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () async {
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _openOverlaySettingsHint();
              },
              child: const Text('설정 열기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showNeedMailRecipientDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('지메일 수신자 입력 필요'),
          content: const Text('수신자(To)를 지메일 주소로 입력하고 저장해 주세요.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSettingsHint() async {
    await openAppSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('설정에서 허용 후 돌아오면 “설정 재확인”을 눌러주세요.'),
      ),
    );
  }

  Future<void> _openOverlaySettingsHint() async {
    await FlutterOverlayWindow.requestPermission();
    if (!mounted) return;
    await _refreshOverlayPermissionStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('시스템 설정에서 허용 후 돌아오면 상태가 자동 반영되거나 “설정 재확인”을 눌러주세요.'),
      ),
    );
  }

  Future<void> _requestNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notifStatus = s);
      if (!s.isGranted) {
        await _showNeedPermissionDialog('알림');
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _requestLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await Permission.locationWhenInUse.request();
      if (!mounted) return;
      setState(() => _locationStatus = s);
      if (!s.isGranted) {
        await _showNeedPermissionDialog('위치');
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _requestBattery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
      setState(() => _batteryStatus = s);
      if (!s.isGranted) {
        await _showNeedPermissionDialog('배터리 최적화 제외');
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _requestCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _cameraStatus = s);
      if (!s.isGranted) {
        await _showNeedPermissionDialog('카메라');
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _requestMicrophone() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await Permission.microphone.request();
      if (!mounted) return;
      setState(() => _microphoneStatus = s);
      if (!s.isGranted) {
        await _showNeedPermissionDialog('오디오 · 마이크');
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
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

    if (!mounted) return;
    if (_overlayGranted != true) {
      await _showNeedOverlayPermissionDialog();
    }
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
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _recheckCurrent() async {
    if (_busy) return;
    final kind = _steps[_index];
    setState(() => _busy = true);
    try {
      await _refreshForStep(kind);
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  void _goNext() {
    if (_index >= _steps.length - 1) return;
    final next = _index + 1;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _goPrev() {
    if (_index <= 0) return;
    final prev = _index - 1;
    _pageController.animateToPage(
      prev,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
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
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Widget _buildPageHeader(
    BuildContext context,
    IconData icon,
    String title,
    String desc,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(icon, size: 46, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPermissionCard(
    BuildContext context, {
    required String label,
    required String status,
    required Future<void> Function() onRequest,
    Future<void> Function()? onOpenSettings,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(status),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : () async => onRequest(),
                child: Text(_busy ? '처리 중' : '허용 요청'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (onOpenSettings != null) {
                              await onOpenSettings();
                              return;
                            }
                            await _openSettingsHint();
                          },
                    child: const Text('설정 열기'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _recheckCurrent,
                    child: const Text('설정 재확인'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMailRecipientCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '지메일 수신자(To)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_mailRecipientStatusLabel()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mailToCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              scrollPadding: const EdgeInsets.only(bottom: 260),
              decoration: const InputDecoration(
                labelText: '수신자(To)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              onSubmitted: (_) => _saveMailRecipient(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _saveMailRecipient,
                child: Text(_busy ? '처리 중' : '지메일 수신자 저장'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _loadSavedMailRecipient,
                child: const Text('저장값 다시 불러오기'),
              ),
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
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            math.max(18, viewInsetsBottom + 18),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
          const SizedBox(height: 18),
          _buildPermissionCard(
            context,
            label: label,
            status: status,
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
          child: _buildPageHeader(
            context,
            Icons.verified_user_outlined,
            '권한 설정',
            '서비스 이용에 필요한 필수 권한을 순서대로 허용해 주세요.',
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
              const SizedBox(height: 18),
              _buildMailRecipientCard(context),
            ],
          ),
        );
    }
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
    final colorScheme = Theme.of(context).colorScheme;
    final kind = _steps[_index];
    final isLast = _index == _steps.length - 1;
    final canNext = _canProceed(kind);

    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('권한 설정'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                Expanded(
                  child: Card(
                    elevation: 1,
                    clipBehavior: Clip.antiAlias,
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (idx) async {
                        setState(() => _index = idx);
                        await _refreshForStep(_steps[idx]);
                      },
                      itemCount: _steps.length,
                      itemBuilder: (context, idx) =>
                          _buildStep(context, _steps[idx]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (i) {
                    final selected = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: selected ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            selected ? colorScheme.primary : colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: _index == 0 ? null : _goPrev,
                      child: const Text('이전'),
                    ),
                    const Spacer(),
                    if (!isLast)
                      FilledButton(
                        onPressed: (!_busy && canNext) ? _goNext : null,
                        child: const Text('다음'),
                      )
                    else
                      FilledButton(
                        onPressed:
                            (!_busy && canNext) ? _completePermissions : null,
                        child: Text(_busy ? '저장 중' : '정책 확인으로'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
