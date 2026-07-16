import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../account/domain/models/session_account.dart';
import '../application/chat_account_scope.dart';
import '../application/chat_area_key.dart';
import '../application/chat_area_resolver.dart';
import '../controllers/area_chat_controller.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/chat_pinned_notice.dart';

class AreaChatPanel extends StatefulWidget {
  const AreaChatPanel({
    super.key,
    this.areaName,
    this.showCloseButton = false,
    this.onClose,
  });

  final String? areaName;
  final bool showCloseButton;
  final VoidCallback? onClose;

  static Future<void> showSheet({
    required BuildContext context,
    required String areaName,
  }) async {
    final area = areaName.trim();
    if (area.isEmpty) return;

    final media = MediaQuery.of(context);
    final heightFactor = media.size.height < 700 ? 0.94 : 0.90;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.48),
      builder: (sheetContext) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 720
                ? 720.0
                : constraints.maxWidth;
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: maxWidth,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: heightFactor,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: AreaChatPanel(
                      areaName: area,
                      showCloseButton: true,
                      onClose: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<AreaChatPanel> createState() => _AreaChatPanelState();
}

class _AreaChatPanelState extends State<AreaChatPanel> {
  late final AreaChatController _controller;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  String _boundSignature = '';
  String _scheduledSignature = '';
  bool _searchVisible = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _controller = AreaChatController()..addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AreaChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaName != widget.areaName) {
      _boundSignature = '';
      _scheduledSignature = '';
      _closeSearch();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final distance = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final next = distance > 220;
    if (next == _showScrollToBottom || !mounted) return;
    setState(() {
      _showScrollToBottom = next;
    });
  }

  String _effectiveArea(BuildContext context) {
    final explicit = widget.areaName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return ChatAreaResolver.watch(context);
  }

  void _scheduleBinding(SessionAccount? session, String requestedArea) {
    final scope = ChatAccountScope.fromSession(session);
    final isHeadquarterChannel = isHeadquarterChatAreaName(requestedArea) ||
        scope.isHeadquarter &&
            sameChatIdentity(requestedArea, scope.division);
    final area = isHeadquarterChannel
        ? headquarterChatAreaName
        : requestedArea.trim();
    final signature = <String>[
      session?.id.trim() ?? '',
      scope.division,
      scope.selectedArea,
      area,
      isHeadquarterChannel ? '1' : '0',
    ].join('\u0001');

    if (signature == _boundSignature || signature == _scheduledSignature) {
      return;
    }

    _scheduledSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _scheduledSignature != signature) return;
      _scheduledSignature = '';
      _boundSignature = signature;
      _closeSearch();

      if (session == null || area.isEmpty) {
        await _controller.stop();
        return;
      }

