part of 'head_memo.dart';

class _HeadMemoAccentOption {
  const _HeadMemoAccentOption({
    required this.id,
    required this.label,
    required this.color,
    required this.softColor,
  });

  final String id;
  final String label;
  final Color color;
  final Color softColor;
}

const List<_HeadMemoAccentOption> _headMemoAccentOptions = <_HeadMemoAccentOption>[
  _HeadMemoAccentOption(
    id: 'blue',
    label: '파랑',
    color: Color(0xFF2563EB),
    softColor: Color(0xFFDBEAFE),
  ),
  _HeadMemoAccentOption(
    id: 'indigo',
    label: '남색',
    color: Color(0xFF4F46E5),
    softColor: Color(0xFFE0E7FF),
  ),
  _HeadMemoAccentOption(
    id: 'violet',
    label: '보라',
    color: Color(0xFF7C3AED),
    softColor: Color(0xFFEDE9FE),
  ),
  _HeadMemoAccentOption(
    id: 'pink',
    label: '분홍',
    color: Color(0xFFDB2777),
    softColor: Color(0xFFFCE7F3),
  ),
  _HeadMemoAccentOption(
    id: 'red',
    label: '빨강',
    color: Color(0xFFDC2626),
    softColor: Color(0xFFFEE2E2),
  ),
  _HeadMemoAccentOption(
    id: 'orange',
    label: '주황',
    color: Color(0xFFEA580C),
    softColor: Color(0xFFFFEDD5),
  ),
  _HeadMemoAccentOption(
    id: 'amber',
    label: '노랑',
    color: Color(0xFFD97706),
    softColor: Color(0xFFFEF3C7),
  ),
  _HeadMemoAccentOption(
    id: 'green',
    label: '초록',
    color: Color(0xFF16A34A),
    softColor: Color(0xFFDCFCE7),
  ),
  _HeadMemoAccentOption(
    id: 'teal',
    label: '청록',
    color: Color(0xFF0F766E),
    softColor: Color(0xFFCCFBF1),
  ),
  _HeadMemoAccentOption(
    id: 'slate',
    label: '회색',
    color: Color(0xFF475569),
    softColor: Color(0xFFE2E8F0),
  ),
];

_HeadMemoAccentOption _headMemoAccent(String id) {
  for (final option in _headMemoAccentOptions) {
    if (option.id == id) return option;
  }
  return _headMemoAccentOptions.first;
}

class _HeadMemoSideDockDiagnostics {
  static const int _limit = 260;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[HQ_MEMO_DOCK][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[HQ_MEMO_DOCK] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '본사 메모 Side Dock 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

class _HeadMemoSideDock extends StatefulWidget {
  const _HeadMemoSideDock();

  @override
  State<_HeadMemoSideDock> createState() => _HeadMemoSideDockState();
}

class _HeadMemoSideDockState extends State<_HeadMemoSideDock> {
  final TextEditingController _bookNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _todoController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();

  String? _selectedPageId;
  String? _boundBookId;
  String? _boundPageId;
  String _query = '';
  bool _preview = false;
  bool _booksExpanded = false;
  bool _colorExpanded = false;
  bool _fontExpanded = false;
  bool _recipientsExpanded = false;
  bool _developerExpanded = false;
  bool _busy = false;
  bool _sending = false;
  bool _developerMode = false;
  bool _remoteLoading = false;
  List<HeadMemoRemoteBookSummary> _remoteBooks = const <HeadMemoRemoteBookSummary>[];
  String? _inlineError;

  bool get _locked => _busy || _sending || _remoteLoading;

  @override
  void initState() {
    super.initState();
    _HeadMemoSideDockDiagnostics.log(
      'dock_open book=${HeadMemo.book.value.id} pages=${HeadMemo.book.value.pages.length}',
    );
    unawaited(_loadDeveloperMode());
  }

  @override
  void dispose() {
    _bookNameController.dispose();
    _searchController.dispose();
    _headerController.dispose();
    _bodyController.dispose();
    _todoController.dispose();
    _recipientController.dispose();
    _HeadMemoSideDockDiagnostics.log('dock_dispose');
    super.dispose();
  }

  Future<void> _loadDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    setState(() => _developerMode = enabled);
    _HeadMemoSideDockDiagnostics.log('developer_mode=$enabled');
  }

  void _bindControllers(HeadMemoBook book) {
    if (_boundBookId != book.id) {
      _boundBookId = book.id;
      _bookNameController.value = TextEditingValue(
        text: book.name,
        selection: TextSelection.collapsed(offset: book.name.length),
      );
      final hasSelected =
          book.pages.any((page) => page.id == _selectedPageId);
      _selectedPageId = hasSelected
          ? _selectedPageId
          : (book.pages.isEmpty ? null : book.pages.first.id);
      _boundPageId = null;
    }
    final page = _pageById(book, _selectedPageId);
    if (page != null && _boundPageId != page.id) {
      _boundPageId = page.id;
      _headerController.value = TextEditingValue(
        text: page.header,
        selection: TextSelection.collapsed(offset: page.header.length),
      );
      _bodyController.value = TextEditingValue(
        text: page.body,
        selection: TextSelection.collapsed(offset: page.body.length),
      );
      _todoController.clear();
    }
  }

  HeadMemoPage? _pageById(HeadMemoBook book, String? pageId) {
    if (book.pages.isEmpty) return null;
    if (pageId != null) {
      for (final page in book.pages) {
        if (page.id == pageId) return page;
      }
    }
    return book.pages.first;
  }

  int _pageIndex(HeadMemoBook book, String? pageId) {
    final index = book.pages.indexWhere((page) => page.id == pageId);
    return index < 0 ? 0 : index;
  }

  List<HeadMemoPage> _searchResults(HeadMemoBook book) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const <HeadMemoPage>[];
    return book.pages.where((page) {
      if (page.header.toLowerCase().contains(q)) return true;
      if (page.body.toLowerCase().contains(q)) return true;
      return page.todos.any((todo) => todo.text.toLowerCase().contains(q));
    }).toList();
  }

