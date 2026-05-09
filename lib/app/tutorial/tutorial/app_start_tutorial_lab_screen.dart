import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/config/email_config.dart';
import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/startup_tasks.dart';
import '../../../app/utils/status_dialog.dart';

class AppStartTutorialLabScreen extends StatefulWidget {
  const AppStartTutorialLabScreen({super.key});

  @override
  State<AppStartTutorialLabScreen> createState() =>
      _AppStartTutorialLabScreenState();
}

enum _StepKind {
  welcome,
  notifications,
  location,
  battery,
  camera,
  overlay,
  microphone,
  mailRecipient,
  usedBefore,
}

class _AppStartTutorialLabScreenState extends State<AppStartTutorialLabScreen>
    with WidgetsBindingObserver {
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

  final List<_StepKind> _steps = const [
    _StepKind.welcome,
    _StepKind.notifications,
    _StepKind.location,
    _StepKind.battery,
    _StepKind.camera,
    _StepKind.overlay,
    _StepKind.microphone,
    _StepKind.mailRecipient,
    _StepKind.usedBefore,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mailToCtrl.addListener(_handleMailToChanged);
    _loadSavedMailRecipient();
    _refreshForStep(_steps.first);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    _refreshForStep(_steps[_index]);
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

  Future<void> _refreshForStep(_StepKind kind) async {
    switch (kind) {
      case _StepKind.welcome:
      case _StepKind.usedBefore:
        return;
      case _StepKind.notifications:
        final s = await Permission.notification.status;
        if (!mounted) return;
        setState(() => _notifStatus = s);
        return;
      case _StepKind.location:
        final s = await Permission.locationWhenInUse.status;
        if (!mounted) return;
        setState(() => _locationStatus = s);
        return;
      case _StepKind.battery:
        final s = await Permission.ignoreBatteryOptimizations.status;
        if (!mounted) return;
        setState(() => _batteryStatus = s);
        return;
      case _StepKind.camera:
        final s = await Permission.camera.status;
        if (!mounted) return;
        setState(() => _cameraStatus = s);
        return;
      case _StepKind.overlay:
        await _refreshOverlayPermissionStatus();
        return;
      case _StepKind.microphone:
        final s = await Permission.microphone.status;
        if (!mounted) return;
        setState(() => _microphoneStatus = s);
        return;
      case _StepKind.mailRecipient:
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

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    switch (v) {
      case 'service':
        return null;
      case 'tablet':
        return 'tablet';
      case 'single':
      case 'simple':
        return 'single';
      case 'double':
      case 'lite':
      case 'light':
        return 'double';
      case 'triple':
      case 'normal':
        return 'triple';
      case 'minor':
        return 'minor';
      default:
        return null;
    }
  }

  Future<String?> _resolveReturnUserRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _normalizeMode(prefs.getString('mode'));
    switch (mode) {
      case 'single':
        return AppRoutes.singleLogin;
      case 'tablet':
        return AppRoutes.tabletLogin;
      case 'double':
        return AppRoutes.doubleLogin;
      case 'triple':
        return AppRoutes.tripleLogin;
      case 'minor':
        return AppRoutes.minorLogin;
      default:
        return null;
    }
  }

  bool _canProceed(_StepKind kind) {
    switch (kind) {
      case _StepKind.welcome:
        return true;
      case _StepKind.notifications:
        return _notifStatus?.isGranted == true;
      case _StepKind.location:
        return _locationStatus?.isGranted == true;
      case _StepKind.battery:
        return _batteryStatus?.isGranted == true;
      case _StepKind.camera:
        return _cameraStatus?.isGranted == true;
      case _StepKind.overlay:
        return _overlayGranted == true;
      case _StepKind.microphone:
        return _microphoneStatus?.isGranted == true;
      case _StepKind.mailRecipient:
        final current = _mailToCtrl.text.trim();
        return _isValidGmailToList(current) &&
            current.isNotEmpty &&
            current == _savedMailTo;
      case _StepKind.usedBefore:
        return false;
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
          content: const Text('수신자(To)를 입력하고 저장해 주세요.'),
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
        await _showNeedPermissionDialog('카메라(사진 촬영)');
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

  Future<void> _setUsedBeforeAndRoute(bool usedBefore) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppStartFlowPrefs.setUsedBefore(usedBefore);
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      if (!mounted) return;

      if (usedBefore) {
        await AppStartFlowPrefs.setSelectorScreenTutorialDone(true);
        await StartupTasks.runAfterPermissions();
        if (!mounted) return;
        final route = await _resolveReturnUserRoute();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          route ?? AppRoutes.selector,
          (r) => false,
        );
        return;
      }

      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.appStartNextTutorialFull);
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 76, color: cs.primary),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: cs.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;

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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
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
    final cs = Theme.of(context).colorScheme;

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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
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

  Widget _buildStep(BuildContext context, _StepKind kind) {
    switch (kind) {
      case _StepKind.welcome:
        return _buildScrollableStep(
          context,
          child: _buildPageHeader(
            context,
            Icons.auto_awesome_rounded,
            '권한 설정 튜토리얼',
            '필수 권한과 필수 초기 설정을 단계별로 완료해야 다음으로 진행할 수 있습니다.',
          ),
        );
      case _StepKind.notifications:
        return _buildPermissionStep(
          context,
          icon: Icons.notifications_active_rounded,
          title: '알림 권한',
          description: '리마인더와 상태 알림을 위해 필요합니다.',
          label: '알림',
          status: _statusLabelForPermission(_notifStatus),
          onRequest: _requestNotifications,
        );
      case _StepKind.location:
        return _buildPermissionStep(
          context,
          icon: Icons.my_location_rounded,
          title: '위치 권한',
          description: '근무/이동 관련 기능을 위해 필요할 수 있습니다.',
          label: '위치(앱 사용 중)',
          status: _statusLabelForPermission(_locationStatus),
          onRequest: _requestLocation,
        );
      case _StepKind.battery:
        return _buildPermissionStep(
          context,
          icon: Icons.battery_saver_rounded,
          title: '배터리 최적화 제외',
          description: '포그라운드 서비스 안정성을 위해 필요합니다.',
          label: '배터리 최적화 제외',
          status: _statusLabelForPermission(_batteryStatus),
          onRequest: _requestBattery,
        );
      case _StepKind.camera:
        return _buildPermissionStep(
          context,
          icon: Icons.photo_camera_rounded,
          title: '사진 촬영 권한',
          description: '업무 사진 촬영 기능을 위해 필요합니다.',
          label: '카메라(사진 촬영)',
          status: _statusLabelForPermission(_cameraStatus),
          onRequest: _requestCamera,
        );
      case _StepKind.overlay:
        return _buildPermissionStep(
          context,
          icon: Icons.picture_in_picture_alt_rounded,
          title: '다른 앱 위 사용 허용',
          description: '오버레이 표시 기능을 위해 필요합니다.',
          label: '다른 앱 위에 표시',
          status: _overlayStatusLabel(),
          onRequest: _requestOverlay,
          onOpenSettings: _openOverlaySettingsHint,
        );
      case _StepKind.microphone:
        return _buildPermissionStep(
          context,
          icon: Icons.mic_rounded,
          title: '오디오 · 마이크 권한',
          description: '무전기 송신과 음성 기능 사용을 위해 필요합니다.',
          label: '오디오 · 마이크',
          status: _statusLabelForPermission(_microphoneStatus),
          onRequest: _requestMicrophone,
        );
      case _StepKind.mailRecipient:
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
      case _StepKind.usedBefore:
        return _buildScrollableStep(
          context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPageHeader(
                context,
                Icons.help_outline_rounded,
                '다음 튜토리얼 선택',
                '앱을 사용해본 적이 있나요?',
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _setUsedBeforeAndRoute(true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('예, 사용해본 적이 있어요'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _setUsedBeforeAndRoute(false),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('아니요, 처음이에요'),
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _mailToCtrl.removeListener(_handleMailToChanged);
    _mailToCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = _steps[_index];
    final isLast = _index == _steps.length - 1;
    final canNext = _canProceed(kind);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('앱 시작 튜토리얼'),
          centerTitle: true,
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
                        color: selected ? cs.primary : cs.outlineVariant,
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
