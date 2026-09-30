import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/gmail_sender_auth.dart';
import '../../../app/auth/google_auth_session.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../selector/application/dev_auth.dart';
import '../data/novel_cloud_backup_store.dart';

class NovelMobileWritingPage extends StatefulWidget {
  const NovelMobileWritingPage({super.key});

  @override
  State<NovelMobileWritingPage> createState() => _NovelMobileWritingPageState();
}

class _NovelMobileWritingPageState extends State<NovelMobileWritingPage> {
  _Project _project = _Project.seed();
  _NovelTab _tab = _NovelTab.chapters;
  int _chapterIndex = 0;
  int _characterIndex = 0;
  int _termIndex = 0;
  bool _checking = true;
  bool _authorized = false;
  bool _editMode = false;
  bool _focusMode = false;
  bool _saving = false;
  bool _busy = false;
  Timer? _saveTimer;
  Timer? _feedbackTimer;
  DeveloperOperationTrace? _trace;
  _NotenFeedback? _feedback;
  bool _exitDialogOpen = false;
  int _feedbackSerial = 0;
  final NovelCloudBackupStore _cloudBackupStore = NovelCloudBackupStore();
  NovelCloudBackupMetadata? _cloudBackupMetadata;
  _CloudOperation _cloudOperation = _CloudOperation.idle;
  bool _cloudFailed = false;