      await _controller.start(
        session: session,
        areaName: area,
        isHeadquarterChannel: isHeadquarterChannel,
      );
      _scrollToBottomSoon();
    });
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
    });
    if (!_searchVisible) {
      _searchController.clear();
      _controller.clearSearch();
      return;
    }
  }

  void _closeSearch() {
    _searchVisible = false;
    _searchController.clear();
    _controller.clearSearch();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _controller.sending) return;
    final sent = await _controller.sendText(text);
    if (!mounted || !sent) return;
    _textController.clear();
    _inputFocusNode.requestFocus();
    _scrollToBottomSoon();
  }

  Future<void> _requestClose() async {
    if (_textController.text.trim().isEmpty) {
      _closePanel();
      return;
    }

    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('작성 중인 메시지 삭제'),
          content: const Text('작성 중인 내용이 있습니다. 채팅 화면을 닫을까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('계속 작성'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('삭제하고 닫기'),
            ),
          ],
        );
      },
    );

    if (close == true && mounted) {
      _closePanel();
    }
  }

  void _closePanel() {
    final callback = widget.onClose;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final pinned = _controller.pinnedNotice?.messageId == message.id;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(
                    pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(pinned ? '고정 공지 해제' : '고정 공지로 설정'),
                  subtitle: Text(
                    pinned
                        ? '현재 상단 공지를 해제합니다.'
                        : '이 메시지를 채팅 상단에 표시합니다.',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(
                    pinned ? _MessageAction.unpin : _MessageAction.pin,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('닫기'),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (action == _MessageAction.pin) {
      _controller.pinMessage(message);
    } else if (action == _MessageAction.unpin) {
      _controller.clearPinnedNotice();
    }
  }

  Future<void> _showPinnedNotice(ChatPinnedNotice notice) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final sender = notice.senderName.trim().isEmpty
            ? '사용자'
            : notice.senderName.trim();
        return AlertDialog(
          icon: const Icon(Icons.campaign_rounded),
          title: const Text('고정 공지'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sender,
                style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (notice.senderIdentity.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  notice.senderIdentity,
                  style: Theme.of(dialogContext).textTheme.labelMedium,
                ),
              ],
              const SizedBox(height: 12),
              SelectableText(notice.text),
              const SizedBox(height: 12),
              Text(
                _formatDateTime(notice.pinnedAt),
                style: Theme.of(dialogContext).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _controller.clearPinnedNotice();
              },
              child: const Text('고정 해제'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final session = userState.session;
    final requestedArea = _effectiveArea(context);
    _scheduleBinding(session, requestedArea);

    final isHeadquarter = isHeadquarterChatAreaName(requestedArea) ||
        ChatAccountScope.fromSession(session).isHeadquarter &&
            sameChatIdentity(
              requestedArea,
              ChatAccountScope.fromSession(session).division,
            );
    final displayArea = isHeadquarter
        ? headquarterChatAreaName
        : requestedArea.trim();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context, displayArea, isHeadquarter),
            if (_searchVisible) _buildSearchBar(context),
            _buildFrontendOnlyBanner(context),
            if (_controller.pinnedNotice != null)
              _buildPinnedNoticeBanner(context, _controller.pinnedNotice!),
            Expanded(
              child: Stack(
                children: [
                  _buildMessageBody(context),
                  if (_showScrollToBottom)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: null,
                        tooltip: '최신 메시지로 이동',
                        onPressed: _scrollToBottomSoon,
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                ],
              ),
            ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String areaName,
    bool isHeadquarter,
  ) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title = isHeadquarter ? '본사 채팅' : '$areaName 채팅';
    final subtitle = isHeadquarter ? '본사 공용 채널' : '지역 공용 채널';

    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                isHeadquarter
                    ? Icons.apartment_rounded
                    : Icons.storefront_rounded,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (text.titleMedium ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _searchVisible ? '검색 닫기' : '메시지 검색',
              onPressed: _toggleSearch,
              icon: Icon(
                _searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
              ),
            ),
            if (widget.showCloseButton)
              IconButton(
                tooltip: '채팅 닫기',
                onPressed: _requestClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontendOnlyBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: cs.secondaryContainer.withOpacity(.58),
      child: Row(
        children: [
          Icon(
            Icons.layers_outlined,
            size: 18,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'UI 전용 모드 · 메시지는 현재 앱 실행 중에만 유지됩니다.',
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resultCount = _controller.searchResults.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _controller.setSearchQuery,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: '이름, 직급, 메시지 검색',
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: () {
                        _searchController.clear();
                        _controller.clearSearch();
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _controller.hasSearchQuery
                ? '현재 화면 검색 결과 $resultCount개'
                : '현재 앱 실행 중 작성된 메시지에서 검색합니다.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedNoticeBanner(
    BuildContext context,
    ChatPinnedNotice notice,
  ) {
    final cs = Theme.of(context).colorScheme;
    final sender = notice.senderName.trim().isEmpty
        ? '사용자'
        : notice.senderName.trim();
    return Material(
      color: cs.tertiaryContainer,
      child: InkWell(
        onTap: () => _showPinnedNotice(notice),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: cs.onTertiaryContainer),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '고정 공지 · $sender',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notice.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '고정 해제',
                onPressed: _controller.clearPinnedNotice,
                icon: Icon(
                  Icons.close_rounded,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBody(BuildContext context) {
    if (!_controller.accessAllowed) {
      return _buildStateView(
        context,
        icon: Icons.lock_outline_rounded,
        title: '채팅 화면을 열 수 없습니다.',
        description: '로그인 정보와 현재 지역을 확인해 주세요.',
      );
    }

    final messages = _controller.hasSearchQuery
        ? _controller.searchResults
        : _controller.messages;

    if (messages.isEmpty) {
      return _buildStateView(
        context,
        icon: _controller.hasSearchQuery
            ? Icons.search_off_rounded
            : Icons.forum_outlined,
        title: _controller.hasSearchQuery
            ? '검색 결과가 없습니다.'
            : '아직 작성된 메시지가 없습니다.',
        description: _controller.hasSearchQuery
            ? '다른 검색어를 입력해 주세요.'
            : '하단 입력창에서 첫 메시지를 작성해 보세요.',
      );
    }

    final children = <Widget>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final previous = index > 0 ? messages[index - 1] : null;
      final next = index + 1 < messages.length ? messages[index + 1] : null;
      final startsGroup = previous == null || !_canGroup(previous, message);
      final endsGroup = next == null || !_canGroup(message, next);
      final showDate = previous == null || !_sameDay(previous.createdAt, message.createdAt);

      if (showDate) {
        children.add(_buildDateDivider(context, message.createdAt));
      }

      children.add(
        _MessageBubble(
          message: message,
          isMine: message.senderId == _controller.currentUserId,
          startsGroup: startsGroup,
          endsGroup: endsGroup,
          pinned: _controller.pinnedNotice?.messageId == message.id,
          onActions: () => _showMessageActions(message),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      ),
    );
  }

  Widget _buildStateView(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 34, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateDivider(BuildContext context, DateTime value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _formatDate(value),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant)),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = _controller.accessAllowed;
    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                textField: true,
                label: '채팅 메시지 입력',
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(1000),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: enabled ? '메시지를 입력하세요.' : '채팅 접근 권한이 없습니다.',
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withOpacity(.7),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              enabled: enabled && _textController.text.trim().isNotEmpty,
              label: '메시지 보내기',
              child: IconButton.filled(
                tooltip: '메시지 보내기',
                onPressed: enabled &&
                        !_controller.sending &&
                        _textController.text.trim().isNotEmpty
                    ? _send
                    : null,
                icon: _controller.sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canGroup(ChatMessage first, ChatMessage second) {
    if (first.senderId != second.senderId) return false;
    if (!_sameDay(first.createdAt, second.createdAt)) return false;
    return second.createdAt.difference(first.createdAt).abs() <=
        const Duration(minutes: 5);
  }

  bool _sameDay(DateTime first, DateTime second) {
    final a = first.toLocal();
    final b = second.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) return '오늘';
    if (difference == 1) return '어제';
    return '${local.year}.${_two(local.month)}.${_two(local.day)}';
  }

  static String _formatDateTime(DateTime value) {
    return '${_formatDate(value)} ${_formatTime(value)}';
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final period = local.hour < 12 ? '오전' : '오후';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$period $hour:${_two(local.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _textController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.startsGroup,
    required this.endsGroup,
    required this.pinned,
    required this.onActions,
  });

  final ChatMessage message;
  final bool isMine;
  final bool startsGroup;
  final bool endsGroup;
  final bool pinned;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width >= 600 ? .72 : .82;
    final bubbleColor = isMine ? cs.primaryContainer : cs.secondaryContainer;
    final foreground = isMine ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final radius = _bubbleRadius(isMine, startsGroup, endsGroup);
    final sender = message.senderName.trim().isEmpty
        ? '사용자'
        : message.senderName.trim();

    return Semantics(
      label: '$sender, ${_AreaChatPanelState._formatDateTime(message.createdAt)}, ${message.text}',
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: '메시지 작업 열기'): onActions,
      },
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: maxWidth,
          child: Padding(
            padding: EdgeInsets.only(
              top: startsGroup ? 8 : 2,
              bottom: endsGroup ? 6 : 0,
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (startsGroup)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                    child: Text(
                      message.senderIdentity.trim().isEmpty
                          ? sender
                          : '$sender · ${message.senderIdentity.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                Material(
                  color: bubbleColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: pinned
                        ? BorderSide(color: cs.tertiary, width: 2)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    onLongPress: onActions,
                    borderRadius: radius,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 10, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            message.text,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: foreground,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          if (endsGroup) ...[
                            const SizedBox(height: 5),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pinned) ...[
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 13,
                                    color: foreground.withOpacity(.78),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  _AreaChatPanelState._formatTime(message.createdAt),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: foreground.withOpacity(.72),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  padding: EdgeInsets.zero,
                                  tooltip: '메시지 작업',
                                  onPressed: onActions,
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 18,
                                    color: foreground.withOpacity(.76),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _bubbleRadius(
    bool mine,
    bool starts,
    bool ends,
  ) {
    const large = Radius.circular(18);
    const small = Radius.circular(6);
    if (mine) {
      return BorderRadius.only(
        topLeft: large,
        topRight: starts ? large : small,
        bottomLeft: large,
        bottomRight: ends ? large : small,
      );
    }
    return BorderRadius.only(
      topLeft: starts ? large : small,
      topRight: large,
      bottomLeft: ends ? large : small,
      bottomRight: large,
    );
  }
}

enum _MessageAction {
  pin,
  unpin,
}