  String _pageTitle(HeadMemoPage page) {
    final header = page.header.trim();
    if (header.isNotEmpty) return header;
    final body = page.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty) return '새 페이지';
    return body.length > 26 ? body.substring(0, 26) : body;
  }

  String _formatUpdated(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (now.year == value.year &&
        now.month == value.month &&
        now.day == value.day) {
      return '${two(value.hour)}:${two(value.minute)} 저장';
    }
    return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _close() async {
    if (_locked) return;
    await HeadMemo.flushPendingSave();
    if (!mounted) return;
    _HeadMemoSideDockDiagnostics.log('dock_close_requested');
    Navigator.of(context).pop();
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    String confirmLabel = '확인',
    bool destructive = false,
  }) async {
    final result = await showCommonOverlayDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            destructive
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(dialogContext).colorScheme.error,
                      foregroundColor:
                          Theme.of(dialogContext).colorScheme.onError,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(confirmLabel),
                  )
                : FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(confirmLabel),
                  ),
          ],
        );
      },
    );
    return result == true;
  }

  void _setInlineError(String? value) {
    if (!mounted) return;
    setState(() => _inlineError = value);
  }

  Future<void> _selectBook(HeadMemoBook value) async {
    if (_locked || value.id == HeadMemo.book.value.id) return;
    await HeadMemo.flushPendingSave();
    await HeadMemo.selectBook(value.id);
    if (!mounted) return;
    setState(() {
      _selectedPageId = HeadMemo.book.value.pages.firstOrNull?.id;
      _boundBookId = null;
      _boundPageId = null;
      _preview = false;
      _query = '';
      _searchController.clear();
      _inlineError = null;
    });
    HapticFeedback.selectionClick();
    _HeadMemoSideDockDiagnostics.log(
      'book_selected id=${value.id} name=${value.name}',
    );
  }

  Future<void> _createBook() async {
    if (_locked) return;
    await HeadMemo.flushPendingSave();
    final created = await HeadMemo.createBook();
    if (!mounted) return;
    setState(() {
      _selectedPageId = created.pages.firstOrNull?.id;
      _boundBookId = null;
      _boundPageId = null;
      _booksExpanded = false;
      _preview = false;
    });
    HapticFeedback.mediumImpact();
    _HeadMemoSideDockDiagnostics.log('book_created id=${created.id}');
  }

  Future<void> _duplicateBook(HeadMemoBook value) async {
    if (_locked) return;
    await HeadMemo.flushPendingSave();
    final copied = await HeadMemo.duplicateBook(value.id);
    if (!mounted || copied == null) return;
    setState(() {
      _selectedPageId = copied.pages.firstOrNull?.id;
      _boundBookId = null;
      _boundPageId = null;
      _preview = false;
    });
    HapticFeedback.mediumImpact();
    _HeadMemoSideDockDiagnostics.log(
      'book_duplicated source=${value.id} target=${copied.id}',
    );
  }

  Future<void> _deleteBook(HeadMemoBook value) async {
    if (_locked || HeadMemo.books.value.length <= 1) return;
    final ok = await _confirm(
      title: '메모북 삭제',
      content: '${value.name} 메모북을 삭제할까요?',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!ok) return;
    final index = HeadMemo.books.value.indexWhere((item) => item.id == value.id);
    final removed = await HeadMemo.deleteBook(value.id);
    if (!mounted || removed == null) return;
    setState(() {
      _selectedPageId = HeadMemo.book.value.pages.firstOrNull?.id;
      _boundBookId = null;
      _boundPageId = null;
      _preview = false;
    });
    HapticFeedback.selectionClick();
    _HeadMemoSideDockDiagnostics.log('book_deleted id=${value.id}');
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('${removed.name} 메모북을 삭제했습니다.'),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            unawaited(HeadMemo.restoreBook(removed, index < 0 ? 0 : index));
          },
        ),
      ),
    );
  }

  Future<void> _selectAccent(String colorId) async {
    if (_locked || HeadMemo.book.value.accentColorId == colorId) return;
    await HeadMemo.updateBookAccentColor(colorId);
    if (!mounted) return;
    setState(() => _inlineError = null);
    HapticFeedback.selectionClick();
    _HeadMemoSideDockDiagnostics.log(
      'accent_selected book=${HeadMemo.book.value.id} color=$colorId',
    );
  }

  Future<void> _selectPage(HeadMemoPage page) async {
    if (_locked || _selectedPageId == page.id) return;
    await HeadMemo.flushPendingSave();
    if (!mounted) return;
    setState(() {
      _selectedPageId = page.id;
      _boundPageId = null;
      _inlineError = null;
    });
    HapticFeedback.selectionClick();
    _HeadMemoSideDockDiagnostics.log('page_selected id=${page.id}');
  }

  Future<void> _addPage() async {
    if (_locked) return;
    await HeadMemo.flushPendingSave();
    await HeadMemo.addPage();
    if (!mounted) return;
    final page = HeadMemo.book.value.pages.last;
    setState(() {
      _selectedPageId = page.id;
      _boundPageId = null;
      _preview = false;
    });
    HapticFeedback.lightImpact();
    _HeadMemoSideDockDiagnostics.log('page_added id=${page.id}');
  }

  Future<void> _duplicatePage(HeadMemoPage page) async {
    if (_locked) return;
    await HeadMemo.flushPendingSave();
    final before = HeadMemo.book.value.pages.length;
    await HeadMemo.duplicatePage(page.id);
    if (!mounted) return;
    final pages = HeadMemo.book.value.pages;
    final sourceIndex = pages.indexWhere((item) => item.id == page.id);
    final target = pages.length > before && sourceIndex >= 0 && sourceIndex + 1 < pages.length
        ? pages[sourceIndex + 1]
        : pages.last;
    setState(() {
      _selectedPageId = target.id;
      _boundPageId = null;
      _preview = false;
    });
    HapticFeedback.lightImpact();
    _HeadMemoSideDockDiagnostics.log(
      'page_duplicated source=${page.id} target=${target.id}',
    );
  }

  Future<void> _deletePage(HeadMemoPage page) async {
    if (_locked || HeadMemo.book.value.pages.length <= 1) return;
    final index = HeadMemo.book.value.pages.indexWhere((item) => item.id == page.id);
    final removed = await HeadMemo.deletePage(page.id);
    if (!mounted || removed == null) return;
    final pages = HeadMemo.book.value.pages;
    final safeIndex = index.clamp(0, pages.length - 1).toInt();
    setState(() {
      _selectedPageId = pages[safeIndex].id;
      _boundPageId = null;
    });
    HapticFeedback.selectionClick();
    _HeadMemoSideDockDiagnostics.log('page_deleted id=${page.id}');
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('${_pageTitle(removed)} 페이지를 삭제했습니다.'),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            unawaited(HeadMemo.restorePage(removed, index < 0 ? 0 : index));
          },
        ),
      ),
    );
  }

  Future<void> _movePage(int delta) async {
    final book = HeadMemo.book.value;
    if (book.pages.isEmpty || _locked) return;
    final current = _pageIndex(book, _selectedPageId);
    final target = (current + delta).clamp(0, book.pages.length - 1).toInt();
    if (target == current) return;
    await _selectPage(book.pages[target]);
  }

  Future<void> _addTodo(HeadMemoPage page) async {
    final value = _todoController.text.trim();
    if (_locked || value.isEmpty) return;
    await HeadMemo.addTodo(page.id, value);
    if (!mounted) return;
    _todoController.clear();
    HapticFeedback.lightImpact();
    _HeadMemoSideDockDiagnostics.log('todo_added page=${page.id}');
  }

  Future<void> _addRecipient() async {
    final value = _recipientController.text.trim().toLowerCase();
    if (_locked || value.isEmpty) return;
    if (!HeadMemo._isValidEmail(value)) {
      _setInlineError('이메일 형식을 확인하세요.');
      return;
    }
    await HeadMemo.addRecipient(value);
    if (!mounted) return;
    _recipientController.clear();
    _setInlineError(null);
    HapticFeedback.lightImpact();
    _HeadMemoSideDockDiagnostics.log('recipient_added email=$value');
  }

  Future<void> _sendBookByEmail() async {
    if (_locked) return;
    final selected = HeadMemo.selectedRecipients();
    if (selected.isEmpty) {
      setState(() {
        _recipientsExpanded = true;
        _inlineError = '전송할 수신자를 선택하세요.';
      });
      return;
    }
    if (GoogleAuthSession.instance.isSessionBlocked) {
      await StatusDialog.showFailure(
        context,
        useCommonUi: true,
        title: '메일 전송 실패',
        description: '구글 세션이 차단되어 전송할 수 없습니다.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _inlineError = null;
    });
    await HeadMemo.flushPendingSave();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '본사 메모 메일 전송',
      initialMessage: 'PDF와 Markdown 생성 준비',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 메일 전송 debugPrint 기록을 표시합니다.',
      standardModeMessage: '개발자 모드 OFF: 일반 메일 전송을 진행합니다.',
    );
    final book = HeadMemo.book.value;
    trace.log(
      'book=${book.id} name=${book.name} pages=${book.pages.length} '
      'recipients=${selected.length} accent=${book.accentColorId}',
      progress: .12,
    );
    try {
      final now = DateTime.now();
      final safe = _memoSafeFileName(book.name);
      final tag = _memoFmtCompact(now);
      final pdfName = '${safe}_$tag.pdf';
      final mdName = '${safe}_$tag.md';
      trace.log('PDF 생성', progress: .26);
      final pdfBytes = await _memoBuildPdfBytes(book, now);
      trace.log('Markdown 생성', progress: .42);
      final markdown = _memoBuildMarkdown(book, now);
      final toCsv = selected.map((item) => item.email).join(', ');
      final subject = '${book.name} 메모 문서 (${_memoFmtYmd(now)})';
      const bodyText =
          '본사 메모 문서를 첨부합니다.\r\n\r\nPDF는 열람과 공유용 문서이며, Markdown은 재편집과 백업용 원본입니다.';
      final mime = _memoBuildMimeMessage(
        toCsv: toCsv,
        subject: subject,
        bodyText: bodyText,
        pdfName: pdfName,
        pdfBytes: pdfBytes,
        markdownName: mdName,
        markdownText: markdown,
        boundary: 'headmemo_${now.microsecondsSinceEpoch}',
      );
      trace.log('Gmail 인증', progress: .62);
      final raw = base64UrlEncode(utf8.encode(mime)).replaceAll('=', '');
      final client = await GmailSenderAuth.client();
      final api = gmail.GmailApi(client);
      trace.log('Gmail API 전송', progress: .82);
      final message = gmail.Message()..raw = raw;
      await api.users.messages.send(message, 'me');
      trace.log('전송 완료 to=$toCsv', progress: .96);
      await trace.succeed('메모북 메일 전송 완료');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (!trace.developerMode) {
        await StatusDialog.showSuccess(
          context,
          useCommonUi: true,
          title: '메일 전송 완료',
          description: '${book.name} 메모북을 ${selected.length}명에게 전송했습니다.',
        );
      }
      _HeadMemoSideDockDiagnostics.log(
        'email_sent book=${book.id} recipients=${selected.length}',
      );
    } catch (error, stackTrace) {
      await HeadMemo._logApiError(
        tag: '_HeadMemoSideDock._sendBookByEmail',
        message: 'Gmail 메모북 전송 실패',
        error: error,
        extra: <String, dynamic>{
          'pages': book.pages.length,
          'recipients': selected.length,
          'accentColorId': book.accentColorId,
        },
        tags: const <String>[
          HeadMemo._tMemo,
          HeadMemo._tMemoEmail,
          HeadMemo._tGmailSend,
        ],
      );
      await trace.fail(
        '메모북 메일 전송 실패',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          useCommonUi: true,
          title: '메일 전송 실패',
          description: '수신자, 구글 세션, 네트워크 상태를 확인하세요.',
        );
      }
      _HeadMemoSideDockDiagnostics.log('email_failure error=$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pushRemote() async {
    if (_locked || !_developerMode) return;
    setState(() => _busy = true);
    await HeadMemo.flushPendingSave();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '본사 메모 ON AIR',
      initialMessage: 'Firestore 업로드 준비',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: Firestore 업로드 로그를 표시합니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    final book = HeadMemo.book.value;
    trace.log(
      'book=${book.id} pages=${book.pages.length} accent=${book.accentColorId}',
      progress: .14,
    );
    try {
      final result = await HeadMemo.pushLibraryToFirestore();
      trace.log(
        'document=${result.documentPath} pages=${result.pageCount} todos=${result.todoCount}',
        progress: .9,
      );
      await trace.succeed('Firestore 업로드 완료');
      _HeadMemoSideDockDiagnostics.log(
        'remote_push_success path=${result.documentPath}',
      );
    } catch (error, stackTrace) {
      await trace.fail(
        'Firestore 업로드 실패',
        error: error,
        stackTrace: stackTrace,
      );
      _HeadMemoSideDockDiagnostics.log('remote_push_failure error=$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullRemote() async {
    if (_locked || !_developerMode) return;
    final ok = await _confirm(
      title: '원격 메모북 내려받기',
      content: '현재 메모북을 Firestore 원격본으로 갱신할까요?',
      confirmLabel: '내려받기',
    );
    if (!ok) return;
    setState(() => _busy = true);
    await HeadMemo.flushPendingSave();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '본사 메모 PULL',
      initialMessage: 'Firestore 내려받기 준비',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: Firestore 내려받기 로그를 표시합니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    try {
      final result = await HeadMemo.pullLibraryFromFirestore();
      trace.log(
        'document=${result.documentPath} book=${result.activeBookName} pages=${result.pageCount}',
        progress: .92,
      );
      await trace.succeed('Firestore 내려받기 완료');
      if (!mounted) return;
      setState(() {
        _boundBookId = null;
        _boundPageId = null;
        _selectedPageId = HeadMemo.book.value.pages.firstOrNull?.id;
      });
      _HeadMemoSideDockDiagnostics.log(
        'remote_pull_success path=${result.documentPath}',
      );
    } catch (error, stackTrace) {
      await trace.fail(
        'Firestore 내려받기 실패',
        error: error,
        stackTrace: stackTrace,
      );
      _HeadMemoSideDockDiagnostics.log('remote_pull_failure error=$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRemoteBooks() async {
    if (_locked || !_developerMode) return;
    setState(() => _remoteLoading = true);
    _HeadMemoSideDockDiagnostics.log('remote_index_load_start');
    try {
      final values = await HeadMemo.fetchRemoteBookIndex();
      if (!mounted) return;
      setState(() => _remoteBooks = values);
      _HeadMemoSideDockDiagnostics.log(
        'remote_index_load_success count=${values.length}',
      );
    } catch (error) {
      _setInlineError('원격 메모북 목록을 불러오지 못했습니다.');
      _HeadMemoSideDockDiagnostics.log('remote_index_load_failure error=$error');
    } finally {
      if (mounted) setState(() => _remoteLoading = false);
    }
  }

  Future<void> _pullRemoteBook(HeadMemoRemoteBookSummary summary) async {
    if (_locked || !_developerMode) return;
    final ok = await _confirm(
      title: '원격 메모북 가져오기',
      content: '${summary.displayName} 메모북을 가져올까요?',
      confirmLabel: '가져오기',
    );
    if (!ok) return;
    setState(() => _busy = true);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '원격 메모북 가져오기',
      initialMessage: '원격 메모북 다운로드 준비',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 원격 메모북 다운로드 로그를 표시합니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    trace.log(
      'remoteBook=${summary.id} name=${summary.displayName} pages=${summary.pageCount}',
      progress: .12,
    );
    try {
      final result = await HeadMemo.pullRemoteBookFromFirestore(summary.id);
      trace.log(
        'document=${result.documentPath} pages=${result.pageCount}',
        progress: .9,
      );
      await trace.succeed('원격 메모북 가져오기 완료');
      if (!mounted) return;
      setState(() {
        _boundBookId = null;
        _boundPageId = null;
        _selectedPageId = HeadMemo.book.value.pages.firstOrNull?.id;
      });
      _HeadMemoSideDockDiagnostics.log(
        'remote_book_pull_success id=${summary.id}',
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '원격 메모북 가져오기 실패',
        error: error,
        stackTrace: stackTrace,
      );
      _HeadMemoSideDockDiagnostics.log(
        'remote_book_pull_failure id=${summary.id} error=$error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HeadMemoBook>>(
      valueListenable: HeadMemo.books,
      builder: (context, _, __) {
        return ValueListenableBuilder<HeadMemoBook>(
          valueListenable: HeadMemo.book,
          builder: (context, book, ___) {
            _bindControllers(book);
            final accent = _headMemoAccent(book.accentColorId);
            final page = _pageById(book, _selectedPageId);
            final pageIndex = page == null ? 0 : _pageIndex(book, page.id);
            return CommonSideDockFrame(
          title: '본사 메모',
          subtitle:
              '${book.name} · ${book.pages.length}쪽 · ${_formatUpdated(book.updatedAt)}',
          icon: Icons.menu_book_rounded,
          onClose: () => unawaited(_close()),
          closeEnabled: !_locked,
          headerAction: _developerMode
              ? IconButton(
                  onPressed: _locked
                      ? null
                      : () => unawaited(
                            _HeadMemoSideDockDiagnostics.showStatus(
                              context,
                              description:
                                  '${book.name} · ${book.pages.length}쪽 · accent=${book.accentColorId}',
                            ),
                          ),
                  icon: const Icon(Icons.bug_report_outlined),
                )
              : null,
          child: AnimatedPadding(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : CommonUiMotion.component,
            curve: CommonUiMotion.enter,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
              children: [
                _buildBookSection(book, accent),
                const SizedBox(height: 12),
                _buildSearchSection(book, accent),
                const SizedBox(height: 12),
                _buildPagesSection(book, page, accent),
                const SizedBox(height: 12),
                if (page != null) _buildEditorSection(book, page, accent),
                if (page != null) ...[
                  const SizedBox(height: 12),
                  _buildTodoSection(page, accent),
                ],
                const SizedBox(height: 12),
                _buildShareSection(book, accent),
                if (_developerMode) ...[
                  const SizedBox(height: 12),
                  _buildDeveloperSection(book, accent),
                ],
                if (_inlineError != null) ...[
                  const SizedBox(height: 12),
                  CommonSideDockReveal(
                    order: 8,
                    child: OpsDockListSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _inlineError!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          footer: OpsDockContextFooterTransition(
            child: OpsDockContextFooter(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '이전',
                    icon: Icons.chevron_left_rounded,
                    variant: CommonButtonVariant.tertiary,
                    minHeight: 42,
                    onPressed: _locked || pageIndex <= 0
                        ? null
                        : () => _movePage(-1),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  child: Text(
                    '${book.pages.isEmpty ? 0 : pageIndex + 1} / ${book.pages.length}',
                    key: ValueKey<String>('${page?.id}_${book.pages.length}'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent.color,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '다음',
                    icon: Icons.chevron_right_rounded,
                    variant: CommonButtonVariant.tertiary,
                    minHeight: 42,
                    onPressed: _locked || pageIndex >= book.pages.length - 1
                        ? null
                        : () => _movePage(1),
                  ),
                ),
                const SizedBox(width: 8),
                CommonButton(
                  label: '추가',
                  icon: Icons.add_rounded,
                  variant: CommonButtonVariant.primary,
                  minHeight: 42,
                  onPressed: _locked ? null : _addPage,
                ),
              ],
            ),
          ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookSection(
    HeadMemoBook book,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockSection(
      title: '메모북',
      subtitle: '${HeadMemo.books.value.length}권',
      accentColor: accent.color,
      order: 0,
      child: OpsDockListSurface(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.softColor,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: accent.color.withOpacity(.28)),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 18,
                      color: accent.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _bookNameController,
                      enabled: !_locked,
                      maxLines: 1,
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        unawaited(HeadMemo.updateBookName(value));
                        _HeadMemoSideDockDiagnostics.log(
                          'book_name_changed length=${value.length}',
                        );
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: _locked
                        ? null
                        : () {
                            setState(() => _booksExpanded = !_booksExpanded);
                            HapticFeedback.selectionClick();
                          },
                    icon: AnimatedRotation(
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.selection,
                      turns: _booksExpanded ? .5 : 0,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                  ),
                ],
              ),
            ),
            _divider(),
            _surfaceActionRow(
              icon: Icons.palette_outlined,
              label: '색상',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _colorDot(accent.color, size: 18),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    turns: _colorExpanded ? .5 : 0,
                    child: const Icon(Icons.expand_more_rounded, size: 19),
                  ),
                ],
              ),
              onTap: _locked
                  ? null
                  : () {
                      setState(() => _colorExpanded = !_colorExpanded);
                      HapticFeedback.selectionClick();
                    },
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              alignment: Alignment.topCenter,
              child: _colorExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                      child: _HeadMemoInlineColorPicker(
                        selectedId: book.accentColorId,
                        enabled: !_locked,
                        onSelected: (value) => unawaited(_selectAccent(value)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            _divider(),
            _surfaceActionRow(
              icon: Icons.format_size_rounded,
              label: '글자 크기',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${book.headerFontSize.round()} / ${book.bodyFontSize.round()}',
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    turns: _fontExpanded ? .5 : 0,
                    child: const Icon(Icons.expand_more_rounded, size: 19),
                  ),
                ],
              ),
              onTap: _locked
                  ? null
                  : () {
                      setState(() => _fontExpanded = !_fontExpanded);
                      HapticFeedback.selectionClick();
                    },
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              alignment: Alignment.topCenter,
              child: _fontExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _HeadMemoFontControls(
                        headerSize: book.headerFontSize,
                        bodySize: book.bodyFontSize,
                        accentColor: accent.color,
                        enabled: !_locked,
                        onChanged: (header, body) {
                          unawaited(
                            HeadMemo.updateFontSizes(
                              headerFontSize: header,
                              bodyFontSize: body,
                            ),
                          );
                          _HeadMemoSideDockDiagnostics.log(
                            'font_changed header=${header.toStringAsFixed(1)} body=${body.toStringAsFixed(1)}',
                          );
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
              curve: CommonUiMotion.enter,
              alignment: Alignment.topCenter,
              child: _booksExpanded
                  ? Column(
                      children: [
                        _divider(),
                        for (final item in HeadMemo.books.value)
                          OpsDockSelectableRowSurface(
                            selected: item.id == book.id,
                            selectionColor: _headMemoAccent(item.accentColorId).color,
                            selectedContainer:
                                _headMemoAccent(item.accentColorId).softColor,
                            onTap: () => unawaited(_selectBook(item)),
                            child: Row(
                              children: [
                                _colorDot(
                                  _headMemoAccent(item.accentColorId).color,
                                  size: 12,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: tokens.textPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${item.pages.length}쪽 · ${_formatUpdated(item.updatedAt)}',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _locked
                                      ? null
                                      : () => unawaited(_duplicateBook(item)),
                                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                                ),
                                IconButton(
                                  onPressed: _locked || HeadMemo.books.value.length <= 1
                                      ? null
                                      : () => unawaited(_deleteBook(item)),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          child: CommonButton(
                            label: '새 메모북',
                            icon: Icons.add_rounded,
                            variant: CommonButtonVariant.secondary,
                            expand: true,
                            minHeight: 42,
                            onPressed: _locked ? null : _createBook,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection(
    HeadMemoBook book,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final results = _searchResults(book);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockSection(
      title: '검색',
      accentColor: accent.color,
      order: 1,
      child: OpsDockListSurface(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 19, color: tokens.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      enabled: !_locked,
                      maxLines: 1,
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        setState(() => _query = value);
                        _HeadMemoSideDockDiagnostics.log(
                          'search_query length=${value.length}',
                        );
                      },
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              alignment: Alignment.topCenter,
              child: _query.trim().isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        _divider(),
                        if (results.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '검색 결과가 없습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          )
                        else
                          for (final page in results.take(8))
                            OpsDockSelectableRowSurface(
                              selected: page.id == _selectedPageId,
                              selectionColor: accent.color,
                              selectedContainer: accent.softColor,
                              onTap: () => unawaited(_selectPage(page)),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.article_outlined,
                                    size: 18,
                                    color: page.id == _selectedPageId
                                        ? accent.color
                                        : tokens.iconSecondary,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _pageTitle(page),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${book.pages.indexOf(page) + 1}p',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagesSection(
    HeadMemoBook book,
    HeadMemoPage? current,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return CommonSideDockSection(
      title: '페이지',
      subtitle: '${book.pages.length}쪽',
      accentColor: accent.color,
      order: 2,
      child: OpsDockListSurface(
        child: Column(
          children: [
            for (var index = 0; index < book.pages.length; index++) ...[
              if (index > 0) _divider(),
              Builder(
                builder: (context) {
                  final page = book.pages[index];
                  final selected = current?.id == page.id;
                  return OpsDockSelectableRowSurface(
                    selected: selected,
                    selectionColor: accent.color,
                    selectedContainer: accent.softColor,
                    onTap: () => unawaited(_selectPage(page)),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? accent.softColor
                                : tokens.surfaceOverlay,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: textTheme.labelMedium?.copyWith(
                              color: selected ? accent.color : tokens.textSecondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pageTitle(page),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${page.body.length}자 · Todo ${page.completedTodoCount}/${page.todos.length}',
                                style: textTheme.labelSmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _locked
                              ? null
                              : () => unawaited(_duplicatePage(page)),
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                        ),
                        IconButton(
                          onPressed: _locked || book.pages.length <= 1
                              ? null
                              : () => unawaited(_deletePage(page)),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditorSection(
    HeadMemoBook book,
    HeadMemoPage page,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockSection(
      title: '현재 페이지',
      subtitle: _preview ? '미리보기' : '편집',
      accentColor: accent.color,
      order: 3,
      child: OpsDockListSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _surfaceActionRow(
              icon: _preview ? Icons.edit_outlined : Icons.visibility_outlined,
              label: _preview ? '편집으로 전환' : '미리보기로 전환',
              trailing: Icon(
                _preview ? Icons.edit_rounded : Icons.visibility_rounded,
                size: 18,
                color: accent.color,
              ),
              onTap: _locked
                  ? null
                  : () {
                      setState(() => _preview = !_preview);
                      HapticFeedback.selectionClick();
                      _HeadMemoSideDockDiagnostics.log('preview=$_preview');
                    },
            ),
            _divider(),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.025, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _preview
                  ? Padding(
                      key: ValueKey<String>('preview_${page.id}'),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _pageTitle(page),
                            style: textTheme.titleLarge?.copyWith(
                              color: tokens.textPrimary,
                              fontSize: book.headerFontSize,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            page.body.trim().isEmpty ? '본문이 비어 있습니다.' : page.body,
                            style: textTheme.bodyMedium?.copyWith(
                              color: page.body.trim().isEmpty
                                  ? tokens.textSecondary
                                  : tokens.textPrimary,
                              fontSize: book.bodyFontSize,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      key: ValueKey<String>('edit_${page.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '페이지 제목',
                                style: textTheme.labelSmall?.copyWith(
                                  color: accent.color,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              TextField(
                                controller: _headerController,
                                enabled: !_locked,
                                maxLines: 2,
                                style: textTheme.titleMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontSize: book.headerFontSize.clamp(18, 30).toDouble(),
                                  fontWeight: FontWeight.w900,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (value) {
                                  unawaited(
                                    HeadMemo.updatePage(page.id, header: value),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        _divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '본문',
                                style: textTheme.labelSmall?.copyWith(
                                  color: accent.color,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _bodyController,
                                enabled: !_locked,
                                minLines: 8,
                                maxLines: 22,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontSize: book.bodyFontSize,
                                  height: 1.55,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (value) {
                                  unawaited(
                                    HeadMemo.updatePage(page.id, body: value),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoSection(
    HeadMemoPage page,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return CommonSideDockSection(
      title: 'Todo',
      subtitle: '${page.completedTodoCount}/${page.todos.length}',
      accentColor: accent.color,
      order: 4,
      child: OpsDockListSurface(
        child: Column(
          children: [
            for (var index = 0; index < page.todos.length; index++) ...[
              if (index > 0) _divider(),
              _HeadMemoTodoRow(
                key: ValueKey<String>(page.todos[index].id),
                todo: page.todos[index],
                accentColor: accent.color,
                enabled: !_locked,
                onDone: (value) {
                  unawaited(
                    HeadMemo.updateTodo(page.id, page.todos[index].id, done: value),
                  );
                  HapticFeedback.selectionClick();
                  _HeadMemoSideDockDiagnostics.log(
                    'todo_done id=${page.todos[index].id} value=$value',
                  );
                },
                onText: (value) {
                  unawaited(
                    HeadMemo.updateTodo(page.id, page.todos[index].id, text: value),
                  );
                },
                onDelete: () {
                  unawaited(
                    HeadMemo.deleteTodo(page.id, page.todos[index].id),
                  );
                  HapticFeedback.selectionClick();
                  _HeadMemoSideDockDiagnostics.log(
                    'todo_deleted id=${page.todos[index].id}',
                  );
                },
              ),
            ],
            if (page.todos.isNotEmpty) _divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.add_task_rounded, size: 19, color: accent.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _todoController,
                      enabled: !_locked,
                      textInputAction: TextInputAction.done,
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => unawaited(_addTodo(page)),
                    ),
                  ),
                  IconButton(
                    onPressed: _locked ? null : () => unawaited(_addTodo(page)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareSection(
    HeadMemoBook book,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockSection(
      title: '공유',
      subtitle: '${HeadMemo.selectedRecipients().length}명 선택',
      accentColor: accent.color,
      order: 5,
      child: ValueListenableBuilder<List<HeadMemoRecipient>>(
        valueListenable: HeadMemo.recipients,
        builder: (context, recipients, _) {
          return OpsDockListSurface(
            child: Column(
              children: [
                _surfaceActionRow(
                  icon: Icons.people_alt_outlined,
                  label: '수신자',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${recipients.where((item) => item.selected).length}명',
                        style: textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        duration:
                            reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        turns: _recipientsExpanded ? .5 : 0,
                        child: const Icon(Icons.expand_more_rounded, size: 19),
                      ),
                    ],
                  ),
                  onTap: _locked
                      ? null
                      : () {
                          setState(
                            () => _recipientsExpanded = !_recipientsExpanded,
                          );
                          HapticFeedback.selectionClick();
                        },
                ),
                AnimatedSize(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  curve: CommonUiMotion.enter,
                  alignment: Alignment.topCenter,
                  child: _recipientsExpanded
                      ? Column(
                          children: [
                            _divider(),
                            if (recipients.isNotEmpty)
                              _surfaceActionRow(
                                icon: Icons.done_all_rounded,
                                label: recipients.every((item) => item.selected)
                                    ? '전체 선택 해제'
                                    : '전체 선택',
                                trailing: const SizedBox.shrink(),
                                onTap: _locked
                                    ? null
                                    : () => unawaited(
                                          HeadMemo.selectAllRecipients(
                                            !recipients.every(
                                              (item) => item.selected,
                                            ),
                                          ),
                                        ),
                              ),
                            for (final recipient in recipients) ...[
                              if (recipients.isNotEmpty) _divider(),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                                child: Row(
                                  children: [
                                    Switch(
                                      value: recipient.selected,
                                      onChanged: _locked
                                          ? null
                                          : (value) => unawaited(
                                                HeadMemo.updateRecipientSelected(
                                                  recipient.id,
                                                  value,
                                                ),
                                              ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            recipient.label,
                                            style: textTheme.bodyMedium?.copyWith(
                                              color: tokens.textPrimary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            recipient.email,
                                            style: textTheme.labelSmall?.copyWith(
                                              color: tokens.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _locked
                                          ? null
                                          : () => unawaited(
                                                HeadMemo.deleteRecipient(
                                                  recipient.id,
                                                ),
                                              ),
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (recipients.isNotEmpty) _divider(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.alternate_email_rounded,
                                    size: 19,
                                    color: accent.color,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _recipientController,
                                      enabled: !_locked,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.done,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: tokens.textPrimary,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        filled: false,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onSubmitted: (_) => unawaited(_addRecipient()),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _locked ? null : () => unawaited(_addRecipient()),
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                _divider(),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: CommonButton(
                    label: 'PDF + Markdown 전송',
                    icon: Icons.send_rounded,
                    expand: true,
                    loading: _sending,
                    minHeight: 46,
                    onPressed: _locked ? null : _sendBookByEmail,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeveloperSection(
    HeadMemoBook book,
    _HeadMemoAccentOption accent,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockSection(
      title: '개발자',
      subtitle: 'Firestore',
      accentColor: accent.color,
      order: 6,
      child: OpsDockListSurface(
        child: Column(
          children: [
            _surfaceActionRow(
              icon: Icons.cloud_upload_outlined,
              label: 'ON AIR',
              trailing: Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
              onTap: _locked ? null : () => unawaited(_pushRemote()),
            ),
            _divider(),
            _surfaceActionRow(
              icon: Icons.cloud_download_outlined,
              label: 'PULL',
              trailing: Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
              onTap: _locked ? null : () => unawaited(_pullRemote()),
            ),
            _divider(),
            _surfaceActionRow(
              icon: Icons.cloud_queue_rounded,
              label: 'REMOTE',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_remoteLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    turns: _developerExpanded ? .5 : 0,
                    child: const Icon(Icons.expand_more_rounded, size: 19),
                  ),
                ],
              ),
              onTap: _locked
                  ? null
                  : () async {
                      setState(() => _developerExpanded = !_developerExpanded);
                      HapticFeedback.selectionClick();
                      if (_developerExpanded && _remoteBooks.isEmpty) {
                        await _loadRemoteBooks();
                      }
                    },
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
              curve: CommonUiMotion.enter,
              alignment: Alignment.topCenter,
              child: _developerExpanded
                  ? Column(
                      children: [
                        _divider(),
                        if (_remoteBooks.isEmpty && !_remoteLoading)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '원격 메모북이 없습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          )
                        else
                          for (final remote in _remoteBooks)
                            OpsDockSelectableRowSurface(
                              selected: remote.id == book.id,
                              selectionColor: accent.color,
                              selectedContainer: accent.softColor,
                              onTap: () => unawaited(_pullRemoteBook(remote)),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.menu_book_outlined,
                                    size: 18,
                                    color: remote.id == book.id
                                        ? accent.color
                                        : tokens.iconSecondary,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          remote.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.bodyMedium?.copyWith(
                                            color: tokens.textPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${remote.pageCount}쪽 · Todo ${remote.completedTodoCount}/${remote.todoCount}',
                                          style: textTheme.labelSmall?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.download_rounded, size: 18),
                                ],
                              ),
                            ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                          child: CommonButton(
                            label: '목록 새로고침',
                            icon: Icons.refresh_rounded,
                            variant: CommonButtonVariant.tertiary,
                            expand: true,
                            minHeight: 40,
                            loading: _remoteLoading,
                            onPressed: _locked ? null : _loadRemoteBooks,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            _divider(),
            _surfaceActionRow(
              icon: Icons.bug_report_outlined,
              label: 'Status Dialog',
              trailing: const Icon(Icons.content_copy_rounded, size: 18),
              onTap: _locked
                  ? null
                  : () => unawaited(
                        _HeadMemoSideDockDiagnostics.showStatus(
                          context,
                          description:
                              '${book.name} · ${book.pages.length}쪽 · ${HeadMemo.remoteLibraryPath}',
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _surfaceActionRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    final tokens = CommonUiTheme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 19, color: tokens.iconSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onTap == null
                        ? tokens.textDisabled
                        : tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          trailing,
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: CommonUiTheme.of(context).borderSubtle,
    );
  }

  Widget _colorDot(Color color, {double size = 16}) {
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.selection,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(.34), width: 2),
      ),
    );
  }
}

extension _HeadMemoFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _HeadMemoInlineColorPicker extends StatelessWidget {
  const _HeadMemoInlineColorPicker({
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final String selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final option in _headMemoAccentOptions)
          Semantics(
            selected: option.id == selectedId,
            button: true,
            label: '메모북 색상 ${option.label}',
            child: GestureDetector(
              onTap: enabled ? () => onSelected(option.id) : null,
              child: AnimatedScale(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                scale: option.id == selectedId ? 1.08 : 1,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: option.id == selectedId
                          ? Theme.of(context).colorScheme.onSurface
                          : option.color.withOpacity(.35),
                      width: option.id == selectedId ? 2.5 : 1.5,
                    ),
                    boxShadow: option.id == selectedId
                        ? [
                            BoxShadow(
                              color: option.color.withOpacity(.24),
                              blurRadius: 9,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: option.id == selectedId
                        ? Icon(
                            Icons.check_rounded,
                            key: ValueKey<String>('check_${option.id}'),
                            size: 18,
                            color: Colors.white,
                          )
                        : SizedBox(
                            key: ValueKey<String>('empty_${option.id}'),
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeadMemoFontControls extends StatefulWidget {
  const _HeadMemoFontControls({
    required this.headerSize,
    required this.bodySize,
    required this.accentColor,
    required this.enabled,
    required this.onChanged,
  });

  final double headerSize;
  final double bodySize;
  final Color accentColor;
  final bool enabled;
  final void Function(double header, double body) onChanged;

  @override
  State<_HeadMemoFontControls> createState() => _HeadMemoFontControlsState();
}

class _HeadMemoFontControlsState extends State<_HeadMemoFontControls> {
  late double _header;
  late double _body;

  @override
  void initState() {
    super.initState();
    _header = widget.headerSize;
    _body = widget.bodySize;
  }

  @override
  void didUpdateWidget(covariant _HeadMemoFontControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headerSize != widget.headerSize) _header = widget.headerSize;
    if (oldWidget.bodySize != widget.bodySize) _body = widget.bodySize;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                '헤더',
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _header,
                min: 18,
                max: 38,
                divisions: 20,
                activeColor: widget.accentColor,
                onChanged: widget.enabled
                    ? (value) {
                        setState(() => _header = value);
                        widget.onChanged(_header, _body);
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${_header.round()}',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                '본문',
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _body,
                min: 12,
                max: 24,
                divisions: 12,
                activeColor: widget.accentColor,
                onChanged: widget.enabled
                    ? (value) {
                        setState(() => _body = value);
                        widget.onChanged(_header, _body);
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${_body.round()}',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeadMemoTodoRow extends StatefulWidget {
  const _HeadMemoTodoRow({
    super.key,
    required this.todo,
    required this.accentColor,
    required this.enabled,
    required this.onDone,
    required this.onText,
    required this.onDelete,
  });

  final HeadMemoTodo todo;
  final Color accentColor;
  final bool enabled;
  final ValueChanged<bool> onDone;
  final ValueChanged<String> onText;
  final VoidCallback onDelete;

  @override
  State<_HeadMemoTodoRow> createState() => _HeadMemoTodoRowState();
}

class _HeadMemoTodoRowState extends State<_HeadMemoTodoRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.todo.text);
  }

  @override
  void didUpdateWidget(covariant _HeadMemoTodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todo.id != widget.todo.id ||
        oldWidget.todo.text != widget.todo.text &&
            _controller.text != widget.todo.text) {
      _controller.value = TextEditingValue(
        text: widget.todo.text,
        selection: TextSelection.collapsed(offset: widget.todo.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.enabled
                ? () => widget.onDone(!widget.todo.done)
                : null,
            icon: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Icon(
                widget.todo.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey<bool>(widget.todo.done),
                color: widget.todo.done
                    ? widget.accentColor
                    : tokens.iconSecondary,
              ),
            ),
          ),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              style: textTheme.bodyMedium?.copyWith(
                    color: widget.todo.done
                        ? tokens.textSecondary
                        : tokens.textPrimary,
                    decoration:
                        widget.todo.done ? TextDecoration.lineThrough : null,
                  ) ??
                  TextStyle(
                    color: widget.todo.done
                        ? tokens.textSecondary
                        : tokens.textPrimary,
                    decoration:
                        widget.todo.done ? TextDecoration.lineThrough : null,
                  ),
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                maxLines: 2,
                style: TextStyle(
                  color: widget.todo.done
                      ? tokens.textSecondary
                      : tokens.textPrimary,
                  decoration:
                      widget.todo.done ? TextDecoration.lineThrough : null,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onText,
              ),
            ),
          ),
          IconButton(
            onPressed: widget.enabled ? widget.onDelete : null,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

const int _memoMimeB64LineLength = 76;

String _memoFmt2(int value) => value.toString().padLeft(2, '0');

String _memoFmtYmd(DateTime value) {
  return '${value.year}-${_memoFmt2(value.month)}-${_memoFmt2(value.day)}';
}

String _memoFmtCompact(DateTime value) {
  return '${value.year}${_memoFmt2(value.month)}${_memoFmt2(value.day)}_'
      '${_memoFmt2(value.hour)}${_memoFmt2(value.minute)}${_memoFmt2(value.second)}';
}

String _memoWrapBase64Lines(
  String value, {
  int lineLength = _memoMimeB64LineLength,
}) {
  if (value.isEmpty) return '';
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index += lineLength) {
    final end = index + lineLength < value.length
        ? index + lineLength
        : value.length;
    buffer.write(value.substring(index, end));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _memoEncodeSubject(String subject) {
  final encoded = base64.encode(utf8.encode(subject));
  return '=?UTF-8?B?$encoded?=';
}

String _memoSafeFileName(String raw) {
  final normalized = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return normalized.isEmpty ? 'head_memo' : normalized;
}

String _memoBuildMimeMessage({
  required String toCsv,
  required String subject,
  required String bodyText,
  required String pdfName,
  required Uint8List pdfBytes,
  required String markdownName,
  required String markdownText,
  required String boundary,
}) {
  const crlf = '\r\n';
  final pdfB64 = _memoWrapBase64Lines(base64.encode(pdfBytes));
  final mdB64 = _memoWrapBase64Lines(base64.encode(utf8.encode(markdownText)));
  final bodyB64 = _memoWrapBase64Lines(base64.encode(utf8.encode(bodyText)));
  final mime = StringBuffer()
    ..write('MIME-Version: 1.0$crlf')
    ..write('To: $toCsv$crlf')
    ..write('Subject: ${_memoEncodeSubject(subject)}$crlf')
    ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
    ..write(crlf)
    ..write('--$boundary$crlf')
    ..write('Content-Type: text/plain; charset="utf-8"$crlf')
    ..write('Content-Transfer-Encoding: base64$crlf')
    ..write(crlf)
    ..write(bodyB64)
    ..write(crlf)
    ..write('--$boundary$crlf')
    ..write('Content-Type: application/pdf; name="$pdfName"$crlf')
    ..write('Content-Disposition: attachment; filename="$pdfName"$crlf')
    ..write('Content-Transfer-Encoding: base64$crlf')
    ..write(crlf)
    ..write(pdfB64)
    ..write(crlf)
    ..write('--$boundary$crlf')
    ..write('Content-Type: text/markdown; charset="utf-8"; name="$markdownName"$crlf')
    ..write('Content-Disposition: attachment; filename="$markdownName"$crlf')
    ..write('Content-Transfer-Encoding: base64$crlf')
    ..write(crlf)
    ..write(mdB64)
    ..write(crlf)
    ..write('--$boundary--$crlf');
  return mime.toString();
}

String _memoPageTitle(HeadMemoPage page) {
  final header = page.header.trim();
  if (header.isNotEmpty) return header;
  final body = page.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (body.isEmpty) return '새 페이지';
  return body.length > 30 ? body.substring(0, 30) : body;
}

Future<Uint8List> _memoBuildPdfBytes(
  HeadMemoBook book,
  DateTime exportedAt,
) async {
  pw.Font? regular;
  pw.Font? bold;
  try {
    final data =
        await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
    regular = pw.Font.ttf(data);
  } catch (_) {}
  try {
    final data =
        await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
    bold = pw.Font.ttf(data);
  } catch (_) {
    bold = regular;
  }
  final theme = regular == null
      ? pw.ThemeData.base()
      : pw.ThemeData.withFont(
          base: regular,
          bold: bold ?? regular,
          italic: regular,
          boldItalic: bold ?? regular,
        );
  final option = _headMemoAccent(book.accentColorId);
  final accent = PdfColor.fromInt(option.color.value);
  final accentSoft = PdfColor.fromInt(option.softColor.value);
  const ink = PdfColor.fromInt(0xff111827);
  const muted = PdfColor.fromInt(0xff6b7280);
  const line = PdfColor.fromInt(0xffd1d5db);
  const soft = PdfColor.fromInt(0xfff3f4f6);
  final doc = pw.Document();

  pw.TextStyle titleStyle(double size) => pw.TextStyle(
        fontSize: size,
        color: ink,
        fontWeight: pw.FontWeight.bold,
      );
  pw.TextStyle bodyStyle(double size, {PdfColor color = ink}) => pw.TextStyle(
        fontSize: size,
        color: color,
        height: 1.45,
      );
  pw.Widget footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: line, width: .6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(book.name, style: bodyStyle(8, color: muted)),
          pw.Text(
            '${HeadMemo._fmtDateTime(exportedAt)} · ${context.pageNumber} / ${context.pagesCount}',
            style: bodyStyle(8, color: muted),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
      build: (context) {
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(34),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(18),
            border: pw.Border.all(color: line, width: .8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: accentSoft,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
                child: pw.Text(
                  'HEAD MEMO BOOK',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: accent,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              pw.SizedBox(height: 38),
              pw.Text(book.name, style: titleStyle(34)),
              pw.SizedBox(height: 16),
              pw.Text(
                '본사 메모 문서',
                style: bodyStyle(12, color: muted),
              ),
              pw.SizedBox(height: 32),
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: soft,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '본문 페이지 ${book.pages.length}',
                      style: titleStyle(10),
                    ),
                    pw.Text(
                      HeadMemo._fmtDateTime(book.updatedAt),
                      style: bodyStyle(9, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('목차', style: titleStyle(24)),
            pw.SizedBox(height: 16),
            for (var index = 0; index < book.pages.length; index++)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(11),
                decoration: pw.BoxDecoration(
                  color: soft,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 30,
                      height: 24,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: accentSoft,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Text(
                        '${index + 1}',
                        style: pw.TextStyle(
                          color: accent,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Text(
                        _memoPageTitle(book.pages[index]),
                        style: titleStyle(11),
                      ),
                    ),
                  ],
                ),
              ),
            pw.Spacer(),
            footer(context),
          ],
        );
      },
    ),
  );

  for (var index = 0; index < book.pages.length; index++) {
    final page = book.pages[index];
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        footer: footer,
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: line, width: .8),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      _memoPageTitle(page),
                      style: titleStyle(book.headerFontSize),
                    ),
                  ),
                  pw.Text(
                    '${index + 1}p',
                    style: bodyStyle(9, color: muted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              page.body.trim().isEmpty ? '본문이 비어 있습니다.' : page.body.trim(),
              style: bodyStyle(book.bodyFontSize),
            ),
            if (page.todos.isNotEmpty) ...[
              pw.SizedBox(height: 22),
              pw.Container(height: .8, color: line),
              pw.SizedBox(height: 12),
              pw.Text('Todo', style: titleStyle(13)),
              pw.SizedBox(height: 8),
              for (final todo in page.todos)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 5),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        todo.done ? '☑' : '☐',
                        style: bodyStyle(
                          11,
                          color: todo.done ? accent : muted,
                        ),
                      ),
                      pw.SizedBox(width: 7),
                      pw.Expanded(
                        child: pw.Text(
                          todo.text,
                          style: bodyStyle(
                            10,
                            color: todo.done ? muted : ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ];
        },
      ),
    );
  }
  return doc.save();
}

String _memoBuildMarkdown(HeadMemoBook book, DateTime exportedAt) {
  final buffer = StringBuffer();
  buffer.writeln('# ${book.name}');
  buffer.writeln();
  buffer.writeln('- 생성: ${HeadMemo._fmtDateTime(book.createdAt)}');
  buffer.writeln('- 수정: ${HeadMemo._fmtDateTime(book.updatedAt)}');
  buffer.writeln('- 내보내기: ${HeadMemo._fmtDateTime(exportedAt)}');
  buffer.writeln('- Accent: ${book.accentColorId}');
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();
  buffer.writeln('## 목차');
  buffer.writeln();
  for (var index = 0; index < book.pages.length; index++) {
    buffer.writeln('${index + 1}. ${_memoPageTitle(book.pages[index])}');
  }
  for (final page in book.pages) {
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('## ${_memoPageTitle(page)}');
    buffer.writeln();
    buffer.writeln(
      page.body.trim().isEmpty ? '_본문이 비어 있습니다._' : page.body.trim(),
    );
    if (page.todos.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('### Todo');
      buffer.writeln();
      for (final todo in page.todos) {
        buffer.writeln('- [${todo.done ? 'x' : ' '}] ${todo.text}');
      }
    }
  }
  buffer.writeln();
  return buffer.toString();
}