  final _titleCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _loglineCtrl = TextEditingController();
  final _chapterTitleCtrl = TextEditingController();
  final _chapterBodyCtrl = TextEditingController();
  final _chapterNoteCtrl = TextEditingController();
  final _chapterTargetCtrl = TextEditingController();
  final _themeCtrl = TextEditingController();
  final _synopsisCtrl = TextEditingController();
  final _worldCtrl = TextEditingController();
  final _beginningCtrl = TextEditingController();
  final _developmentCtrl = TextEditingController();
  final _crisisCtrl = TextEditingController();
  final _climaxCtrl = TextEditingController();
  final _endingCtrl = TextEditingController();
  final _foreshadowCtrl = TextEditingController();
  final _designMemoCtrl = TextEditingController();
  final _charNameCtrl = TextEditingController();
  final _charRoleCtrl = TextEditingController();
  final _charAliasCtrl = TextEditingController();
  final _charAgeCtrl = TextEditingController();
  final _charGenderCtrl = TextEditingController();
  final _charJobCtrl = TextEditingController();
  final _charLookCtrl = TextEditingController();
  final _charPersonalityCtrl = TextEditingController();
  final _charSpeechCtrl = TextEditingController();
  final _charDesireCtrl = TextEditingController();
  final _charWeaknessCtrl = TextEditingController();
  final _charSecretCtrl = TextEditingController();
  final _charArcCtrl = TextEditingController();
  final _charRelationCtrl = TextEditingController();
  final _termNameCtrl = TextEditingController();
  final _termAliasCtrl = TextEditingController();
  final _termCategoryCtrl = TextEditingController();
  final _termShortCtrl = TextEditingController();
  final _termDefinitionCtrl = TextEditingController();
  final _termUsageCtrl = TextEditingController();
  final _termRelatedCtrl = TextEditingController();
  final _termMemoCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _feedbackTimer?.cancel();
    for (final c in [
      _titleCtrl,
      _genreCtrl,
      _loglineCtrl,
      _chapterTitleCtrl,
      _chapterBodyCtrl,
      _chapterNoteCtrl,
      _chapterTargetCtrl,
      _themeCtrl,
      _synopsisCtrl,
      _worldCtrl,
      _beginningCtrl,
      _developmentCtrl,
      _crisisCtrl,
      _climaxCtrl,
      _endingCtrl,
      _foreshadowCtrl,
      _designMemoCtrl,
      _charNameCtrl,
      _charRoleCtrl,
      _charAliasCtrl,
      _charAgeCtrl,
      _charGenderCtrl,
      _charJobCtrl,
      _charLookCtrl,
      _charPersonalityCtrl,
      _charSpeechCtrl,
      _charDesireCtrl,
      _charWeaknessCtrl,
      _charSecretCtrl,
      _charArcCtrl,
      _charRelationCtrl,
      _termNameCtrl,
      _termAliasCtrl,
      _termCategoryCtrl,
      _termShortCtrl,
      _termDefinitionCtrl,
      _termUsageCtrl,
      _termRelatedCtrl,
      _termMemoCtrl,
      _recipientCtrl,
    ]) {
      c.dispose();
    }
    _bodyFocus.dispose();
    _trace?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await DevAuth.isDeveloperLoggedIn();
    final loaded = await _LocalStore.load();
    final cloudMetadata = await _cloudBackupStore.localMetadata(loaded.id);
    if (!mounted) return;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: 'notensystem',
      initialMessage: 'screen_init authorized=$ok',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: notensystem 진단 로그를 기록합니다.',
      standardModeMessage: '개발자 모드 OFF: notensystem 접근이 제한됩니다.',
      showDialogImmediately: false,
    );
    if (!mounted) {
      trace.dispose();
      return;
    }
    setState(() {
      _trace = trace;
      _authorized = ok;
      _project = loaded;
      _cloudBackupMetadata = cloudMetadata;
      _checking = false;
      _chapterIndex = _safeIndex(
        _project.chapters.indexWhere((e) => e.id == _project.activeChapterId),
        _project.chapters.length,
      );
      _characterIndex = _project.characters.isEmpty ? -1 : 0;
      _termIndex = _project.terms.isEmpty ? -1 : 0;
    });
    _loadAllControllers();
    _log(
      'screen_ready project=${_project.id} chapters=${_project.chapters.length} characters=${_project.characters.length} terms=${_project.terms.length} cloudMetadata=${cloudMetadata != null}',
      progress: .08,
    );
  }

  void _log(String message, {double? progress}) {
    _trace?.log(message, progress: progress);
  }

  int _safeIndex(int value, int length) {
    if (length <= 0) return -1;
    if (value < 0) return 0;
    return math.min(value, length - 1);
  }

  _Chapter? get _chapter =>
      _chapterIndex < 0 || _chapterIndex >= _project.chapters.length
          ? null
          : _project.chapters[_chapterIndex];

  _Character? get _character =>
      _characterIndex < 0 || _characterIndex >= _project.characters.length
          ? null
          : _project.characters[_characterIndex];

  _Term? get _term =>
      _termIndex < 0 || _termIndex >= _project.terms.length ? null : _project
          .terms[_termIndex];

  void _loadAllControllers() {
    _titleCtrl.text = _project.title;
    _genreCtrl.text = _project.genre;
    _loglineCtrl.text = _project.logline;
    _loadChapter();
    _loadDesign();
    _loadCharacter();
    _loadTerm();
  }

  void _loadChapter() {
    final c = _chapter;
    _chapterTitleCtrl.text = c?.title ?? '';
    _chapterBodyCtrl.text = c?.body ?? '';
    _chapterNoteCtrl.text = c?.note ?? '';
    _chapterTargetCtrl.text = '${c?.target ?? 4000}';
  }

  void _loadDesign() {
    final d = _project.design;
    _themeCtrl.text = d.theme;
    _synopsisCtrl.text = d.synopsis;
    _worldCtrl.text = d.world;
    _beginningCtrl.text = d.beginning;
    _developmentCtrl.text = d.development;
    _crisisCtrl.text = d.crisis;
    _climaxCtrl.text = d.climax;
    _endingCtrl.text = d.ending;
    _foreshadowCtrl.text = d.foreshadow;
    _designMemoCtrl.text = d.memo;
  }

  void _loadCharacter() {
    final c = _character;
    _charNameCtrl.text = c?.name ?? '';
    _charRoleCtrl.text = c?.role ?? '';
    _charAliasCtrl.text = c?.alias ?? '';
    _charAgeCtrl.text = c?.age ?? '';
    _charGenderCtrl.text = c?.gender ?? '';
    _charJobCtrl.text = c?.job ?? '';
    _charLookCtrl.text = c?.look ?? '';
    _charPersonalityCtrl.text = c?.personality ?? '';
    _charSpeechCtrl.text = c?.speech ?? '';
    _charDesireCtrl.text = c?.desire ?? '';
    _charWeaknessCtrl.text = c?.weakness ?? '';
    _charSecretCtrl.text = c?.secret ?? '';
    _charArcCtrl.text = c?.arc ?? '';
    _charRelationCtrl.text = c?.relations ?? '';
  }

  void _loadTerm() {
    final t = _term;
    _termNameCtrl.text = t?.name ?? '';
    _termAliasCtrl.text = t?.aliases ?? '';
    _termCategoryCtrl.text = t?.category ?? '';
    _termShortCtrl.text = t?.shortDefinition ?? '';
    _termDefinitionCtrl.text = t?.definition ?? '';
    _termUsageCtrl.text = t?.usage ?? '';
    _termRelatedCtrl.text = t?.related ?? '';
    _termMemoCtrl.text = t?.memo ?? '';
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _feedbackTimer?.cancel();
    if (!_saving) setState(() => _saving = true);
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveLocal);
  }

  Future<void> _saveLocal() async {
    _saveTimer?.cancel();
    await _LocalStore.save(_project);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  void _setProject(_Project next, {bool save = true}) {
    setState(() => _project = next.touch());
    if (save) _queueSave();
  }

  void _updateMeta() {
    _setProject(_project.copyWith(
      title: _titleCtrl.text
          .trim()
          .isEmpty ? '무제 소설' : _titleCtrl.text.trim(),
      genre: _genreCtrl.text.trim(),
      logline: _loglineCtrl.text.trim(),
    ));
  }

  void _updateDesign() {
    _setProject(_project.copyWith(
      design: _project.design.copyWith(
        theme: _themeCtrl.text,
        synopsis: _synopsisCtrl.text,
        world: _worldCtrl.text,
        beginning: _beginningCtrl.text,
        development: _developmentCtrl.text,
        crisis: _crisisCtrl.text,
        climax: _climaxCtrl.text,
        ending: _endingCtrl.text,
        foreshadow: _foreshadowCtrl.text,
        memo: _designMemoCtrl.text,
        updatedAt: DateTime.now(),
      ),
    ));
  }

  void _updateChapter() {
    final c = _chapter;
    if (c == null) return;
    final target = int.tryParse(_chapterTargetCtrl.text.trim()) ?? c.target;
    final list = List<_Chapter>.from(_project.chapters);
    final updated = c.copyWith(
      title: _chapterTitleCtrl.text
          .trim()
          .isEmpty ? '제목 없는 챕터' : _chapterTitleCtrl.text.trim(),
      body: _chapterBodyCtrl.text,
      note: _chapterNoteCtrl.text,
      target: target <= 0 ? 4000 : target,
      updatedAt: DateTime.now(),
    );
    list[_chapterIndex] = updated;
    _setProject(_project.copyWith(chapters: list, activeChapterId: updated.id));
  }

  void _updateCharacter() {
    final c = _character;
    if (c == null) return;
    final list = List<_Character>.from(_project.characters);
    list[_characterIndex] = c.copyWith(
      name: _charNameCtrl.text
          .trim()
          .isEmpty ? '새 인물' : _charNameCtrl.text.trim(),
      role: _charRoleCtrl.text.trim(),
      alias: _charAliasCtrl.text.trim(),
      age: _charAgeCtrl.text.trim(),
      gender: _charGenderCtrl.text.trim(),
      job: _charJobCtrl.text.trim(),
      look: _charLookCtrl.text,
      personality: _charPersonalityCtrl.text,
      speech: _charSpeechCtrl.text,
      desire: _charDesireCtrl.text,
      weakness: _charWeaknessCtrl.text,
      secret: _charSecretCtrl.text,
      arc: _charArcCtrl.text,
      relations: _charRelationCtrl.text,
      updatedAt: DateTime.now(),
    );
    _setProject(_project.copyWith(characters: list));
  }

  void _updateTerm() {
    final t = _term;
    if (t == null) return;
    final list = List<_Term>.from(_project.terms);
    list[_termIndex] = t.copyWith(
      name: _termNameCtrl.text
          .trim()
          .isEmpty ? '새 용어' : _termNameCtrl.text.trim(),
      aliases: _termAliasCtrl.text.trim(),
      category: _termCategoryCtrl.text
          .trim()
          .isEmpty ? '일반' : _termCategoryCtrl.text.trim(),
      shortDefinition: _termShortCtrl.text.trim(),
      definition: _termDefinitionCtrl.text,
      usage: _termUsageCtrl.text,
      related: _termRelatedCtrl.text,
      memo: _termMemoCtrl.text,
      updatedAt: DateTime.now(),
    );
    _setProject(_project.copyWith(terms: list));
  }

  void _selectChapter(int index) {
    if (index < 0 || index >= _project.chapters.length) return;
    _log('chapter_select index=$index id=${_project.chapters[index].id}');
    setState(() {
      _chapterIndex = index;
      _project = _project
          .copyWith(activeChapterId: _project.chapters[index].id)
          .touch();
      _tab = _NovelTab.chapters;
    });
    _loadChapter();
    _queueSave();
  }

  Future<void> _openChapterSelector() async {
    _log('chapter_selector_open count=${_project.chapters.length}');
    final selected = await showCommonOverlayDialog<int>(
      context: context,
      barrierLabel: '챕터 선택',
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return _NotenDialogShell(
          title: '챕터 선택',
          subtitle: '이동할 챕터를 선택합니다.',
          icon: Icons.article_rounded,
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .76,
          onClose: () => Navigator.of(dialogContext).pop(),
          trailing: _editMode
              ? IconButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _addChapter();
                  },
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '챕터 추가',
                )
              : null,
          child: _NotenListSurface(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _project.chapters.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: tokens.borderSubtle,
              ),
              itemBuilder: (_, index) {
                final chapter = _project.chapters[index];
                return _NotenSelectableRow(
                  selected: index == _chapterIndex,
                  icon: Icons.article_rounded,
                  title: chapter.title,
                  subtitle: '${chapter.count}자 · 목표 ${chapter.target}',
                  onTap: () => Navigator.of(dialogContext).pop(index),
                );
              },
            ),
          ),
        );
      },
    );
    if (selected != null) {
      _selectChapter(selected);
    }
  }

  void _selectCharacter(int index) {
    if (index < 0 || index >= _project.characters.length) return;
    _log('character_select index=$index id=${_project.characters[index].id}');
    setState(() {
      _characterIndex = index;
      _tab = _NovelTab.characters;
    });
    _loadCharacter();
  }

  void _selectTerm(int index) {
    if (index < 0 || index >= _project.terms.length) return;
    _log('term_select index=$index id=${_project.terms[index].id}');
    setState(() {
      _termIndex = index;
      _tab = _NovelTab.terms;
    });
    _loadTerm();
  }

  Future<void> _openCharacterSelector() async {
    _log('character_selector_open count=${_project.characters.length}');
    final selected = await showCommonOverlayDialog<int>(
      context: context,
      barrierLabel: '인물 선택',
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return _NotenDialogShell(
          title: '인물 선택',
          subtitle: '편집하거나 확인할 인물을 선택합니다.',
          icon: Icons.groups_rounded,
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .76,
          onClose: () => Navigator.of(dialogContext).pop(),
          trailing: _editMode
              ? IconButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _addCharacter();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  tooltip: '인물 추가',
                )
              : null,
          child: _project.characters.isEmpty
              ? const _NotenEmptyState(
                  icon: Icons.groups_rounded,
                  title: '등록된 인물이 없습니다',
                  body: '수정 모드를 켜고 인물을 추가하세요.',
                )
              : _NotenListSurface(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _project.characters.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: tokens.borderSubtle,
                    ),
                    itemBuilder: (_, index) {
                      final character = _project.characters[index];
                      return _NotenSelectableRow(
                        selected: index == _characterIndex,
                        icon: Icons.person_rounded,
                        title: character.displayName,
                        subtitle: character.role.isEmpty ? '역할 미정' : character.role,
                        onTap: () => Navigator.of(dialogContext).pop(index),
                      );
                    },
                  ),
                ),
        );
      },
    );
    if (selected != null) {
      _selectCharacter(selected);
    }
  }

  Future<void> _openTermSelector() async {
    _log('term_selector_open count=${_project.terms.length}');
    final selected = await showCommonOverlayDialog<int>(
      context: context,
      barrierLabel: '용어 선택',
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return _NotenDialogShell(
          title: '용어 선택',
          subtitle: '편집하거나 확인할 용어를 선택합니다.',
          icon: Icons.menu_book_rounded,
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .76,
          onClose: () => Navigator.of(dialogContext).pop(),
          trailing: _editMode
              ? IconButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _addTerm();
                  },
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '용어 추가',
                )
              : null,
          child: _project.terms.isEmpty
              ? const _NotenEmptyState(
                  icon: Icons.menu_book_rounded,
                  title: '등록된 용어가 없습니다',
                  body: '수정 모드를 켜고 용어를 추가하세요.',
                )
              : _NotenListSurface(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _project.terms.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: tokens.borderSubtle,
                    ),
                    itemBuilder: (_, index) {
                      final term = _project.terms[index];
                      return _NotenSelectableRow(
                        selected: index == _termIndex,
                        icon: Icons.menu_book_rounded,
                        title: term.displayName,
                        subtitle: term.category,
                        onTap: () => Navigator.of(dialogContext).pop(index),
                      );
                    },
                  ),
                ),
        );
      },
    );
    if (selected != null) {
      _selectTerm(selected);
    }
  }

  void _addChapter() {
    if (!_editMode) return;
    _log('chapter_add_requested');
    final now = DateTime.now();
    final list = List<_Chapter>.from(_project.chapters);
    final chapter = _Chapter(id: _Ids.newId('chapter'),
        title: 'Chapter ${('${list.length + 1}').padLeft(2, '0')}. 새 장면',
        body: '',
        note: '',
        target: 4000,
        order: list.length,
        createdAt: now,
        updatedAt: now);
    list.add(chapter);
    setState(() {
      _project = _project
          .copyWith(chapters: list, activeChapterId: chapter.id)
          .touch();
      _chapterIndex = list.length - 1;
      _tab = _NovelTab.chapters;
    });
    _loadChapter();
    _queueSave();
  }

  void _addCharacter() {
    if (!_editMode) return;
    _log('character_add_requested');
    final now = DateTime.now();
    final list = List<_Character>.from(_project.characters)
      ..add(_Character.empty(now));
    setState(() {
      _project = _project.copyWith(characters: list).touch();
      _characterIndex = list.length - 1;
      _tab = _NovelTab.characters;
    });
    _loadCharacter();
    _queueSave();
  }

  void _addTerm() {
    if (!_editMode) return;
    _log('term_add_requested');
    final now = DateTime.now();
    final list = List<_Term>.from(_project.terms)
      ..add(_Term.empty(now));
    setState(() {
      _project = _project.copyWith(terms: list).touch();
      _termIndex = list.length - 1;
      _tab = _NovelTab.terms;
    });
    _loadTerm();
    _queueSave();
  }

  Future<void> _deleteChapter() async {
    if (!_editMode || _project.chapters.length <= 1) {
      _showFeedback(
        '최소 1개의 챕터는 필요합니다.',
        tone: _NotenFeedbackTone.warning,
      );
      return;
    }
    final ok = await _confirm('챕터 삭제', '현재 챕터를 삭제하시겠습니까?');
    if (ok != true) return;
    _log('chapter_delete_confirmed id=${_chapter?.id}');
    final list = List<_Chapter>.from(_project.chapters)
      ..removeAt(_chapterIndex);
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(order: i, updatedAt: DateTime.now());
    }
    setState(() {
      _chapterIndex = _safeIndex(_chapterIndex, list.length);
      _project = _project.copyWith(
          chapters: list, activeChapterId: list[_chapterIndex].id).touch();
    });
    _loadChapter();
    _queueSave();
  }

  Future<void> _deleteCharacter() async {
    if (!_editMode || _character == null) return;
    final ok = await _confirm(
        '인물 삭제', '${_character!.displayName} 인물을 삭제하시겠습니까?');
    if (ok != true) return;
    _log('character_delete_confirmed id=${_character?.id}');
    final list = List<_Character>.from(_project.characters)
      ..removeAt(_characterIndex);
    setState(() {
      _characterIndex = _safeIndex(_characterIndex, list.length);
      _project = _project.copyWith(characters: list).touch();
    });
    _loadCharacter();
    _queueSave();
  }

  Future<void> _deleteTerm() async {
    if (!_editMode || _term == null) return;
    final ok = await _confirm('용어 삭제', '${_term!.displayName} 용어를 삭제하시겠습니까?');
    if (ok != true) return;
    _log('term_delete_confirmed id=${_term?.id}');
    final list = List<_Term>.from(_project.terms)
      ..removeAt(_termIndex);
    setState(() {
      _termIndex = _safeIndex(_termIndex, list.length);
      _project = _project.copyWith(terms: list).touch();
    });
    _loadTerm();
    _queueSave();
  }

  void _toggleEdit() {
    setState(() => _editMode = !_editMode);
    _log('edit_mode changed=${_editMode ? 'on' : 'off'}');
    _showFeedback(
      _editMode ? '수정 모드가 켜졌습니다.' : '수정 모드가 꺼졌습니다.',
      tone: _editMode ? _NotenFeedbackTone.success : _NotenFeedbackTone.info,
    );
  }

  void _toggleFocus() {
    setState(() => _focusMode = !_focusMode);
    _log('focus_mode changed=${_focusMode ? 'on' : 'off'}');
  }

  Future<void> _requestExit({required String source}) async {
    if (_exitDialogOpen) {
      _log('exit_request_ignored source=$source reason=dialog_open');
      return;
    }
    _exitDialogOpen = true;
    _log('exit_requested source=$source', progress: .62);
    try {
      final ok = await _confirm(
        'notensystem 종료',
        '현재 작업을 저장하고 화면을 종료하시겠습니까?',
      );
      _log('exit_confirmation source=$source confirmed=${ok == true}');
      if (ok != true || !mounted) return;
      await _saveLocal();
      if (!mounted) return;
      _log('exit_completed source=$source', progress: .94);
      Navigator.of(context).pop();
    } finally {
      _exitDialogOpen = false;
    }
  }

  Future<bool?> _confirm(String title, String message) {
    return showCommonOverlayDialog<bool>(
      context: context,
      barrierLabel: title,
      builder: (dialogContext) {
        return _NotenDialogShell(
          title: title,
          subtitle: message,
          icon: Icons.help_outline_rounded,
          maxWidth: 430,
          onClose: () => Navigator.of(dialogContext).pop(false),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFeedback(
    String text, {
    _NotenFeedbackTone tone = _NotenFeedbackTone.info,
    Duration duration = const Duration(milliseconds: 2400),
  }) {
    if (!mounted) return;
    _feedbackTimer?.cancel();
    final id = ++_feedbackSerial;
    setState(() {
      _feedback = _NotenFeedback(
        id: id,
        message: text,
        tone: tone,
      );
    });
    _log('feedback_show id=$id tone=${tone.name} message=${jsonEncode(text)}');
    _feedbackTimer = Timer(duration, () {
      if (!mounted || _feedback?.id != id) return;
      setState(() => _feedback = null);
      _log('feedback_auto_hide id=$id tone=${tone.name}');
    });
  }

  void _dismissFeedback() {
    final feedback = _feedback;
    if (feedback == null) return;
    _feedbackTimer?.cancel();
    if (mounted) setState(() => _feedback = null);
    _log('feedback_dismissed id=${feedback.id} tone=${feedback.tone.name}');
  }

  Future<bool> _run(String title, Future<String> Function() task) async {
    if (_busy) return false;
    var success = false;
    setState(() => _busy = true);
    _log('operation_start title=$title busy=true', progress: .34);
    try {
      await _saveLocal();
      final msg = await task();
      success = true;
      _log('operation_success title=$title message=$msg', progress: .72);
      if (!mounted) return success;
      await _showMessageDialog(
        title: title,
        message: msg,
        icon: Icons.check_circle_rounded,
      );
    } catch (error, stackTrace) {
      _log('operation_failure title=$title error=$error');
      _trace?.log('operation_stack title=$title stack=$stackTrace');
      if (!mounted) return false;
      await _showMessageDialog(
        title: '작업 실패',
        message: '$error',
        icon: Icons.error_outline_rounded,
        failure: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      _log('operation_end title=$title busy=false success=$success', progress: .82);
    }
    return success;
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
    required IconData icon,
    bool failure = false,
  }) {
    return showCommonOverlayDialog<void>(
      context: context,
      barrierLabel: title,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return _NotenDialogShell(
          title: title,
          subtitle: message,
          icon: icon,
          iconColor: failure ? tokens.danger : tokens.success,
          maxWidth: 460,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ),
        );
      },
    );
  }

  bool get _cloudBackupCurrent {
    final metadata = _cloudBackupMetadata;
    if (metadata == null) return false;
    return metadata.fingerprint ==
        NovelCloudBackupStore.fingerprintProject(_project.toJson());
  }

  _ToolActionStatus get _cloudToolStatus {
    if (_cloudOperation != _CloudOperation.idle) {
      return _ToolActionStatus.working;
    }
    if (_cloudFailed) return _ToolActionStatus.failed;
    return _cloudBackupCurrent
        ? _ToolActionStatus.current
        : _ToolActionStatus.needsBackup;
  }

  String get _cloudBackupSubtitle {
    final metadata = _cloudBackupMetadata;
    if (metadata == null) {
      return '변경된 프로젝트를 압축 스냅샷 1개로 백업합니다.';
    }
    if (_cloudBackupCurrent) {
      return '마지막 백업 ${_Export.dt(metadata.backedUpAt)} · ${_formatBytes(metadata.compressedBytes)}';
    }
    return '변경사항이 있습니다. 백업 시 압축 파일 1개만 업로드합니다.';
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _backupCloud() async {
    if (_busy) return;
    final forceUpload = _cloudFailed;
    if (mounted) {
      setState(() {
        _cloudOperation = _CloudOperation.backup;
        _cloudFailed = false;
      });
    }
    _log(
      'cloud_backup_requested projectId=${_project.id} path=${_cloudBackupStore.pathFor(_project.id)}',
      progress: .42,
    );
    final success = await _run('클라우드 백업', () async {
      final result = await _cloudBackupStore.backup(
        projectId: _project.id,
        sourceUpdatedAt: _project.updatedAt,
        project: _project.toJson(),
        force: forceUpload,
        log: (message) => _log(message),
      );
      if (mounted) {
        setState(() => _cloudBackupMetadata = result.metadata);
      }
      if (!result.uploaded) {
        return '변경사항이 없어 클라우드 업로드를 생략했습니다.';
      }
      return '클라우드 백업을 완료했습니다.\n${_formatBytes(result.metadata.rawBytes)} → ${_formatBytes(result.metadata.compressedBytes)}';
    });
    if (!mounted) return;
    setState(() {
      _cloudOperation = _CloudOperation.idle;
      _cloudFailed = !success;
    });
  }

  Future<void> _restoreCloud() async {
    if (_busy) return;
    final ok = await _confirm(
      '클라우드 복원',
      '현재 로컬 프로젝트를 마지막 클라우드 백업으로 교체하시겠습니까?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      _cloudOperation = _CloudOperation.restore;
      _cloudFailed = false;
    });
    _log(
      'cloud_restore_requested projectId=${_project.id} path=${_cloudBackupStore.pathFor(_project.id)}',
      progress: .42,
    );
    final success = await _run('클라우드 복원', () async {
      final projectBeforeRestore = _project;
      await _LocalStore.savePreRestore(projectBeforeRestore);
      _log(
        'cloud_restore_safety_snapshot_saved projectId=${projectBeforeRestore.id}',
        progress: .45,
      );
      var remoteApplied = false;
      try {
        final result = await _cloudBackupStore.restore(
          projectId: projectBeforeRestore.id,
          log: (message) => _log(message),
        );
        final project = _Project.fromJson(result.project);
        _applyPulledProject(project, save: false);
        remoteApplied = true;
        await _saveLocal();
        if (mounted) {
          setState(() => _cloudBackupMetadata = result.metadata);
        }
        _log(
          'cloud_restore_local_commit_success projectId=${project.id}',
          progress: .7,
        );
        return '클라우드 백업을 복원했습니다.\n다운로드 ${_formatBytes(result.metadata.compressedBytes)} · 복원 ${_formatBytes(result.metadata.rawBytes)}';
      } catch (error, stackTrace) {
        _log(
          'cloud_restore_failure_before_rollback remoteApplied=$remoteApplied error=$error',
          progress: .62,
        );
        _trace?.log(
          'cloud_restore_failure_stack remoteApplied=$remoteApplied stack=$stackTrace',
        );
        if (remoteApplied) {
          _log(
            'cloud_restore_rollback_started projectId=${projectBeforeRestore.id}',
            progress: .64,
          );
          try {
            final rollbackProject =
                await _LocalStore.loadPreRestore() ?? projectBeforeRestore;
            _applyPulledProject(rollbackProject, save: false);
            await _saveLocal();
            _log(
              'cloud_restore_rollback_success projectId=${rollbackProject.id}',
              progress: .68,
            );
          } catch (rollbackError, rollbackStackTrace) {
            _log(
              'cloud_restore_rollback_failure error=$rollbackError',
              progress: .68,
            );
            _trace?.log(
              'cloud_restore_rollback_stack stack=$rollbackStackTrace',
            );
          }
        } else {
          _log(
            'cloud_restore_rollback_skipped remoteApplied=false',
            progress: .68,
          );
        }
        rethrow;
      }
    });
    if (!mounted) return;
    setState(() {
      _cloudOperation = _CloudOperation.idle;
      _cloudFailed = !success;
    });
  }

  Future<void> _openTools() async {
    _log(
      'tools_dialog_open cloudStatus=${_cloudToolStatus.name} cloudCurrent=$_cloudBackupCurrent',
    );
    await showCommonOverlayDialog<void>(
      context: context,
      barrierLabel: '저장 및 전송',
      builder: (dialogContext) {
        return _NotenDialogShell(
          title: '저장 · 전송',
          subtitle: '로컬 저장, 클라우드 백업과 문서 전송을 관리합니다.',
          icon: Icons.save_alt_rounded,
          maxWidth: 620,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .84,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _toolSection(
                dialogContext,
                '저장',
                [
                  _ToolAction(
                    icon: Icons.save_rounded,
                    title: '로컬 저장',
                    subtitle: '현재 프로젝트를 기기에 저장합니다.',
                    run: () async {
                      await _run('로컬 저장', () async {
                        return '현재 프로젝트를 기기에 저장했습니다.';
                      });
                    },
                  ),
                  _ToolAction(
                    icon: Icons.cloud_upload_rounded,
                    title: '클라우드 백업',
                    subtitle: _cloudBackupSubtitle,
                    status: _cloudToolStatus,
                    run: _backupCloud,
                  ),
                  _ToolAction(
                    icon: Icons.cloud_download_rounded,
                    title: '클라우드 복원',
                    subtitle: '마지막 압축 스냅샷 1개를 내려받아 프로젝트를 복원합니다.',
                    status: _cloudOperation == _CloudOperation.restore
                        ? _ToolActionStatus.working
                        : _ToolActionStatus.none,
                    run: _restoreCloud,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _toolSection(
                dialogContext,
                '전송',
                [
                  _ToolAction(
                    icon: Icons.people_alt_rounded,
                    title: '수신자 관리',
                    subtitle: '문서를 받을 이메일을 관리합니다.',
                    run: _openRecipients,
                  ),
                  _ToolAction(
                    icon: Icons.attach_email_rounded,
                    title: 'PDF + Markdown 전송',
                    subtitle: '선택한 수신자에게 프로젝트 문서를 이메일로 전송합니다.',
                    run: _sendMail,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolSection(
    BuildContext dialogContext,
    String title,
    List<_ToolAction> actions,
  ) {
    final tokens = CommonUiTheme.of(dialogContext);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
          child: Text(
            title,
            style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        _NotenListSurface(
          child: Column(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                _NotenActionRow(
                  icon: actions[index].icon,
                  title: actions[index].title,
                  subtitle: actions[index].subtitle,
                  enabled: !_busy,
                  trailing: _toolStatus(dialogContext, actions[index].status),
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    _log(
                      'tool_action id=${actions[index].title} cloudStatus=${actions[index].status.name}',
                    );
                    await actions[index].run();
                  },
                ),
                if (index != actions.length - 1)
                  Divider(height: 1, color: tokens.borderSubtle),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget? _toolStatus(BuildContext context, _ToolActionStatus status) {
    if (status == _ToolActionStatus.none) return null;
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    late final String label;
    late final IconData icon;
    late final Color foreground;
    late final Color background;
    switch (status) {
      case _ToolActionStatus.none:
        return null;
      case _ToolActionStatus.current:
        label = '최신';
        icon = Icons.check_rounded;
        foreground = tokens.success;
        background = tokens.successContainer;
        break;
      case _ToolActionStatus.needsBackup:
        label = '백업 필요';
        icon = Icons.cloud_upload_rounded;
        foreground = tokens.accent;
        background = tokens.accentContainer;
        break;
      case _ToolActionStatus.working:
        label = _cloudOperation == _CloudOperation.restore ? '복원 중' : '백업 중';
        icon = Icons.sync_rounded;
        foreground = tokens.info;
        background = tokens.infoContainer;
        break;
      case _ToolActionStatus.failed:
        label = '확인 필요';
        icon = Icons.error_outline_rounded;
        foreground = tokens.danger;
        background = tokens.dangerContainer;
        break;
    }
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: _NotenStatusPill(
        key: ValueKey<String>(status.name),
        icon: icon,
        label: label,
        foreground: foreground,
        background: background,
      ),
    );
  }

  void _applyPulledProject(
    _Project p, {
    bool save = true,
  }) {
    setState(() {
      _project = p;
      _chapterIndex = _safeIndex(
        _project.chapters.indexWhere((e) => e.id == _project.activeChapterId),
        _project.chapters.length,
      );
      _characterIndex = _safeIndex(0, _project.characters.length);
      _termIndex = _safeIndex(0, _project.terms.length);
    });
    _loadAllControllers();
    if (save) {
      _queueSave();
    }
  }

  Future<void> _openRecipients() async {
    _recipientCtrl.clear();
    _log('recipients_dialog_open count=${_project.recipients.length}');
    await showCommonOverlayDialog<void>(
      context: context,
      barrierLabel: '수신자 보관함',
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final tokens = CommonUiTheme.of(dialogContext);
            return _NotenDialogShell(
              title: '수신자 보관함',
              subtitle: 'PDF와 Markdown을 받을 이메일을 관리합니다.',
              icon: Icons.people_alt_rounded,
              maxWidth: 600,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .78,
              onClose: () => Navigator.of(dialogContext).pop(),
              child: Column(
                children: [
                  _NotenListSurface(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _recipientCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: '이메일',
                                isDense: true,
                                filled: true,
                                fillColor: tokens.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: tokens.borderSubtle),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () {
                              final email = _recipientCtrl.text.trim().toLowerCase();
                              if (!_Mail.isValid(email)) {
                                _showFeedback(
                                  '이메일 형식을 확인하세요.',
                                  tone: _NotenFeedbackTone.warning,
                                );
                                return;
                              }
                              if (_project.recipients.any((e) => e.email == email)) {
                                _showFeedback(
                                  '이미 등록된 이메일입니다.',
                                  tone: _NotenFeedbackTone.warning,
                                );
                                return;
                              }
                              final now = DateTime.now();
                              final list = List<_Recipient>.from(_project.recipients)
                                ..add(
                                  _Recipient(
                                    id: _Ids.newId('recipient'),
                                    email: email,
                                    label: _Mail.label(email),
                                    selected: true,
                                    createdAt: now,
                                    updatedAt: now,
                                  ),
                                );
                              setState(() {
                                _project = _project.copyWith(recipients: list).touch();
                              });
                              setDialogState(() {});
                              _recipientCtrl.clear();
                              _queueSave();
                              _log('recipient_add email=$email');
                            },
                            icon: const Icon(Icons.add_rounded),
                            tooltip: '수신자 추가',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _project.recipients.isEmpty
                        ? _NotenEmptyState(
                            icon: Icons.mail_outline_rounded,
                            title: '등록된 수신자가 없습니다',
                            body: '이메일을 추가하면 문서를 선택한 수신자에게 전송할 수 있습니다.',
                          )
                        : _NotenListSurface(
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _project.recipients.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: tokens.borderSubtle,
                              ),
                              itemBuilder: (_, index) {
                                final recipient = _project.recipients[index];
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: recipient.selected,
                                        onChanged: (value) {
                                          final list = List<_Recipient>.from(_project.recipients);
                                          list[index] = recipient.copyWith(
                                            selected: value == true,
                                            updatedAt: DateTime.now(),
                                          );
                                          setState(() {
                                            _project = _project.copyWith(recipients: list).touch();
                                          });
                                          setDialogState(() {});
                                          _queueSave();
                                          _log('recipient_toggle email=${recipient.email} selected=${value == true}');
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              recipient.email,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                            Text(
                                              recipient.label,
                                              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                                                    color: tokens.textSecondary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          final list = List<_Recipient>.from(_project.recipients)
                                            ..removeAt(index);
                                          setState(() {
                                            _project = _project.copyWith(recipients: list).touch();
                                          });
                                          setDialogState(() {});
                                          _queueSave();
                                          _log('recipient_remove email=${recipient.email}');
                                        },
                                        icon: const Icon(Icons.delete_outline_rounded),
                                        tooltip: '삭제',
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendMail() async {
    final selected = _project.recipients.where((e) =>
    e.selected && _Mail.isValid(e.email)).toList();
    if (selected.isEmpty) {
      _showFeedback(
        '수신자 보관함에서 이메일을 선택하세요.',
        tone: _NotenFeedbackTone.warning,
      );
      await _openRecipients();
      return;
    }
    await _run('메일 전송 완료', () async {
      if (GoogleAuthSession.instance.isSessionBlocked) throw StateError(
          '구글 세션이 차단되어 전송할 수 없습니다.');
      final now = DateTime.now();
      final pdf = await _Export.pdf(_project, now);
      final md = _Export.markdown(_project, now);
      final safe = _Export.safeName(_project.title);
      final tag = _Export.compact(now);
      final rawMime = _Mail.mime(
        toCsv: selected.map((e) => e.email).join(', '),
        subject: '${_project.title} 소설 문서 (${_Export.ymd(now)})',
        bodyText: 'notensystem 소설 문서를 첨부합니다. PDF는 공유용, Markdown은 백업과 재편집용입니다.',
        pdfName: '${safe}_$tag.pdf',
        pdfBytes: pdf,
        markdownName: '${safe}_$tag.md',
        markdownText: md,
        boundary: 'notensystem_${now.microsecondsSinceEpoch}',
      );
      final client = await GmailSenderAuth.client();
      final api = gmail.GmailApi(client);
      await api.users.messages.send(gmail.Message()
        ..raw = base64UrlEncode(utf8.encode(rawMime)).replaceAll('=', ''),
          'me');
      return '${selected.length}명에게 PDF와 Markdown을 전송했습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _requestExit(source: 'system_back');
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    if (_checking) {
      return Scaffold(
        backgroundColor: tokens.canvas,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: tokens.accent),
          ),
        ),
      );
    }
    if (!_authorized) return _locked(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final metrics = CommonSideRailMetrics.resolve(
              dockHeight: constraints.maxHeight,
              textScale: media.textScaler.scale(1),
            );
            final railWidth = metrics.effectiveRailWidth(constraints.maxWidth);
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                    child: Column(
                      children: [
                        _topSurface(context),
                        _feedbackRegion(context),
                        if (!_focusMode) ...[
                          const SizedBox(height: 8),
                          _statusSurface(context),
                        ],
                        const SizedBox(height: 8),
                        Expanded(child: _workspaceSwitcher(context)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: metrics.effectiveRailGap(constraints.maxWidth)),
                SizedBox(
                  width: railWidth,
                  child: _rightRail(context, metrics),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _locked(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _NotenListSurface(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 42, color: tokens.accent),
                      const SizedBox(height: 14),
                      Text(
                        '개발자 모드가 필요합니다',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'notensystem은 개발자 모드에서 사용할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () => _requestExit(source: 'locked_screen'),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('종료'),
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
  }

  Widget _feedbackRegion(BuildContext context) {
    final feedback = _feedback;
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
    return AnimatedSize(
      duration: duration,
      curve: CommonUiMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: feedback == null
            ? const SizedBox(key: ValueKey<String>('feedback_empty'))
            : Padding(
                key: ValueKey<int>(feedback.id),
                padding: const EdgeInsets.only(top: 8),
                child: _NotenListSurface(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _feedbackColor(tokens, feedback.tone),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          _feedbackIcon(feedback.tone),
                          size: 18,
                          color: _feedbackColor(tokens, feedback.tone),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feedback.message,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: _dismissFeedback,
                          icon: const Icon(Icons.close_rounded),
                          tooltip: '닫기',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Color _feedbackColor(CommonUiTokens tokens, _NotenFeedbackTone tone) {
    switch (tone) {
      case _NotenFeedbackTone.success:
        return tokens.success;
      case _NotenFeedbackTone.warning:
        return tokens.warning;
      case _NotenFeedbackTone.danger:
        return tokens.danger;
      case _NotenFeedbackTone.info:
        return tokens.info;
    }
  }

  IconData _feedbackIcon(_NotenFeedbackTone tone) {
    switch (tone) {
      case _NotenFeedbackTone.success:
        return Icons.check_circle_outline_rounded;
      case _NotenFeedbackTone.warning:
        return Icons.warning_amber_rounded;
      case _NotenFeedbackTone.danger:
        return Icons.error_outline_rounded;
      case _NotenFeedbackTone.info:
        return Icons.info_outline_rounded;
    }
  }

  Widget _topSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return _NotenListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _titleCtrl,
                readOnly: !_editMode,
                maxLines: 1,
                onChanged: (_) => _updateMeta(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 7),
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .92, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: _NotenStatusPill(
                key: ValueKey<bool>(_saving),
                icon: _saving ? Icons.sync_rounded : Icons.check_circle_rounded,
                label: _saving ? '저장 중' : '저장됨',
                foreground: _saving ? tokens.warning : tokens.success,
                background: _saving
                    ? tokens.warningContainer
                    : tokens.successContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final current = _chapter?.count ?? 0;
    final target = _chapter?.target ?? 0;
    final progress = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0).toDouble();
    return _NotenListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              _editMode ? Icons.edit_rounded : Icons.lock_outline_rounded,
              size: 16,
              color: _editMode ? tokens.accent : tokens.iconSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              _editMode ? '수정 가능' : '읽기 전용',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                      ? Duration.zero
                      : CommonUiMotion.layout,
                  curve: CommonUiMotion.enter,
                  builder: (_, value, __) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: tokens.surfaceDisabled,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$current / $target자',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(width: 8),
            Text(
              '전체 ${_project.totalCount}자',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceSwitcher(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.018, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<_NovelTab>(_tab),
        child: _workspace(context),
      ),
    );
  }

  Widget _workspace(BuildContext context) {
    switch (_tab) {
      case _NovelTab.design:
        return _designWorkspace(context);
      case _NovelTab.characters:
        return _characterWorkspace(context);
      case _NovelTab.terms:
        return _termWorkspace(context);
      case _NovelTab.chapters:
        return _chapterWorkspace(context);
    }
  }

  void _selectWorkspace(_NovelTab tab) {
    if (_tab == tab) {
      if (tab == _NovelTab.chapters && _project.chapters.length > 1) {
        _openChapterSelector();
      }
      return;
    }
    setState(() => _tab = tab);
    _log('workspace_select tab=${tab.name}');
  }

  Widget _rightRail(BuildContext context, CommonSideRailMetrics metrics) {
    final tokens = CommonUiTheme.of(context);
    final actions = <_NotenRailAction>[
      _NotenRailAction(
        label: '챕터',
        icon: Icons.article_rounded,
        selected: _tab == _NovelTab.chapters,
        onTap: () => _selectWorkspace(_NovelTab.chapters),
      ),
      _NotenRailAction(
        label: '설계',
        icon: Icons.architecture_rounded,
        selected: _tab == _NovelTab.design,
        onTap: () => _selectWorkspace(_NovelTab.design),
      ),
      _NotenRailAction(
        label: '인물',
        icon: Icons.groups_rounded,
        selected: _tab == _NovelTab.characters,
        onTap: () => _selectWorkspace(_NovelTab.characters),
      ),
      _NotenRailAction(
        label: '용어',
        icon: Icons.menu_book_rounded,
        selected: _tab == _NovelTab.terms,
        onTap: () => _selectWorkspace(_NovelTab.terms),
      ),
      _NotenRailAction.divider(),
      _NotenRailAction(
        label: _editMode ? '수정 끄기' : '수정 켜기',
        icon: _editMode ? Icons.edit_rounded : Icons.lock_outline_rounded,
        selected: _editMode,
        onTap: _toggleEdit,
      ),
      _NotenRailAction(
        label: _focusMode ? '집중 해제' : '집중 모드',
        icon: _focusMode
            ? Icons.fullscreen_exit_rounded
            : Icons.center_focus_strong_rounded,
        selected: _focusMode,
        onTap: _toggleFocus,
      ),
      _NotenRailAction(
        label: '저장·전송',
        icon: Icons.cloud_sync_rounded,
        enabled: !_busy,
        onTap: _openTools,
      ),
      if (_trace?.developerMode == true)
        _NotenRailAction(
          label: '상태',
          icon: Icons.bug_report_rounded,
          onTap: _openDeveloperStatus,
        ),
      _NotenRailAction.divider(),
      _NotenRailAction(
        label: '종료',
        icon: Icons.logout_rounded,
        danger: true,
        onTap: () => _requestExit(source: 'right_rail'),
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface.withOpacity(.28),
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: metrics.headerHeight + metrics.outerVertical * 2,
            child: Center(
              child: Semantics(
                label: 'notensystem 탐색',
                child: Container(
                  width: metrics.ultra ? 26 : 30,
                  height: metrics.ultra ? 26 : 30,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer.withOpacity(.72),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.accent.withOpacity(.28)),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: metrics.ultra ? 16 : 18,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.actionInsetHorizontal,
                vertical: metrics.actionInsetVertical,
              ),
              children: [
                for (final action in actions)
                  action.divider
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Divider(height: 1, color: tokens.borderSubtle),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: _NotenRailButton(
                            action: action,
                            extent: metrics.minimumButtonExtent,
                            compact: metrics.compact,
                          ),
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeveloperStatus() async {
    final trace = _trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    final cloud = _cloudBackupMetadata;
    final hasPreRestore = await _LocalStore.hasPreRestore();
    if (!mounted) return;
    _log(
      'developer_status_requested tab=${_tab.name} edit=$_editMode focus=$_focusMode busy=$_busy feedback=${_feedback?.tone.name ?? 'none'} cloudOperation=${_cloudOperation.name} cloudCurrent=$_cloudBackupCurrent cloudFailed=$_cloudFailed cloudPath=${_cloudBackupStore.pathFor(_project.id)} cloudCompressedBytes=${cloud?.compressedBytes ?? 0} preRestore=$hasPreRestore chapterIndex=$_chapterIndex characterIndex=$_characterIndex termIndex=$_termIndex',
      progress: .9,
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: 'notensystem 상태',
      description:
          'tab=${_tab.name} edit=$_editMode focus=$_focusMode busy=$_busy feedback=${_feedback?.tone.name ?? 'none'} cloud=${_cloudToolStatus.name} cloudCurrent=$_cloudBackupCurrent cloudBackedUpAt=${cloud?.backedUpAt.toIso8601String() ?? 'none'} cloudPath=${_cloudBackupStore.pathFor(_project.id)} cloudRawBytes=${cloud?.rawBytes ?? 0} cloudCompressedBytes=${cloud?.compressedBytes ?? 0} preRestore=$hasPreRestore chapters=${_project.chapters.length} characters=${_project.characters.length} terms=${_project.terms.length}',
    );
  }

  Widget _workspaceHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    List<Widget> actions = const [],
  }) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    VoidCallback onChanged, {
    int lines = 1,
    TextInputType? keyboard,
    bool last = false,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      decoration: BoxDecoration(
        color: _editMode ? tokens.transparent : tokens.surfaceDisabled.withOpacity(.34),
        border: last ? null : Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            readOnly: !_editMode,
            maxLines: lines,
            keyboardType: keyboard,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterWorkspace(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final editor = Column(
      children: [
        _workspaceHeader(
          context,
          title: '챕터',
          subtitle: '원고, 목표 글자 수와 장면 메모를 관리합니다.',
          icon: Icons.article_rounded,
          actions: [
            IconButton(
              onPressed: _openChapterSelector,
              icon: const Icon(Icons.view_list_rounded),
              tooltip: '챕터 선택',
            ),
            if (_editMode)
              IconButton(
                onPressed: _addChapter,
                icon: const Icon(Icons.add_rounded),
                tooltip: '챕터 추가',
              ),
            if (_editMode)
              IconButton(
                onPressed: _deleteChapter,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '챕터 삭제',
              ),
          ],
        ),
        if (!_focusMode) ...[
          _NotenListSurface(
            child: Column(
              children: [
                _field('챕터 제목', _chapterTitleCtrl, _updateChapter),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: _field(
                        '목표 글자',
                        _chapterTargetCtrl,
                        _updateChapter,
                        keyboard: TextInputType.number,
                        last: true,
                      ),
                    ),
                    Expanded(
                      child: _field(
                        '챕터 메모',
                        _chapterNoteCtrl,
                        _updateChapter,
                        last: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _NotenListSurface(
            child: TextField(
              controller: _chapterBodyCtrl,
              focusNode: _bodyFocus,
              readOnly: !_editMode,
              onChanged: (_) => _updateChapter(),
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(16, 14, 16, 20),
              ),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.7,
                    fontSize: 16.5,
                  ),
            ),
          ),
        ),
      ],
    );
    if (_focusMode || !wide) {
      return editor;
    }
    return Row(
      children: [
        SizedBox(width: 260, child: _chapterList()),
        const SizedBox(width: 8),
        Expanded(child: editor),
      ],
    );
  }

  Widget _chapterList() {
    return _entityList(
      title: '챕터 목록',
      count: _project.chapters.length,
      add: _editMode ? _addChapter : null,
      itemBuilder: (index) {
        final chapter = _project.chapters[index];
        return _NotenSelectableRow(
          selected: _chapterIndex == index,
          icon: Icons.article_rounded,
          title: chapter.title,
          subtitle: '${chapter.count}자 · 목표 ${chapter.target}',
          onTap: () => _selectChapter(index),
        );
      },
    );
  }

  Widget _designWorkspace(BuildContext context) {
    return Column(
      children: [
        _workspaceHeader(
          context,
          title: '설계',
          subtitle: '기본 정보, 세계관, 플롯과 작가 메모를 관리합니다.',
          icon: Icons.architecture_rounded,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _fieldSection(
                context,
                title: '기본 정보',
                icon: Icons.description_outlined,
                children: [
                  _field('장르', _genreCtrl, _updateMeta),
                  _field('로그라인', _loglineCtrl, _updateMeta, lines: 2),
                  _field('핵심 주제', _themeCtrl, _updateDesign, lines: 3),
                  _field('전체 시놉시스', _synopsisCtrl, _updateDesign, lines: 6, last: true),
                ],
              ),
              const SizedBox(height: 8),
              _fieldSection(
                context,
                title: '세계관',
                icon: Icons.public_rounded,
                children: [
                  _field('세계관 / 시대 / 장소 / 규칙', _worldCtrl, _updateDesign, lines: 7, last: true),
                ],
              ),
              const SizedBox(height: 8),
              _fieldSection(
                context,
                title: '플롯 구조',
                icon: Icons.account_tree_rounded,
                children: [
                  _field('발단', _beginningCtrl, _updateDesign, lines: 4),
                  _field('전개', _developmentCtrl, _updateDesign, lines: 4),
                  _field('위기', _crisisCtrl, _updateDesign, lines: 4),
                  _field('절정', _climaxCtrl, _updateDesign, lines: 4),
                  _field('결말', _endingCtrl, _updateDesign, lines: 4),
                  _field('복선 / 회수 계획', _foreshadowCtrl, _updateDesign, lines: 5, last: true),
                ],
              ),
              const SizedBox(height: 8),
              _fieldSection(
                context,
                title: '작가 메모',
                icon: Icons.edit_note_rounded,
                children: [
                  _field('수정할 점 / 다음 집필 계획', _designMemoCtrl, _updateDesign, lines: 6, last: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _characterWorkspace(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final editor = Column(
      children: [
        _workspaceHeader(
          context,
          title: '인물',
          subtitle: '인물의 역할, 성격, 욕망과 관계를 관리합니다.',
          icon: Icons.groups_rounded,
          actions: [
            IconButton(
              onPressed: _openCharacterSelector,
              icon: const Icon(Icons.view_list_rounded),
              tooltip: '인물 선택',
            ),
            if (_editMode)
              IconButton(
                onPressed: _addCharacter,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                tooltip: '인물 추가',
              ),
            if (_editMode)
              IconButton(
                onPressed: _project.characters.isEmpty ? null : _deleteCharacter,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '인물 삭제',
              ),
          ],
        ),
        Expanded(
          child: _project.characters.isEmpty
              ? const _NotenEmptyState(
                  icon: Icons.groups_rounded,
                  title: '등록된 인물이 없습니다',
                  body: '수정 모드를 켜고 인물을 추가하세요.',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _fieldSection(
                      context,
                      title: '기본 정보',
                      icon: Icons.badge_outlined,
                      children: [
                        _field('이름', _charNameCtrl, _updateCharacter),
                        _field('역할', _charRoleCtrl, _updateCharacter),
                        _field('별칭', _charAliasCtrl, _updateCharacter),
                        _field('나이', _charAgeCtrl, _updateCharacter),
                        _field('성별', _charGenderCtrl, _updateCharacter),
                        _field('직업 / 소속', _charJobCtrl, _updateCharacter, last: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _fieldSection(
                      context,
                      title: '인물 설계',
                      icon: Icons.psychology_alt_rounded,
                      children: [
                        _field('외형', _charLookCtrl, _updateCharacter, lines: 4),
                        _field('성격', _charPersonalityCtrl, _updateCharacter, lines: 4),
                        _field('말투', _charSpeechCtrl, _updateCharacter, lines: 4),
                        _field('욕망', _charDesireCtrl, _updateCharacter, lines: 4),
                        _field('약점', _charWeaknessCtrl, _updateCharacter, lines: 4),
                        _field('비밀', _charSecretCtrl, _updateCharacter, lines: 4),
                        _field('성장 arc', _charArcCtrl, _updateCharacter, lines: 4),
                        _field('관계 / 감정선 / 등장 챕터', _charRelationCtrl, _updateCharacter, lines: 6, last: true),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
    if (!wide || _focusMode) return editor;
    return Row(
      children: [
        SizedBox(width: 260, child: _characterSideList()),
        const SizedBox(width: 8),
        Expanded(child: editor),
      ],
    );
  }

  Widget _termWorkspace(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final editor = Column(
      children: [
        _workspaceHeader(
          context,
          title: '용어',
          subtitle: '세계관 고유명사와 설정 용어를 관리합니다.',
          icon: Icons.menu_book_rounded,
          actions: [
            IconButton(
              onPressed: _openTermSelector,
              icon: const Icon(Icons.view_list_rounded),
              tooltip: '용어 선택',
            ),
            if (_editMode)
              IconButton(
                onPressed: _addTerm,
                icon: const Icon(Icons.add_rounded),
                tooltip: '용어 추가',
              ),
            if (_editMode)
              IconButton(
                onPressed: _project.terms.isEmpty ? null : _deleteTerm,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '용어 삭제',
              ),
          ],
        ),
        Expanded(
          child: _project.terms.isEmpty
              ? const _NotenEmptyState(
                  icon: Icons.menu_book_rounded,
                  title: '등록된 용어가 없습니다',
                  body: '수정 모드를 켜고 용어를 추가하세요.',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _fieldSection(
                      context,
                      title: '용어 정보',
                      icon: Icons.menu_book_outlined,
                      children: [
                        _field('용어명', _termNameCtrl, _updateTerm),
                        _field('별칭', _termAliasCtrl, _updateTerm),
                        _field('카테고리', _termCategoryCtrl, _updateTerm),
                        _field('짧은 정의', _termShortCtrl, _updateTerm, last: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _fieldSection(
                      context,
                      title: '상세 설정',
                      icon: Icons.subject_rounded,
                      children: [
                        _field('상세 정의', _termDefinitionCtrl, _updateTerm, lines: 7),
                        _field('작중 사용 방식', _termUsageCtrl, _updateTerm, lines: 5),
                        _field('관련 인물 / 챕터 / 설계 키워드', _termRelatedCtrl, _updateTerm, lines: 4),
                        _field('작가 메모', _termMemoCtrl, _updateTerm, lines: 5, last: true),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
    if (!wide || _focusMode) return editor;
    return Row(
      children: [
        SizedBox(width: 260, child: _termSideList()),
        const SizedBox(width: 8),
        Expanded(child: editor),
      ],
    );
  }

  Widget _fieldSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final tokens = CommonUiTheme.of(context);
    return _NotenListSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: tokens.iconSecondary),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          ...children,
        ],
      ),
    );
  }

  Widget _characterSideList() {
    return _entityList(
      title: '인물 목록',
      count: _project.characters.length,
      add: _editMode ? _addCharacter : null,
      itemBuilder: (index) {
        final character = _project.characters[index];
        return _NotenSelectableRow(
          selected: _characterIndex == index,
          icon: Icons.person_rounded,
          title: character.displayName,
          subtitle: character.role.isEmpty ? '역할 미정' : character.role,
          onTap: () => _selectCharacter(index),
        );
      },
    );
  }

  Widget _termSideList() {
    return _entityList(
      title: '용어 목록',
      count: _project.terms.length,
      add: _editMode ? _addTerm : null,
      itemBuilder: (index) {
        final term = _project.terms[index];
        return _NotenSelectableRow(
          selected: _termIndex == index,
          icon: Icons.menu_book_rounded,
          title: term.displayName,
          subtitle: term.category,
          onTap: () => _selectTerm(index),
        );
      },
    );
  }

  Widget _entityList({
    required String title,
    required int count,
    required Widget Function(int index) itemBuilder,
    VoidCallback? add,
  }) {
    final tokens = CommonUiTheme.of(context);
    return _NotenListSurface(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 5, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (add != null)
                  IconButton(
                    onPressed: add,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: '추가',
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: count == 0
                ? const Center(child: Text('목록 없음'))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: count,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: tokens.borderSubtle,
                    ),
                    itemBuilder: (_, index) => itemBuilder(index),
                  ),
          ),
        ],
      ),
    );
  }

}

enum _NotenFeedbackTone { info, success, warning, danger }

enum _CloudOperation { idle, backup, restore }

enum _ToolActionStatus { none, current, needsBackup, working, failed }

class _NotenFeedback {
  const _NotenFeedback({
    required this.id,
    required this.message,
    required this.tone,
  });

  final int id;
  final String message;
  final _NotenFeedbackTone tone;
}

class _ToolAction {
  const _ToolAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.run,
    this.status = _ToolActionStatus.none,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() run;
  final _ToolActionStatus status;
}

class _NotenRailAction {
  const _NotenRailAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.danger = false,
  }) : divider = false;

  const _NotenRailAction.divider()
      : label = '',
        icon = Icons.remove,
        onTap = null,
        selected = false,
        enabled = false,
        danger = false,
        divider = true;

  final String label;
  final IconData icon;
  final FutureOr<void> Function()? onTap;
  final bool selected;
  final bool enabled;
  final bool danger;
  final bool divider;
}

class _NotenRailButton extends StatefulWidget {
  const _NotenRailButton({
    required this.action,
    required this.extent,
    required this.compact,
  });

  final _NotenRailAction action;
  final double extent;
  final bool compact;

  @override
  State<_NotenRailButton> createState() => _NotenRailButtonState();
}

class _NotenRailButtonState extends State<_NotenRailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final action = widget.action;
    final foreground = action.danger
        ? tokens.danger
        : action.selected
            ? tokens.accent
            : action.enabled
                ? tokens.iconPrimary
                : tokens.iconDisabled;
    final background = action.selected
        ? tokens.accentContainer.withOpacity(.68)
        : _pressed
            ? tokens.surfaceSelected.withOpacity(.52)
            : tokens.surfaceRaised;
    final border = action.selected
        ? tokens.accent.withOpacity(.4)
        : action.danger
            ? tokens.danger.withOpacity(.3)
            : tokens.borderSubtle;
    final core = AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed && action.enabled ? .95 : 1,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        opacity: action.enabled ? 1 : .48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: action.enabled && action.onTap != null
                ? () {
                    HapticFeedback.selectionClick();
                    action.onTap!();
                  }
                : null,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value && action.enabled);
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              height: widget.extent,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .84, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    action.icon,
                    key: ValueKey<String>('${action.label}:${action.selected}:${action.enabled}'),
                    size: widget.compact ? 19 : 20,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: action.selected,
      enabled: action.enabled,
      label: action.label,
      excludeSemantics: true,
      child: Tooltip(message: action.label, child: core),
    );
  }
}

class _NotenListSurface extends StatelessWidget {
  const _NotenListSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: child,
      ),
    );
  }
}

class _NotenSelectableRow extends StatefulWidget {
  const _NotenSelectableRow({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_NotenSelectableRow> createState() => _NotenSelectableRowState();
}

class _NotenSelectableRowState extends State<_NotenSelectableRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: Stack(
            children: [
              AnimatedContainer(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                color: widget.selected
                    ? tokens.accentContainer.withOpacity(.56)
                    : _pressed
                        ? tokens.surfaceSelected.withOpacity(.42)
                        : Colors.transparent,
                padding: const EdgeInsets.fromLTRB(11, 10, 13, 10),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 19,
                      color: widget.selected ? tokens.accent : tokens.iconSecondary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                bottom: 8,
                right: 0,
                child: AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: widget.selected ? 3 : 0,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotenActionRow extends StatefulWidget {
  const _NotenActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  State<_NotenActionRow> createState() => _NotenActionRowState();
}

class _NotenActionRowState extends State<_NotenActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed && widget.enabled ? .985 : 1,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        opacity: widget.enabled ? 1 : .52,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: tokens.iconPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotenDialogShell extends StatelessWidget {
  const _NotenDialogShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    required this.onClose,
    this.trailing,
    this.iconColor,
    this.maxWidth = 560,
    this.maxHeight,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final Widget? trailing;
  final Color? iconColor;
  final double maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight ?? MediaQuery.sizeOf(context).height * .82,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
          border: Border.all(color: tokens.borderStrong),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withOpacity(.2),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Icon(icon, color: iconColor ?? tokens.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: content,
    );
  }
}

class _NotenStatusPill extends StatelessWidget {
  const _NotenStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _NotenEmptyState extends StatelessWidget {
  const _NotenEmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return _NotenListSurface(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: tokens.iconSecondary),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NovelTab { chapters, design, characters, terms }

class _Ids {
  static String newId(String prefix) => '${prefix}_${DateTime
      .now()
      .microsecondsSinceEpoch}_${math
      .Random()
      .nextInt(99999)
      .toString()
      .padLeft(5, '0')}';
}

class _Dates {
  static DateTime? parse(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

class _Project {
  final String id;
  final String title;
  final String genre;
  final String logline;
  final _Design design;
  final List<_Chapter> chapters;
  final List<_Character> characters;
  final List<_Term> terms;
  final List<_Recipient> recipients;
  final String activeChapterId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const _Project(
      {required this.id, required this.title, required this.genre, required this.logline, required this.design, required this.chapters, required this.characters, required this.terms, required this.recipients, required this.activeChapterId, required this.createdAt, required this.updatedAt});

  int get totalCount => chapters.fold(0, (s, c) => s + c.count);

  static _Project seed() {
    final now = DateTime.now();
    final chapter = _Chapter(id: _Ids.newId('chapter'),
        title: 'Chapter 01. 첫 문장',
        body: '비가 멈춘 골목 끝에서, 그녀는 아직 오지 않은 편지의 답장을 기다리고 있었다.\n\n',
        note: '주인공의 결핍과 사건의 첫 단서를 자연스럽게 배치한다.',
        target: 4200,
        order: 0,
        createdAt: now,
        updatedAt: now);
    return _Project(id: _Ids.newId('project'),
        title: '무제 소설',
        genre: '미스터리 판타지',
        logline: '사라지는 기억의 도시에서 잊혀진 진실을 추적하는 이야기.',
        design: _Design.seed(now),
        chapters: [chapter],
        characters: [_Character.seed(now)],
        terms: [_Term.seed(now)],
        recipients: const [],
        activeChapterId: chapter.id,
        createdAt: now,
        updatedAt: now);
  }

  _Project touch() => copyWith(updatedAt: DateTime.now());

  _Project copyWith(
      {String? title, String? genre, String? logline, _Design? design, List<
          _Chapter>? chapters, List<_Character>? characters, List<
          _Term>? terms, List<
          _Recipient>? recipients, String? activeChapterId, DateTime? updatedAt}) {
    return _Project(id: id,
        title: title ?? this.title,
        genre: genre ?? this.genre,
        logline: logline ?? this.logline,
        design: design ?? this.design,
        chapters: chapters ?? this.chapters,
        characters: characters ?? this.characters,
        terms: terms ?? this.terms,
        recipients: recipients ?? this.recipients,
        activeChapterId: activeChapterId ?? this.activeChapterId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt);
  }

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'title': title,
        'genre': genre,
        'logline': logline,
        'design': design.toJson(),
        'chapters': chapters.map((e) => e.toJson()).toList(),
        'characters': characters.map((e) => e.toJson()).toList(),
        'terms': terms.map((e) => e.toJson()).toList(),
        'recipients': recipients.map((e) => e.toJson()).toList(),
        'activeChapterId': activeChapterId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };


  factory _Project.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final chapters = (json['chapters'] as List?)?.whereType<Map>().map((e) =>
        _Chapter.fromJson(Map<String, dynamic>.from(e))).toList() ??
        <_Chapter>[];
    chapters.sort((a, b) => a.order.compareTo(b.order));
    final safeChapters = chapters.isEmpty ? seed().chapters : chapters;
    return _Project(
      id: ((json['id'] as String?) ?? '')
          .trim()
          .isEmpty ? _Ids.newId('project') : (json['id'] as String).trim(),
      title: ((json['title'] as String?) ?? '')
          .trim()
          .isEmpty ? '무제 소설' : (json['title'] as String).trim(),
      genre: (json['genre'] as String?) ?? '',
      logline: (json['logline'] as String?) ?? '',
      design: json['design'] is Map ? _Design.fromJson(
          Map<String, dynamic>.from(json['design'] as Map)) : _Design.seed(now),
      chapters: safeChapters,
      characters: (json['characters'] as List?)?.whereType<Map>().map((e) =>
          _Character.fromJson(Map<String, dynamic>.from(e))).toList() ??
          <_Character>[],
      terms: (json['terms'] as List?)?.whereType<Map>().map((e) =>
          _Term.fromJson(Map<String, dynamic>.from(e))).toList() ?? <_Term>[],
      recipients: (json['recipients'] as List?)?.whereType<Map>().map((e) =>
          _Recipient.fromJson(Map<String, dynamic>.from(e))).where((e) =>
          _Mail.isValid(e.email)).toList() ?? <_Recipient>[],
      activeChapterId: ((json['activeChapterId'] as String?) ?? '')
          .trim()
          .isEmpty ? safeChapters.first.id : (json['activeChapterId'] as String)
          .trim(),
      createdAt: _Dates.parse(json['createdAt']) ?? now,
      updatedAt: _Dates.parse(json['updatedAt']) ?? now,
    );
  }
}

class _Design {
  final String theme, synopsis, world, beginning, development, crisis, climax,
      ending, foreshadow, memo;
  final DateTime createdAt, updatedAt;

  const _Design(
      {required this.theme, required this.synopsis, required this.world, required this.beginning, required this.development, required this.crisis, required this.climax, required this.ending, required this.foreshadow, required this.memo, required this.createdAt, required this.updatedAt});

  static _Design seed(DateTime now) =>
      _Design(theme: '기억은 사라져도 선택의 흔적은 남는다.',
          synopsis: '매달 마지막 밤 기억 일부가 사라지는 도시에서, 주인공은 자신이 잊은 약속과 실종 사건의 연결고리를 추적한다.',
          world: '도시는 기억 소실 현상을 일상으로 받아들이며, 사람들은 중요한 기억을 기록 보관소에 맡긴다.',
          beginning: '기억이 사라진 다음 날, 주인공은 자신에게 온 편지 한 장을 발견한다.',
          development: '편지의 단서를 따라가며 인물들의 감춰진 관계와 도시의 규칙을 확인한다.',
          crisis: '주인공이 되찾으려는 기억이 누군가를 파괴할 수 있다는 사실이 드러난다.',
          climax: '기억을 되찾을지, 모두를 위해 남겨둘지 선택해야 한다.',
          ending: '진실의 일부를 남기고 새로운 기억 방식을 만든다.',
          foreshadow: '파란 우산, 멈춘 시계, 지워진 우편함, 반복되는 같은 문장.',
          memo: '감정선은 조용하게 시작해서 후반부에 폭발시키기.',
          createdAt: now,
          updatedAt: now);

  _Design copyWith(
      {String? theme, String? synopsis, String? world, String? beginning, String? development, String? crisis, String? climax, String? ending, String? foreshadow, String? memo, DateTime? updatedAt}) =>
      _Design(theme: theme ?? this.theme,
          synopsis: synopsis ?? this.synopsis,
          world: world ?? this.world,
          beginning: beginning ?? this.beginning,
          development: development ?? this.development,
          crisis: crisis ?? this.crisis,
          climax: climax ?? this.climax,
          ending: ending ?? this.ending,
          foreshadow: foreshadow ?? this.foreshadow,
          memo: memo ?? this.memo,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt);

  Map<String, dynamic> toJson() =>
      {
        'theme': theme,
        'synopsis': synopsis,
        'world': world,
        'beginning': beginning,
        'development': development,
        'crisis': crisis,
        'climax': climax,
        'ending': ending,
        'foreshadow': foreshadow,
        'memo': memo,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };

  factory _Design.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return _Design(theme: (j['theme'] as String?) ?? '',
        synopsis: (j['synopsis'] as String?) ?? '',
        world: (j['world'] as String?) ?? '',
        beginning: (j['beginning'] as String?) ?? '',
        development: (j['development'] as String?) ?? '',
        crisis: (j['crisis'] as String?) ?? '',
        climax: (j['climax'] as String?) ?? '',
        ending: (j['ending'] as String?) ?? '',
        foreshadow: (j['foreshadow'] as String?) ?? '',
        memo: (j['memo'] as String?) ?? '',
        createdAt: _Dates.parse(j['createdAt']) ?? now,
        updatedAt: _Dates.parse(j['updatedAt']) ?? now);
  }
}

class _Chapter {
  final String id, title, body, note;
  final int target, order;
  final DateTime createdAt, updatedAt;

  const _Chapter(
      {required this.id, required this.title, required this.body, required this.note, required this.target, required this.order, required this.createdAt, required this.updatedAt});

  int get count =>
      body
          .replaceAll(RegExp(r'\s+'), '')
          .runes
          .length;

  _Chapter copyWith(
      {String? title, String? body, String? note, int? target, int? order, DateTime? updatedAt}) =>
      _Chapter(id: id,
          title: title ?? this.title,
          body: body ?? this.body,
          note: note ?? this.note,
          target: target ?? this.target,
          order: order ?? this.order,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt);

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'title': title,
        'body': body,
        'note': note,
        'target': target,
        'order': order,
        'count': count,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };

  factory _Chapter.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return _Chapter(id: ((j['id'] as String?) ?? '')
        .trim()
        .isEmpty ? _Ids.newId('chapter') : (j['id'] as String).trim(),
        title: ((j['title'] as String?) ?? '')
            .trim()
            .isEmpty ? '제목 없는 챕터' : (j['title'] as String),
        body: (j['body'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        target: _Dates.intValue(j['target'], 4000),
        order: _Dates.intValue(j['order'], 0),
        createdAt: _Dates.parse(j['createdAt']) ?? now,
        updatedAt: _Dates.parse(j['updatedAt']) ?? now);
  }
}

class _Character {
  final String id, name, role, alias, age, gender, job, look, personality,
      speech, desire, weakness, secret, arc, relations;
  final DateTime createdAt, updatedAt;

  const _Character(
      {required this.id, required this.name, required this.role, required this.alias, required this.age, required this.gender, required this.job, required this.look, required this.personality, required this.speech, required this.desire, required this.weakness, required this.secret, required this.arc, required this.relations, required this.createdAt, required this.updatedAt});

  String get displayName =>
      name
          .trim()
          .isEmpty ? '새 인물' : name.trim();

  static _Character empty(DateTime now) =>
      _Character(id: _Ids.newId('character'),
          name: '새 인물',
          role: '역할 미정',
          alias: '',
          age: '',
          gender: '',
          job: '',
          look: '',
          personality: '',
          speech: '',
          desire: '',
          weakness: '',
          secret: '',
          arc: '',
          relations: '',
          createdAt: now,
          updatedAt: now);

  static _Character seed(DateTime now) =>
      _Character(id: _Ids.newId('character'),
          name: '윤서',
          role: '주인공',
          alias: '',
          age: '29',
          gender: '',
          job: '기록 보관소 직원',
          look: '검은 코트와 오래된 만년필.',
          personality: '차분하고 관찰력이 좋지만 결정적인 순간에는 충동적으로 움직인다.',
          speech: '짧고 단정한 문장을 쓴다.',
          desire: '잃어버린 약속의 의미를 알고 싶다.',
          weakness: '타인의 기억을 쉽게 믿지 못한다.',
          secret: '기억 소실 현상의 첫 피해자와 관련되어 있다.',
          arc: '기억을 되찾는 사람에서 기억을 선택하는 사람으로 변화한다.',
          relations: '도현: 조력자이지만 진실을 숨긴다.',
          createdAt: now,
          updatedAt: now);

  _Character copyWith(
      {String? name, String? role, String? alias, String? age, String? gender, String? job, String? look, String? personality, String? speech, String? desire, String? weakness, String? secret, String? arc, String? relations, DateTime? updatedAt}) =>
      _Character(id: id,
          name: name ?? this.name,
          role: role ?? this.role,
          alias: alias ?? this.alias,
          age: age ?? this.age,
          gender: gender ?? this.gender,
          job: job ?? this.job,
          look: look ?? this.look,
          personality: personality ?? this.personality,
          speech: speech ?? this.speech,
          desire: desire ?? this.desire,
          weakness: weakness ?? this.weakness,
          secret: secret ?? this.secret,
          arc: arc ?? this.arc,
          relations: relations ?? this.relations,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt);

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'name': name,
        'role': role,
        'alias': alias,
        'age': age,
        'gender': gender,
        'job': job,
        'look': look,
        'personality': personality,
        'speech': speech,
        'desire': desire,
        'weakness': weakness,
        'secret': secret,
        'arc': arc,
        'relations': relations,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };

  factory _Character.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return _Character(id: ((j['id'] as String?) ?? '')
        .trim()
        .isEmpty ? _Ids.newId('character') : (j['id'] as String).trim(),
        name: (j['name'] as String?) ?? '새 인물',
        role: (j['role'] as String?) ?? '',
        alias: (j['alias'] as String?) ?? '',
        age: (j['age'] as String?) ?? '',
        gender: (j['gender'] as String?) ?? '',
        job: (j['job'] as String?) ?? '',
        look: (j['look'] as String?) ?? '',
        personality: (j['personality'] as String?) ?? '',
        speech: (j['speech'] as String?) ?? '',
        desire: (j['desire'] as String?) ?? '',
        weakness: (j['weakness'] as String?) ?? '',
        secret: (j['secret'] as String?) ?? '',
        arc: (j['arc'] as String?) ?? '',
        relations: (j['relations'] as String?) ?? '',
        createdAt: _Dates.parse(j['createdAt']) ?? now,
        updatedAt: _Dates.parse(j['updatedAt']) ?? now);
  }
}

class _Term {
  final String id, name, aliases, category, shortDefinition, definition, usage,
      related, memo;
  final DateTime createdAt, updatedAt;

  const _Term(
      {required this.id, required this.name, required this.aliases, required this.category, required this.shortDefinition, required this.definition, required this.usage, required this.related, required this.memo, required this.createdAt, required this.updatedAt});

  String get displayName =>
      name
          .trim()
          .isEmpty ? '새 용어' : name.trim();

  static _Term empty(DateTime now) =>
      _Term(id: _Ids.newId('term'),
          name: '새 용어',
          aliases: '',
          category: '일반',
          shortDefinition: '',
          definition: '',
          usage: '',
          related: '',
          memo: '',
          createdAt: now,
          updatedAt: now);

  static _Term seed(DateTime now) =>
      _Term(id: _Ids.newId('term'),
          name: '기억세',
          aliases: '망각세, 기록세',
          category: '사회 제도',
          shortDefinition: '기억 보관소 이용료 대신 도시가 징수하는 세금.',
          definition: '중요한 기억을 공식 보관소에 맡길 때 납부하는 비용 체계다.',
          usage: '도시의 계급 구조와 기억 상실 문제를 드러내는 장치다.',
          related: '윤서, 기록 보관소, Chapter 01',
          memo: '후반부 권력 구조와 연결한다.',
          createdAt: now,
          updatedAt: now);

  _Term copyWith(
      {String? name, String? aliases, String? category, String? shortDefinition, String? definition, String? usage, String? related, String? memo, DateTime? updatedAt}) =>
      _Term(id: id,
          name: name ?? this.name,
          aliases: aliases ?? this.aliases,
          category: category ?? this.category,
          shortDefinition: shortDefinition ?? this.shortDefinition,
          definition: definition ?? this.definition,
          usage: usage ?? this.usage,
          related: related ?? this.related,
          memo: memo ?? this.memo,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt);

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'name': name,
        'aliases': aliases,
        'category': category,
        'shortDefinition': shortDefinition,
        'definition': definition,
        'usage': usage,
        'related': related,
        'memo': memo,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };

  factory _Term.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return _Term(id: ((j['id'] as String?) ?? '')
        .trim()
        .isEmpty ? _Ids.newId('term') : (j['id'] as String).trim(),
        name: (j['name'] as String?) ?? '새 용어',
        aliases: (j['aliases'] as String?) ?? '',
        category: (j['category'] as String?) ?? '일반',
        shortDefinition: (j['shortDefinition'] as String?) ?? '',
        definition: (j['definition'] as String?) ?? '',
        usage: (j['usage'] as String?) ?? '',
        related: (j['related'] as String?) ?? '',
        memo: (j['memo'] as String?) ?? '',
        createdAt: _Dates.parse(j['createdAt']) ?? now,
        updatedAt: _Dates.parse(j['updatedAt']) ?? now);
  }
}

class _Recipient {
  final String id, email, label;
  final bool selected;
  final DateTime createdAt, updatedAt;

  const _Recipient(
      {required this.id, required this.email, required this.label, required this.selected, required this.createdAt, required this.updatedAt});

  _Recipient copyWith({bool? selected, DateTime? updatedAt}) =>
      _Recipient(id: id,
          email: email,
          label: label,
          selected: selected ?? this.selected,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt);

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'email': email,
        'label': label,
        'selected': selected,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };

  factory _Recipient.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    final email = ((j['email'] as String?) ?? '').trim().toLowerCase();
    return _Recipient(id: ((j['id'] as String?) ?? '')
        .trim()
        .isEmpty ? _Ids.newId('recipient') : (j['id'] as String).trim(),
        email: email,
        label: ((j['label'] as String?) ?? '')
            .trim()
            .isEmpty ? _Mail.label(email) : (j['label'] as String).trim(),
        selected: j['selected'] != false,
        createdAt: _Dates.parse(j['createdAt']) ?? now,
        updatedAt: _Dates.parse(j['updatedAt']) ?? now);
  }
}

class _LocalStore {
  static const key = 'notensystem_project_v1';
  static const preRestoreKey = 'notensystem_pre_restore_v1';

  static Future<_Project> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return _Project.seed();
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        return _Project.fromJson(Map<String, dynamic>.from(parsed));
      }
    } catch (_) {}
    return _Project.seed();
  }

  static Future<void> save(_Project project) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(project.toJson()));
  }

  static Future<void> savePreRestore(_Project project) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preRestoreKey, jsonEncode(project.toJson()));
  }

  static Future<_Project?> loadPreRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preRestoreKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        return _Project.fromJson(Map<String, dynamic>.from(parsed));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> hasPreRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preRestoreKey);
    return raw != null && raw.trim().isNotEmpty;
  }
}

class _Export {
  static String safeName(String value) =>
      (value
          .trim()
          .isEmpty ? 'notensystem' : value.trim()).replaceAll(
          RegExp(r'[\\/:*?"<>|]+'), '_').replaceAll(RegExp(r'\s+'), '_');

  static String compact(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}_${_two(d.hour)}${_two(
          d.minute)}';

  static String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String dt(DateTime d) => '${ymd(d)} ${_two(d.hour)}:${_two(d.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String markdown(_Project p, DateTime exportedAt) {
    final b = StringBuffer();
    b.writeln('# ${p.title}');
    b.writeln();
    b.writeln('- 장르: ${p.genre}');
    b.writeln('- 로그라인: ${p.logline}');
    b.writeln('- 생성: ${dt(p.createdAt)}');
    b.writeln('- 수정: ${dt(p.updatedAt)}');
    b.writeln('- 내보내기: ${dt(exportedAt)}');
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('## 설계');
    _md(b, '핵심 주제', p.design.theme);
    _md(b, '전체 시놉시스', p.design.synopsis);
    _md(b, '세계관', p.design.world);
    _md(b, '발단', p.design.beginning);
    _md(b, '전개', p.design.development);
    _md(b, '위기', p.design.crisis);
    _md(b, '절정', p.design.climax);
    _md(b, '결말', p.design.ending);
    _md(b, '복선', p.design.foreshadow);
    _md(b, '작가 메모', p.design.memo);
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('## 인물');
    for (final c in p.characters) {
      b.writeln();
      b.writeln('### ${c.displayName}');
      b.writeln('- 역할: ${c.role}');
      b.writeln('- 별칭: ${c.alias}');
      b.writeln('- 나이: ${c.age}');
      b.writeln('- 성별: ${c.gender}');
      b.writeln('- 직업/소속: ${c.job}');
      _md(b, '외형', c.look);
      _md(b, '성격', c.personality);
      _md(b, '말투', c.speech);
      _md(b, '욕망', c.desire);
      _md(b, '약점', c.weakness);
      _md(b, '비밀', c.secret);
      _md(b, '성장 arc', c.arc);
      _md(b, '관계', c.relations);
    }
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('## 용어');
    for (final t in p.terms) {
      b.writeln();
      b.writeln('### ${t.displayName}');
      b.writeln('- 카테고리: ${t.category}');
      b.writeln('- 별칭: ${t.aliases}');
      b.writeln('- 짧은 정의: ${t.shortDefinition}');
      _md(b, '상세 정의', t.definition);
      _md(b, '작중 사용 방식', t.usage);
      _md(b, '관련 항목', t.related);
      _md(b, '메모', t.memo);
    }
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('## 챕터');
    for (final c in p.chapters) {
      b.writeln();
      b.writeln('### ${c.title}');
      b.writeln('- 목표: ${c.target}자');
      b.writeln('- 현재: ${c.count}자');
      _md(b, '챕터 메모', c.note);
      b.writeln();
      b.writeln(c.body
          .trim()
          .isEmpty ? '_본문이 비어 있습니다._' : c.body.trim());
    }
    return b.toString();
  }

  static void _md(StringBuffer b, String title, String value) {
    b.writeln();
    b.writeln('#### $title');
    b.writeln();
    b.writeln(value
        .trim()
        .isEmpty ? '_비어 있음_' : value.trim());
  }

  static Future<Uint8List> pdf(_Project p, DateTime exportedAt) async {
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = pw.Font.ttf(await rootBundle.load(
          'assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf'));
    } catch (_) {}
    try {
      bold = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf'));
    } catch (_) {
      bold = regular;
    }
    final theme = regular == null ? pw.ThemeData.base() : pw.ThemeData.withFont(
        base: regular,
        bold: bold ?? regular,
        italic: regular,
        boldItalic: bold ?? regular);
    final doc = pw.Document();
    const ink = PdfColor.fromInt(0xff111827);
    const muted = PdfColor.fromInt(0xff6b7280);
    const line = PdfColor.fromInt(0xffd1d5db);
    const accent = PdfColor.fromInt(0xff2563eb);
    pw.TextStyle h(double size) =>
        pw.TextStyle(
            fontSize: size, color: ink, fontWeight: pw.FontWeight.bold);
    pw.TextStyle body(double size, {PdfColor color = ink}) =>
        pw.TextStyle(fontSize: size, color: color, height: 1.45);
    pw.Widget block(String title, String value) =>
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 11),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title, style: h(12)),
                  pw.SizedBox(height: 4),
                  pw.Text(value
                      .trim()
                      .isEmpty ? '비어 있음' : value.trim(),
                      style: body(10.5, color: value
                          .trim()
                          .isEmpty ? muted : ink))
                ]));
    pw.Widget footer(pw.Context ctx) =>
        pw.Container(padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: line, width: .6))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(p.title, style: body(8, color: muted)),
                  pw.Text('${dt(exportedAt)} · ${ctx.pageNumber} / ${ctx
                      .pagesCount}', style: body(8, color: muted))
                ]));

    doc.addPage(pw.Page(theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        build: (_) =>
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTENSYSTEM NOVEL PACKAGE', style: pw.TextStyle(
                      fontSize: 10,
                      color: accent,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2)),
                  pw.SizedBox(height: 32),
                  pw.Text(p.title, style: h(34)),
                  pw.SizedBox(height: 12),
                  pw.Text(p.logline
                      .trim()
                      .isEmpty ? '로그라인 없음' : p.logline.trim(),
                      style: body(13, color: muted)),
                  pw.SizedBox(height: 28),
                  pw.Text('장르: ${p.genre}', style: body(11)),
                  pw.Text('챕터: ${p.chapters.length}개 · 인물: ${p.characters
                      .length}명 · 용어: ${p.terms.length}개 · 본문: ${p
                      .totalCount}자', style: body(11)),
                  pw.Text(
                      '내보내기: ${dt(exportedAt)}', style: body(11, color: muted))
                ])));

    doc.addPage(pw.MultiPage(theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        footer: footer,
        build: (_) =>
        [
          pw.Text('설계', style: h(24)),
          pw.SizedBox(height: 14),
          block('핵심 주제', p.design.theme),
          block('전체 시놉시스', p.design.synopsis),
          block('세계관', p.design.world),
          block('발단', p.design.beginning),
          block('전개', p.design.development),
          block('위기', p.design.crisis),
          block('절정', p.design.climax),
          block('결말', p.design.ending),
          block('복선', p.design.foreshadow),
          block('작가 메모', p.design.memo)
        ]));

    doc.addPage(pw.MultiPage(theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        footer: footer,
        build: (_) =>
        [
          pw.Text('인물', style: h(24)),
          pw.SizedBox(height: 14),
          for (final c in p.characters) ...[
            pw.Text(c.displayName, style: h(16)),
            pw.Text('역할: ${c.role} · 별칭: ${c.alias} · 나이: ${c.age} · 직업/소속: ${c
                .job}', style: body(9.5, color: muted)),
            pw.SizedBox(height: 6),
            block('외형', c.look),
            block('성격', c.personality),
            block('말투', c.speech),
            block('욕망 / 약점 / 비밀', '${c.desire}\n${c.weakness}\n${c.secret}'),
            block('성장 arc / 관계', '${c.arc}\n${c.relations}'),
            pw.Container(height: .8, color: line),
            pw.SizedBox(height: 12)
          ]
        ]));

    doc.addPage(pw.MultiPage(theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        footer: footer,
        build: (_) =>
        [
          pw.Text('용어', style: h(24)),
          pw.SizedBox(height: 14),
          for (final t in p.terms) ...[
            pw.Text(t.displayName, style: h(15)),
            pw.Text('${t.category} · 별칭: ${t.aliases}',
                style: body(9.5, color: muted)),
            pw.SizedBox(height: 6),
            block('짧은 정의', t.shortDefinition),
            block('상세 정의', t.definition),
            block('사용 방식', t.usage),
            block('관련 항목 / 메모', '${t.related}\n${t.memo}'),
            pw.Container(height: .8, color: line),
            pw.SizedBox(height: 12)
          ]
        ]));

    for (final c in p.chapters) {
      doc.addPage(pw.MultiPage(theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
          footer: footer,
          build: (_) =>
          [
            pw.Text(c.title, style: h(20)),
            pw.SizedBox(height: 4),
            pw.Text('${c.count}자 · 목표 ${c.target}자',
                style: body(9.5, color: muted)),
            if (c.note
                .trim()
                .isNotEmpty) block('챕터 메모', c.note),
            pw.SizedBox(height: 12),
            pw.Text(c.body
                .trim()
                .isEmpty ? '본문이 비어 있습니다.' : c.body.trim(), style: body(11.5))
          ]));
    }
    return doc.save();
  }
}

class _Mail {
  static bool isValid(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

  static String label(String email) =>
      email
          .split('@')
          .first
          .trim()
          .isEmpty ? email : email
          .split('@')
          .first
          .trim();

  static String mime(
      {required String toCsv, required String subject, required String bodyText, required String pdfName, required Uint8List pdfBytes, required String markdownName, required String markdownText, required String boundary}) {
    const crlf = '\r\n';
    final pdf = _wrap(base64.encode(pdfBytes));
    final md = _wrap(base64.encode(utf8.encode(markdownText)));
    final body = _wrap(base64.encode(utf8.encode(bodyText)));
    final buffer = StringBuffer()
      ..write('MIME-Version: 1.0$crlf')..write('To: $toCsv$crlf')..write(
          'Subject: =?UTF-8?B?${base64.encode(
              utf8.encode(subject))}?=$crlf')..write(
          'Content-Type: multipart/mixed; boundary="$boundary"$crlf')..write(
          crlf)..write('--$boundary$crlf')..write(
          'Content-Type: text/plain; charset="utf-8"$crlf')..write(
          'Content-Transfer-Encoding: base64$crlf')..write(crlf)..write(
          body)..write(crlf)..write('--$boundary$crlf')..write(
          'Content-Type: application/pdf; name="$pdfName"$crlf')..write(
          'Content-Disposition: attachment; filename="$pdfName"$crlf')..write(
          'Content-Transfer-Encoding: base64$crlf')..write(crlf)..write(
          pdf)..write(crlf)..write('--$boundary$crlf')..write(
          'Content-Type: text/markdown; charset="utf-8"; name="$markdownName"$crlf')..write(
          'Content-Disposition: attachment; filename="$markdownName"$crlf')..write(
          'Content-Transfer-Encoding: base64$crlf')..write(crlf)..write(
          md)..write(crlf)..write('--$boundary--$crlf');
    return buffer.toString();
  }

  static String _wrap(String value) {
    final b = StringBuffer();
    for (var i = 0; i < value.length; i += 76) {
      b.writeln(value.substring(i, math.min(i + 76, value.length)));
    }
    return b.toString().trimRight();
  }
}
