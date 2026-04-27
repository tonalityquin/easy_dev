import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../widgets/dialog/status_dialog_package/status_dialog.dart';
import '../../../application/discord/discord_config.dart';

class DiscordBottomSheet extends StatefulWidget {
  const DiscordBottomSheet({super.key, required this.rootContext});

  final BuildContext rootContext;

  @override
  State<DiscordBottomSheet> createState() =>
      _DiscordBottomSheetState();
}

class _DiscordBottomSheetState
    extends State<DiscordBottomSheet> {
  static const String _discordSchemeUrl = 'discord://';

  static const String _androidStoreWeb =
      'https://play.google.com/store/apps/details?id=com.discord';
  static const String _androidStoreMarket = 'market://details?id=com.discord';

  static const String _iosStoreUrl =
      'https://apps.apple.com/app/discord-chat-talk-hangout/id985746746';

  final _inviteController = TextEditingController();

  int _currentStep = 0;
  bool _loading = true;

  BuildContext get _statusContext =>
      widget.rootContext.mounted ? widget.rootContext : context;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _showSuccessStatus(String title) {
    return StatusDialog.showSuccess(
      _statusContext,
      title: title,
    );
  }

  Future<void> _showFailureStatus(String title) {
    return StatusDialog.showFailure(
      _statusContext,
      title: title,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _inviteController.text = prefs.getString(discordWalkieInviteUrlKey) ?? '';
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      discordWalkieInviteUrlKey,
      _inviteController.text.trim(),
    );
  }

  Future<void> _clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(discordWalkieInviteUrlKey);
    await prefs.setBool(discordWalkieTutorialDoneKey, false);
    _inviteController.clear();
    if (!mounted) return;
    setState(() {
      _currentStep = 0;
    });
    await _showSuccessStatus(StatusDialog.savedInviteLinkResetSuccess);
  }

  Future<bool> _launchExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyInviteLink(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    await _showSuccessStatus(StatusDialog.inviteLinkCopySuccess);
  }

  Future<String?> _readClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Future<void> _pasteInviteFromClipboard() async {
    final text = await _readClipboard();
    if (text == null) {
      await _showFailureStatus(StatusDialog.clipboardTextNotFound);
      return;
    }
    if (!isDiscordInviteUrl(text)) {
      await _showFailureStatus(StatusDialog.discordInviteUrlInvalid);
      return;
    }
    _inviteController.text = text;
    await _save();
    if (mounted) {
      setState(() {});
    }
    await _showSuccessStatus(StatusDialog.discordInviteUrlSaveSuccess);
  }

  Future<void> _openDiscordOrStore() async {
    final opened = await _launchExternal(_discordSchemeUrl);
    if (opened) return;

    if (Platform.isIOS) {
      await _launchExternal(_iosStoreUrl);
      return;
    }

    final ok = await _launchExternal(_androidStoreMarket);
    if (!ok) {
      await _launchExternal(_androidStoreWeb);
    }
  }

  Future<void> _openInvite() async {
    final url = _inviteController.text.trim();
    if (!isDiscordInviteUrl(url)) {
      await _showFailureStatus(StatusDialog.discordInviteUrlPasteRequired);
      return;
    }
    await _save();
    final ok = await _launchExternal(url);
    if (!ok) {
      await _showFailureStatus(StatusDialog.externalLinkOpenFailed);
    }
  }

  Future<void> _markDone() async {
    final invite = _inviteController.text.trim();
    if (!isDiscordInviteUrl(invite)) {
      await _showFailureStatus(StatusDialog.discordInviteUrlRequired);
      return;
    }
    await _save();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(discordWalkieTutorialDoneKey, true);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }

  Widget _hint(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
    );
  }

  Step _installStep() {
    return Step(
      title: const Text('디스코드 설치'),
      subtitle: const Text('처음이라면 먼저 설치'),
      isActive: _currentStep >= 0,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('이 단계에서 할 일'),
          const SizedBox(height: 8),
          _hint('1) 아래 버튼으로 디스코드를 설치하세요.\n2) 설치가 끝나면 다시 이 앱으로 돌아오면 됩니다.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openDiscordOrStore,
            icon: const Icon(Icons.download_rounded),
            label: const Text('디스코드 설치/열기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => _currentStep = 1),
            child: const Text('설치했어요 (다음)'),
          ),
        ],
      ),
    );
  }

  Step _signupStep() {
    return Step(
      title: const Text('계정 만들기'),
      subtitle: const Text('구글 이메일로 가입 가능'),
      isActive: _currentStep >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('이 단계에서 할 일'),
          const SizedBox(height: 8),
          _hint(
              '1) 디스코드를 열고 회원가입을 진행하세요.\n2) 마이크 권한 요청이 나오면 허용하세요.\n3) 가입이 끝나면 다시 이 앱으로 돌아오세요.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openDiscordOrStore,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('디스코드 열기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => _currentStep = 2),
            child: const Text('가입했어요 (다음)'),
          ),
        ],
      ),
    );
  }

  Step _joinServerStep() {
    return Step(
      title: const Text('서버 참가'),
      subtitle: const Text('관리자가 준 초대 링크'),
      isActive: _currentStep >= 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('초대 링크 붙여넣기'),
          const SizedBox(height: 8),
          _hint(
              '관리자가 전달한 초대 링크를 복사한 뒤, 아래에서 붙여넣어 주세요.\n예: discord.gg/… 또는 discord.com/invite/…\n\n서버에 들어가면 디스코드 앱에서 음성 채널(무전 채널)을 직접 선택해 입장하면 됩니다.'),
          const SizedBox(height: 10),
          TextField(
            controller: _inviteController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '초대 링크 붙여넣기',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: _inviteController.text.trim().isEmpty
                    ? null
                    : () => _copyInviteLink(_inviteController.text.trim()),
              ),
            ),
            onChanged: (_) async {
              await _save();
              if (mounted) {
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteInviteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('클립보드'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openInvite,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('초대 열기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _hint(
              '서버에 들어갔으면 아래의 “완료”를 눌러 주세요.\n다음부터는 커뮤니티 허브에서 사내 업무 커뮤니티 카드를 누르면 초대 링크가 바로 열립니다.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '디스코드 시작하기',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: _clearSaved,
                  child: const Text('초기화'),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Stepper(
                currentStep: _currentStep,
                onStepTapped: (index) => setState(() => _currentStep = index),
                controlsBuilder: (context, details) {
                  final isLastStep = _currentStep == 2;
                  return Row(
                    children: [
                      if (!isLastStep)
                        FilledButton(
                          onPressed: () => setState(() => _currentStep += 1),
                          child: const Text('다음'),
                        ),
                      if (isLastStep)
                        FilledButton(
                          onPressed: _markDone,
                          child: const Text('완료'),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _currentStep == 0
                            ? null
                            : () => setState(() => _currentStep -= 1),
                        child: const Text('이전'),
                      ),
                    ],
                  );
                },
                steps: [
                  _installStep(),
                  _signupStep(),
                  _joinServerStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
