import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../selector/application/dev_auth.dart';
import '../application/area_chat_read_receipts.dart';
import '../application/chat_account_scope.dart';
import '../application/chat_area_key.dart';
import '../application/chat_area_resolver.dart';
import '../application/chat_failure.dart';
import '../controllers/area_chat_controller.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/chat_pinned_notice.dart';
import 'area_chat_status_dialog.dart';

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

class _AreaChatPanelState extends State<AreaChatPanel>
    with WidgetsBindingObserver {
  late final AreaChatController _controller;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _boundArea = '';
  String _boundChannelId = '';
  String _boundUserId = '';
  String _lastDeveloperErrorSignature = '';
  int _lastLatestSeq = 0;
  int _lastMarkedReadSeq = 0;
  bool _searchVisible = false;
  bool _loadingOlderFromScroll = false;
  bool _isUserScrollActive = false;
  bool _developerMode = false;
  bool _readReceiptReady = false;
  bool _markingRead = false;
  ScrollDirection _userScrollDirection = ScrollDirection.idle;
  int _programmaticScrollDepth = 0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Timer? _readDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AreaChatController();
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_loadDeveloperMode());
  }

  Future<void> _loadDeveloperMode() async {
    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    setState(() {
      _developerMode = enabled;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBindingSoon();
  }

  @override
  void didUpdateWidget(covariant AreaChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaName != widget.areaName) {
      _boundArea = '';
      _boundChannelId = '';
      _boundUserId = '';
      _lastLatestSeq = 0;
      _lastMarkedReadSeq = 0;
      _readReceiptReady = false;
      _closeSearch();
      _syncBindingSoon();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _scheduleMarkVisibleAsRead();
    }
  }

  String _effectiveAreaForBuild(BuildContext context) {
    final explicit = widget.areaName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return ChatAreaResolver.watch(context);
  }

  String _effectiveAreaForRead(BuildContext context) {
    final explicit = widget.areaName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return ChatAreaResolver.read(context);
  }

  void _syncBindingSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final requestedArea = _effectiveAreaForRead(context);
      final session = context.read<UserState>().session;
      final accountScope = ChatAccountScope.fromSession(session);
      final isHeadquarterChannel = isHeadquarterChatAreaName(requestedArea) ||
          accountScope.isHeadquarter &&
              sameChatIdentity(requestedArea, accountScope.division);
      final area = isHeadquarterChannel
          ? headquarterChatAreaName
          : requestedArea.trim();
      final channelId = accountScope.channelIdFor(
        areaName: area,
        isHeadquarterChannel: isHeadquarterChannel,
      );
      final userId = accountScope.userId;

      if (session == null || channelId.isEmpty) {
        if (_boundArea.isNotEmpty ||
            _boundChannelId.isNotEmpty ||
            _boundUserId.isNotEmpty) {
          _boundArea = '';
          _boundChannelId = '';
          _boundUserId = '';
          _lastLatestSeq = 0;
          _lastMarkedReadSeq = 0;
          _readReceiptReady = false;
          _closeSearch();
          unawaited(_controller.stop());
        }
        return;
      }

      if (_boundArea == area &&
          _boundChannelId == channelId &&
          _boundUserId == userId) {
        return;
      }

      _boundArea = area;
      _boundChannelId = channelId;
      _boundUserId = userId;
      _lastLatestSeq = 0;
      _lastMarkedReadSeq = 0;
      _readReceiptReady = false;
      _closeSearch();
      unawaited(_loadInitialReadSeq(channelId, area, userId));
      unawaited(
        _controller.start(
          session: session,
          areaName: area,
          isHeadquarterChannel: isHeadquarterChannel,
        ),
      );
    });
  }

  Future<void> _loadInitialReadSeq(
    String channelId,
    String area,
    String userId,
  ) async {
    var readSeq = 0;
    try {
      readSeq = await AreaChatReadReceipts.readSeq(
        channelId,
        userId: userId,
      );
    } catch (_) {}
    if (!mounted ||
        channelId != _boundChannelId ||
        area != _boundArea ||
        userId != _boundUserId) {
      return;
    }
    if (readSeq > _lastMarkedReadSeq) {
      _lastMarkedReadSeq = readSeq;
    }
    _readReceiptReady = true;
    setState(() {});
    _scheduleMarkVisibleAsRead();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final latestSeq = _controller.latestSeq;
    final initialLoad = _lastLatestSeq == 0 && latestSeq > 0;
    final newMessageArrived = latestSeq > _lastLatestSeq;
    final nearBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            180;

    if (!_searchVisible &&
        (initialLoad || newMessageArrived && nearBottom)) {
      _scrollToBottomSoon();
    } else {
      _scheduleMarkVisibleAsRead();
    }
    _lastLatestSeq = latestSeq;
    _showDeveloperIndexDialogIfNeeded();
    setState(() {});
  }

  Iterable<ChatFailure> get _failures sync* {
    final failures = <ChatFailure?>[
      _controller.primaryFailure,
      _controller.historyFailure,
      _controller.sendFailure,
      _controller.noticeFailure,
      _controller.searchFailure,
      _controller.searchIndexFailure,
    ];
    for (final failure in failures) {
      if (failure != null) yield failure;
    }
  }

  void _showDeveloperIndexDialogIfNeeded() {
    ChatFailure? detectedFailure;
    for (final failure in _failures) {
      if (failure.isIndexRequired) {
        detectedFailure = failure;
        break;
      }
    }
    final indexFailure = detectedFailure;
    if (indexFailure == null) {
      _lastDeveloperErrorSignature = '';
      return;
    }
    if (indexFailure.signature == _lastDeveloperErrorSignature) return;
    _lastDeveloperErrorSignature = indexFailure.signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        AreaChatStatusDialog.showIndexFailure(
          context,
          failure: indexFailure,
          details: <String, Object?>{
            'areaName': _boundArea,
            'channelId': _boundChannelId,
            'userId': _boundUserId,
            'searchQuery': _controller.searchQuery,
            'queryShape': indexFailure.operation ==
                    ChatOperation.searchMessages
                ? 'messages: searchTokens arrayContains + seq descending'
                : indexFailure.operation.name,
          },
        ),
      );
    });
  }

  bool get _isProgrammaticScroll => _programmaticScrollDepth > 0;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _isUserScrollActive = notification.dragDetails != null;
    } else if (notification is UserScrollNotification) {
      _userScrollDirection = notification.direction;
    } else if (notification is ScrollEndNotification) {
      _isUserScrollActive = false;
      _userScrollDirection = ScrollDirection.idle;
      _scheduleMarkVisibleAsRead();
    }
    return false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _isProgrammaticScroll ||
        !_isUserScrollActive ||
        _userScrollDirection != ScrollDirection.forward ||
        _controller.globalSearchActive) {
      return;
    }
    if (_scrollController.position.pixels <= 96) {
      unawaited(_loadOlderPreservingPosition());
    }
  }

  Future<void> _loadOlderPreservingPosition() async {
    if (_loadingOlderFromScroll ||
        _controller.loadingOlder ||
        !_controller.hasMore ||
        _controller.messages.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }

    _loadingOlderFromScroll = true;
    final previousCount = _visibleMessages.length;
    final previousExtent = _scrollController.position.maxScrollExtent;
    final previousPixels = _scrollController.position.pixels;

    await _controller.loadOlderMessages();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _loadingOlderFromScroll = false;
        return;
      }
      final newCount = _visibleMessages.length;
      if (newCount > previousCount) {
        final newExtent = _scrollController.position.maxScrollExtent;
        final target = previousPixels + newExtent - previousExtent;
        final correctedOffset = target
            .clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble();
        _jumpToProgrammatically(correctedOffset);
      }
      _loadingOlderFromScroll = false;
    });
  }

  List<ChatMessage> get _visibleMessages {
    if (_searchVisible && _controller.searchQuery.isNotEmpty) {
      return _controller.searchResults;
    }
    return _controller.messages;
  }

  void _jumpToProgrammatically(double offset) {
    if (!_scrollController.hasClients) return;
    _programmaticScrollDepth += 1;
    try {
      _scrollController.jumpTo(offset);
    } finally {
      _programmaticScrollDepth -= 1;
      _scheduleMarkVisibleAsRead();
    }
  }

  Future<void> _animateToProgrammatically(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (!_scrollController.hasClients) return;
    _programmaticScrollDepth += 1;
    try {
      await _scrollController.animateTo(
        offset,
        duration: duration,
        curve: curve,
      );
    } finally {
      _programmaticScrollDepth -= 1;
      _scheduleMarkVisibleAsRead();
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      unawaited(
        _animateToProgrammatically(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _scrollToTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _jumpToProgrammatically(
        _scrollController.position.minScrollExtent,
      );
    });
  }

  bool get _hasUnseenReadGap {
    final oldestLoadedSeq = _controller.oldestLoadedSeq;
    return _readReceiptReady &&
        _lastMarkedReadSeq > 0 &&
        oldestLoadedSeq > _lastMarkedReadSeq + 1;
  }

  void _scheduleMarkVisibleAsRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_markVisibleAsRead()),
    );
  }

  Future<void> _markVisibleAsRead() async {
    if (!mounted ||
        !_readReceiptReady ||
        _appLifecycleState != AppLifecycleState.resumed ||
        _searchVisible ||
        _controller.historyGapPending ||
        _hasUnseenReadGap ||
        _boundArea.isEmpty ||
        _boundChannelId.isEmpty ||
        _boundUserId.isEmpty ||
        !TickerMode.of(context) ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 8) {
      return;
    }

    final seq = _controller.latestSeq;
    if (_markingRead || seq <= 0 || seq <= _lastMarkedReadSeq) return;
    _markingRead = true;
    try {
      await AreaChatReadReceipts.markRead(
        channelId: _boundChannelId,
        areaName: _boundArea,
        userId: _boundUserId,
        seq: seq,
      );
      _lastMarkedReadSeq = seq;
    } catch (_) {
    } finally {
      _markingRead = false;
    }
  }

  bool get _hasDraft => _textController.text.trim().isNotEmpty;

  Future<bool> _confirmDiscardDraft() async {
    if (!_hasDraft) return true;

    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.edit_note_rounded),
          title: const Text('작성 중인 메시지'),
          content: const Text(
            '작성 중인 메시지가 있습니다. 메시지를 삭제하고 닫으시겠습니까?',
          ),
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

    if (discard != true) return false;
    _textController.clear();
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _requestClose() async {
    final canClose = await _confirmDiscardDraft();
    if (!canClose || !mounted) return;
    final close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    await Navigator.of(context).maybePop();
  }

  bool _isSameDay(DateTime first, DateTime second) {
    final a = first.toLocal();
    final b = second.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _canGroupMessages(ChatMessage first, ChatMessage second) {
    if (first.senderId != second.senderId) return false;
    if (first.seq > 0 && second.seq > 0 && second.seq != first.seq + 1) {
      return false;
    }
    if (!_isSameDay(first.createdAt, second.createdAt)) return false;
    final difference = second.createdAt.difference(first.createdAt).abs();
    return difference <= const Duration(minutes: 5);
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _controller.sending) return;
    final sent = await _controller.sendText(text);
    if (!mounted) return;
    if (sent) {
      _textController.clear();
      setState(() {});
      _scrollToBottomSoon();
      return;
    }
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
    _showFailureSnackBar(
      _controller.sendFailure,
      retryLabel: '다시 전송',
      onRetry: () => unawaited(_send()),
    );
  }

  void _toggleSearch() {
    if (_searchVisible) {
      _closeSearch();
      return;
    }
    setState(() {
      _searchVisible = true;
    });
    _scrollToTopSoon();
  }

  void _closeSearch() {
    _searchController.clear();
    _controller.clearSearch();
    if (mounted) {
      setState(() {
        _searchVisible = false;
      });
      _scrollToBottomSoon();
    } else {
      _searchVisible = false;
    }
  }

  Future<void> _runGlobalSearch() async {
    FocusScope.of(context).unfocus();
    await _controller.searchAllMessages();
    if (!mounted) return;
    _showFailureSnackBar(
      _controller.searchFailure,
      retryLabel: '다시 검색',
      onRetry: () => unawaited(_runGlobalSearch()),
    );
    _scrollToTopSoon();
  }

  Future<void> _retryGlobalSearch() async {
    if (_controller.globalSearchHasCursor) {
      await _loadMoreGlobalSearch();
    } else {
      await _runGlobalSearch();
    }
  }

  Future<void> _loadMoreGlobalSearch() async {
    final canPreserve = _scrollController.hasClients;
    final previousCount = _visibleMessages.length;
    final previousExtent = canPreserve
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final previousPixels = canPreserve
        ? _scrollController.position.pixels
        : 0.0;

    await _controller.loadMoreGlobalSearchResults();
    if (!mounted) return;
    _showFailureSnackBar(
      _controller.searchFailure,
      retryLabel: '다시 시도',
      onRetry: () => unawaited(_loadMoreGlobalSearch()),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !canPreserve ||
          !_scrollController.hasClients ||
          _visibleMessages.length <= previousCount) {
        return;
      }
      final newExtent = _scrollController.position.maxScrollExtent;
      final target = previousPixels + newExtent - previousExtent;
      final correctedOffset = target
          .clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          )
          .toDouble();
      _jumpToProgrammatically(correctedOffset);
    });
  }

  Future<void> _indexNextSearchHistoryBatch() async {
    final completed = await _controller.indexNextSearchHistoryBatch();
    if (!mounted) return;
    if (!completed) {
      _showFailureSnackBar(
        _controller.searchIndexFailure,
        retryLabel: '다시 준비',
        onRetry: () => unawaited(_indexNextSearchHistoryBatch()),
      );
      return;
    }
    final message = _controller.searchIndexHasMore
        ? '이전 메시지를 확인했습니다. 누적 ${_controller.searchIndexUpdatedCount}개를 검색할 수 있습니다.'
        : '현재 채널의 이전 메시지 검색 준비가 완료되었습니다.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showFailureSnackBar(
    ChatFailure? failure, {
    required String retryLabel,
    required VoidCallback onRetry,
  }) {
    if (!mounted || failure == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(failure.userMessage),
        action: failure.retryable
            ? SnackBarAction(
                label: retryLabel,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final isPinned = _controller.pinnedNotice?.messageId == message.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(isPinned ? '공지 고정 해제' : '공지로 고정'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final completed = isPinned
                      ? await _controller.clearPinnedNotice()
                      : await _controller.pinMessage(message);
                  if (!mounted || completed) return;
                  _showFailureSnackBar(
                    _controller.noticeFailure,
                    retryLabel: '다시 시도',
                    onRetry: () {
                      if (isPinned) {
                        unawaited(_controller.clearPinnedNotice());
                      } else {
                        unawaited(_controller.pinMessage(message));
                      }
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPinnedNotice(ChatPinnedNotice notice) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final sender = notice.senderName.trim().isEmpty
            ? '사용자'
            : notice.senderName.trim();
        return AlertDialog(
          icon: Icon(Icons.campaign_rounded, color: cs.primary),
          title: const Text('고정 공지'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (notice.senderIdentity.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(notice.senderIdentity.trim()),
                ],
                const SizedBox(height: 12),
                SelectableText(notice.text),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
            FilledButton.tonalIcon(
              onPressed: _controller.updatingPinnedNotice
                  ? null
                  : () async {
                      Navigator.of(dialogContext).pop();
                      final completed =
                          await _controller.clearPinnedNotice();
                      if (!mounted || completed) return;
                      _showFailureSnackBar(
                        _controller.noticeFailure,
                        retryLabel: '다시 시도',
                        onRetry: () =>
                            unawaited(_controller.clearPinnedNotice()),
                      );
                    },
              icon: const Icon(Icons.push_pin_outlined),
              label: const Text('고정 해제'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedArea = _effectiveAreaForBuild(context);
    final userState = context.watch<UserState>();
    final session = userState.session;
    final accountScope = ChatAccountScope.fromSession(session);
    final isHeadquarterChannel = isHeadquarterChatAreaName(requestedArea) ||
        accountScope.isHeadquarter &&
            sameChatIdentity(requestedArea, accountScope.division);
    final area = isHeadquarterChannel
        ? headquarterChatAreaName
        : requestedArea.trim();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canSend = session != null &&
        _boundChannelId.isNotEmpty &&
        area.isNotEmpty &&
        !_controller.sending &&
        _textController.text.trim().isNotEmpty;
    final keyboardInset = widget.showCloseButton
        ? MediaQuery.of(context).viewInsets.bottom
        : 0.0;
    final title = isHeadquarterChannel
        ? '본사 채팅'
        : area.isEmpty
            ? '지역 채팅'
            : '$area 채팅';
    final subtitle = isHeadquarterChannel ? '본사 공용 채널' : '지역 공용 채널';
    final channelIcon = isHeadquarterChannel
        ? Icons.corporate_fare_rounded
        : Icons.store_mall_directory_rounded;

    return WillPopScope(
      onWillPop: _confirmDiscardDraft,
      child: Material(
        color: cs.surface,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withOpacity(.7),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        channelIcon,
                        size: 21,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (text.titleMedium ?? const TextStyle())
                                .copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (text.labelSmall ?? const TextStyle())
                                .copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_controller.loading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: cs.primary,
                        ),
                      ),
                    IconButton(
                      tooltip: _searchVisible ? '검색 닫기' : '메시지 검색',
                      onPressed: _toggleSearch,
                      icon: Icon(
                        _searchVisible
                            ? Icons.search_off_rounded
                            : Icons.search_rounded,
                      ),
                    ),
                    if (widget.showCloseButton) ...[
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: '닫기',
                        onPressed: () => unawaited(_requestClose()),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ],
                ),
              ),
              if (_searchVisible) _buildSearchBar(context),
              if (_controller.historyRebased) _buildRecoveredBanner(context),
              if (_hasUnseenReadGap && !_controller.historyRebased)
                _buildUnreadHistoryBanner(context),
              if (_controller.primaryFailure != null &&
                  _controller.messages.isNotEmpty)
                _AreaChatFailureBanner(
                  failure: _controller.primaryFailure!,
                  onRetry: _controller.primaryFailure!.retryable
                      ? () => unawaited(_controller.retryInitialLoad())
                      : null,
                ),
              if (_controller.pinnedNotice != null)
                _buildPinnedNoticeBanner(
                  context,
                  _controller.pinnedNotice!,
                ),
              Expanded(
                child: _buildMessageArea(context, area, session?.id ?? ''),
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
              AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: keyboardInset),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Semantics(
                          textField: true,
                          label: '메시지 작성',
                          child: TextField(
                            controller: _textController,
                            enabled: session != null && area.trim().isNotEmpty,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: 4,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        button: true,
                        label: '메시지 전송',
                        enabled: canSend,
                        child: Tooltip(
                          message: '메시지 전송',
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: FilledButton(
                              onPressed:
                                  canSend ? () => unawaited(_send()) : null,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _controller.sending
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasQuery = _controller.searchQuery.isNotEmpty;
    final global = _controller.globalSearchActive;
    final statusText = !hasQuery
        ? '현재 불러온 메시지에서 검색합니다.'
        : global
            ? '전체 메시지 검색 결과 ${_controller.searchResults.length}개'
            : '현재 메시지 검색 결과 ${_controller.localSearchResults.length}개';

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
          Semantics(
            textField: true,
            label: '메시지 검색',
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                _controller.setSearchQuery(value);
                setState(() {});
              },
              onSubmitted: (_) {
                if (hasQuery) unawaited(_runGlobalSearch());
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '검색어 지우기',
                        onPressed: () {
                          _searchController.clear();
                          _controller.clearSearch();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusText,
            style: (text.labelSmall ?? const TextStyle()).copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!global)
                FilledButton.tonalIcon(
                  onPressed: hasQuery && !_controller.searchingAll
                      ? () => unawaited(_runGlobalSearch())
                      : null,
                  icon: _controller.searchingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: const Text('전체 메시지에서 검색'),
                )
              else ...[
                TextButton.icon(
                  onPressed: _controller.useLocalSearch,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('현재 메시지에서 검색'),
                ),
                if (_controller.globalSearchHasMore)
                  FilledButton.tonalIcon(
                    onPressed: _controller.searchingAll
                        ? null
                        : () => unawaited(_loadMoreGlobalSearch()),
                    icon: _controller.searchingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.history_rounded),
                    label: const Text('이전 검색 결과 더 보기'),
                  ),
              ],
              if (_developerMode)
                TextButton.icon(
                  onPressed: _controller.indexingSearchHistory ||
                          !_controller.searchIndexHasMore
                      ? null
                      : () => unawaited(_indexNextSearchHistoryBatch()),
                  icon: _controller.indexingSearchHistory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(
                    _controller.searchIndexHasMore
                        ? '이전 메시지 검색 준비'
                        : '검색 준비 완료',
                  ),
                ),
            ],
          ),
          if (_developerMode && _controller.searchIndexScannedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '확인 ${_controller.searchIndexScannedCount}개 · 반영 ${_controller.searchIndexUpdatedCount}개',
                style: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_controller.searchFailure != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _InlineFailure(
                failure: _controller.searchFailure!,
                onRetry: _controller.searchFailure!.retryable
                    ? () => unawaited(_retryGlobalSearch())
                    : null,
              ),
            ),
          if (_controller.searchIndexFailure != null && _developerMode)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _InlineFailure(
                failure: _controller.searchIndexFailure!,
                onRetry: _controller.searchIndexFailure!.retryable
                    ? () => unawaited(_indexNextSearchHistoryBatch())
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnreadHistoryBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          children: [
            Icon(Icons.mark_chat_unread_rounded,
                color: cs.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '읽지 않은 이전 메시지가 있습니다. 위로 이동해 확인해 주세요.',
                style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveredBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_done_rounded, color: cs.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '연결이 복구되었습니다.',
                style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '안내 닫기',
              onPressed: _controller.dismissHistoryRebasedNotice,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedNoticeBanner(
    BuildContext context,
    ChatPinnedNotice notice,
  ) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sender =
        notice.senderName.trim().isEmpty ? '사용자' : notice.senderName.trim();
    return Material(
      color: cs.tertiaryContainer,
      child: InkWell(
        onTap: () => unawaited(_showPinnedNotice(notice)),
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
                      style: (text.labelMedium ?? const TextStyle()).copyWith(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notice.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (text.bodySmall ?? const TextStyle()).copyWith(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '고정 해제',
                onPressed: _controller.updatingPinnedNotice
                    ? null
                    : () async {
                        final completed =
                            await _controller.clearPinnedNotice();
                        if (!mounted || completed) return;
                        _showFailureSnackBar(
                          _controller.noticeFailure,
                          retryLabel: '다시 시도',
                          onRetry: () =>
                              unawaited(_controller.clearPinnedNotice()),
                        );
                      },
                icon: _controller.updatingPinnedNotice
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.push_pin_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageArea(
    BuildContext context,
    String area,
    String currentUserId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final primaryFailure = _controller.primaryFailure;
    final searching = _searchVisible && _controller.searchQuery.isNotEmpty;
    final messages = searching ? _controller.searchResults : _controller.messages;

    if (area.trim().isEmpty) {
      return const _AreaChatEmptyState(
        icon: Icons.location_off_rounded,
        text: '지역 정보가 없어 채팅을 열 수 없습니다.',
      );
    }

    if (primaryFailure != null && _controller.messages.isEmpty) {
      return _AreaChatEmptyState(
        icon: Icons.error_outline_rounded,
        text: primaryFailure.userMessage,
        actionLabel: primaryFailure.retryable ? '다시 시도' : null,
        onAction: primaryFailure.retryable
            ? () => unawaited(_controller.retryInitialLoad())
            : null,
      );
    }

    if (_controller.loading && _controller.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchVisible && _controller.searchQuery.isEmpty) {
      return const _AreaChatEmptyState(
        icon: Icons.manage_search_rounded,
        text: '검색할 내용을 입력하세요.',
      );
    }

    if (messages.isEmpty) {
      if (searching) {
        final textValue = _controller.globalSearchActive
            ? '전체 메시지에서 일치하는 결과가 없습니다.'
            : '현재 메시지에서 일치하는 결과가 없습니다.';
        return _AreaChatSearchEmptyState(
          icon: Icons.search_off_rounded,
          text: textValue,
          actionLabel: _controller.globalSearchActive
              ? _controller.globalSearchHasMore
                  ? '이전 검색 결과 더 보기'
                  : null
              : _controller.hasMore
                  ? '이전 메시지에서 더 찾기'
                  : null,
          loading: _controller.globalSearchActive
              ? _controller.searchingAll
              : _controller.loadingOlder,
          onAction: _controller.globalSearchActive
              ? _controller.globalSearchHasMore
                  ? () => unawaited(_loadMoreGlobalSearch())
                  : null
              : _controller.hasMore
                  ? () => unawaited(_controller.loadOlderMessages())
                  : null,
        );
      }
      return const _AreaChatEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        text: '아직 채팅 메시지가 없습니다.',
      );
    }

    return Container(
      color: cs.surface,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: messages.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHistoryHeader(context, searching);
            }

            final messageIndex = index - 1;
            final message = messages[messageIndex];
            final previous = messageIndex > 0
                ? messages[messageIndex - 1]
                : null;
            final next = messageIndex + 1 < messages.length
                ? messages[messageIndex + 1]
                : null;
            final isPinned = _controller.pinnedNotice?.messageId == message.id;
            final previousPinned = previous != null &&
                _controller.pinnedNotice?.messageId == previous.id;
            final nextPinned = next != null &&
                _controller.pinnedNotice?.messageId == next.id;
            final startsNewDay = previous == null ||
                !_isSameDay(previous.createdAt, message.createdAt);
            final groupedWithPrevious = previous != null &&
                !startsNewDay &&
                !previousPinned &&
                !isPinned &&
                _canGroupMessages(previous, message);
            final groupedWithNext = next != null &&
                !nextPinned &&
                !isPinned &&
                _canGroupMessages(message, next);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsNewDay)
                  _AreaChatDateSeparator(date: message.createdAt),
                _AreaChatBubble(
                  message: message,
                  isMe: message.senderId == currentUserId,
                  isPinned: isPinned,
                  showSender: !groupedWithPrevious,
                  showTime: !groupedWithNext,
                  groupedWithPrevious: groupedWithPrevious,
                  groupedWithNext: groupedWithNext,
                  textTheme: text,
                  onActions: () => unawaited(_showMessageActions(message)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistoryHeader(BuildContext context, bool searching) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (searching && _controller.globalSearchActive) {
      if (_controller.searchingAll) {
        return const _HistoryProgress();
      }
      if (_controller.searchFailure != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _InlineFailure(
            failure: _controller.searchFailure!,
            onRetry: _controller.searchFailure!.retryable
                ? () => unawaited(_retryGlobalSearch())
                : null,
          ),
        );
      }
      if (_controller.globalSearchHasMore) {
        return Center(
          child: TextButton.icon(
            onPressed: () => unawaited(_loadMoreGlobalSearch()),
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('이전 검색 결과 더 보기'),
          ),
        );
      }
      return _HistoryEndLabel(
        text: '전체 검색 결과를 모두 확인했습니다.',
        textStyle: text.labelSmall,
        color: cs.onSurfaceVariant,
      );
    }

    if (_controller.loadingOlder) {
      return const _HistoryProgress();
    }
    if (_controller.historyFailure != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _InlineFailure(
          failure: _controller.historyFailure!,
          onRetry: _controller.historyFailure!.retryable
              ? () => unawaited(_loadOlderPreservingPosition())
              : null,
        ),
      );
    }
    if (_controller.hasMore) {
      return Center(
        child: TextButton.icon(
          onPressed: () => unawaited(_loadOlderPreservingPosition()),
          icon: const Icon(Icons.history_rounded),
          label: Text(searching ? '이전 메시지에서 더 찾기' : '이전 메시지 불러오기'),
        ),
      );
    }
    return _HistoryEndLabel(
      text: '첫 메시지까지 불러왔습니다.',
      textStyle: text.labelSmall,
      color: cs.onSurfaceVariant,
    );
  }
}

class _AreaChatFailureBanner extends StatelessWidget {
  const _AreaChatFailureBanner({
    required this.failure,
    required this.onRetry,
  });

  final ChatFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failure.userMessage,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({
    required this.failure,
    required this.onRetry,
  });

  final ChatFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            failure.userMessage,
            style: TextStyle(
              color: cs.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: const Text('재시도'),
          ),
      ],
    );
  }
}

class _HistoryProgress extends StatelessWidget {
  const _HistoryProgress();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class _HistoryEndLabel extends StatelessWidget {
  const _HistoryEndLabel({
    required this.text,
    required this.textStyle,
    required this.color,
  });

  final String text;
  final TextStyle? textStyle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          text,
          style: (textStyle ?? const TextStyle()).copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AreaChatEmptyState extends StatelessWidget {
  const _AreaChatEmptyState({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AreaChatSearchEmptyState extends StatelessWidget {
  const _AreaChatSearchEmptyState({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.loading,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final bool loading;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: loading ? null : onAction,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AreaChatDateSeparator extends StatelessWidget {
  const _AreaChatDateSeparator({required this.date});

  final DateTime date;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}년 ${local.month}월 ${local.day}일';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = _formatDate(date);

    return Semantics(
      header: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Divider(color: cs.outlineVariant.withOpacity(.7)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                style: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: cs.outlineVariant.withOpacity(.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaChatBubble extends StatelessWidget {
  const _AreaChatBubble({
    required this.message,
    required this.isMe,
    required this.isPinned,
    required this.showSender,
    required this.showTime,
    required this.groupedWithPrevious,
    required this.groupedWithNext,
    required this.textTheme,
    required this.onActions,
  });

  final ChatMessage message;
  final bool isMe;
  final bool isPinned;
  final bool showSender;
  final bool showTime;
  final bool groupedWithPrevious;
  final bool groupedWithNext;
  final TextTheme textTheme;
  final VoidCallback onActions;

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final period = local.hour < 12 ? '오전' : '오후';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  String _semanticDateTime(DateTime value) {
    final local = value.toLocal();
    final period = local.hour < 12 ? '오전' : '오후';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}월 ${local.day}일 $period $hour시 $minute분';
  }

  BorderRadius _borderRadius() {
    const large = Radius.circular(16);
    const small = Radius.circular(6);

    if (isMe) {
      return BorderRadius.only(
        topLeft: large,
        bottomLeft: large,
        topRight: groupedWithPrevious ? small : large,
        bottomRight: groupedWithNext ? small : large,
      );
    }

    return BorderRadius.only(
      topLeft: groupedWithPrevious ? small : large,
      bottomLeft: groupedWithNext ? small : large,
      topRight: large,
      bottomRight: large,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isMe ? cs.primaryContainer : cs.secondaryContainer;
    final fg = isMe ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final senderName = message.senderName.trim();
    final senderIdentity = message.senderIdentity.trim();
    final sender = senderName.isNotEmpty
        ? senderName
        : senderIdentity.isNotEmpty
            ? senderIdentity
            : '사용자';
    final semanticLabel = [
      sender,
      _semanticDateTime(message.createdAt),
      if (isPinned) '고정 공지',
      message.text,
    ].join(', ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final available = constraints.maxWidth - 42;
        final ratioWidth = constraints.maxWidth * (wide ? .72 : .82);
        final widthLimit = wide ? 520.0 : 420.0;
        final maxBubbleWidth = ratioWidth < widthLimit
            ? ratioWidth
            : widthLimit;
        final constrainedWidth = maxBubbleWidth < available
            ? maxBubbleWidth
            : available;
        final topMargin = groupedWithPrevious ? 1.5 : 6.0;
        final bottomMargin = groupedWithNext ? 1.5 : 6.0;

        final bubble = Semantics(
          container: true,
          label: semanticLabel,
          onLongPress: onActions,
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            const CustomSemanticsAction(label: '메시지 작업 열기'): onActions,
          },
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constrainedWidth),
              child: GestureDetector(
                onLongPress: onActions,
                child: Container(
                  margin: EdgeInsets.only(
                    top: topMargin,
                    bottom: bottomMargin,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: _borderRadius(),
                    border: Border.all(
                      color: isPinned ? cs.tertiary : cs.outlineVariant,
                      width: isPinned ? 1.8 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPinned) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin_rounded,
                              size: 14,
                              color: fg.withOpacity(.85),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '고정 공지',
                              style: (textTheme.labelSmall ?? const TextStyle())
                                  .copyWith(
                                color: fg.withOpacity(.85),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (!isMe && showSender) ...[
                        Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.labelSmall ?? const TextStyle())
                              .copyWith(
                            color: fg.withOpacity(.78),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        message.text,
                        style: (textTheme.bodyMedium ?? const TextStyle())
                            .copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (showTime) ...[
                        const SizedBox(height: 5),
                        Text(
                          _formatTime(message.createdAt),
                          style: (textTheme.labelSmall ?? const TextStyle())
                              .copyWith(
                            color: fg.withOpacity(.70),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final actionButton = Tooltip(
          message: '메시지 작업',
          child: IconButton(
            onPressed: onActions,
            icon: const Icon(Icons.more_horiz_rounded),
            iconSize: 19,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
          ),
        );

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: isMe
                ? <Widget>[actionButton, bubble]
                : <Widget>[bubble, actionButton],
          ),
        );
      },
    );
  }
}
