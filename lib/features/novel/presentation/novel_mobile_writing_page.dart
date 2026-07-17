import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../selector/application/dev_auth.dart';

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
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await DevAuth.isDeveloperLoggedIn();
    final loaded = await _LocalStore.load();
    if (!mounted) return;
    setState(() {
      _authorized = ok;
      _project = loaded;
      _checking = false;
      _chapterIndex = _safeIndex(
          _project.chapters.indexWhere((e) => e.id == _project.activeChapterId),
          _project.chapters.length);
      _characterIndex = _project.characters.isEmpty ? -1 : 0;
      _termIndex = _project.terms.isEmpty ? -1 : 0;
    });
    _loadAllControllers();
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
    if (!_saving) setState(() => _saving = true);
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveLocal);
  }

  Future<void> _saveLocal() async {
    _saveTimer?.cancel();
    final next = _project.touch();
    _project = next;
    await _LocalStore.save(next);
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
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final cs = Theme
            .of(sheetContext)
            .colorScheme;
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery
                .of(sheetContext)
                .size
                .height * .72),
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: cs.outlineVariant.withOpacity(.6))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                  child: Row(
                    children: [
                      CircleAvatar(backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                          child: const Icon(Icons.article_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment
                              .start, children: [
                            Text('챕터 선택', style: Theme
                                .of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text('다른 챕터로 이동하거나 새 챕터를 추가합니다.', style: Theme
                                .of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant))
                          ])),
                      if (_editMode) IconButton.filledTonal(onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _addChapter();
                      }, icon: const Icon(Icons.add_rounded), tooltip: '챕터 추가'),
                      IconButton(onPressed: () =>
                          Navigator
                              .of(sheetContext)
                              .pop(), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(.55)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                    itemCount: _project.chapters.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final chapter = _project.chapters[i];
                      final selectedChapter = i == _chapterIndex;
                      return ListTile(
                        selected: selectedChapter,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        tileColor: selectedChapter ? cs.primaryContainer : cs
                            .surfaceContainerHighest.withOpacity(.42),
                        selectedTileColor: cs.primaryContainer,
                        leading: CircleAvatar(
                            backgroundColor: selectedChapter ? cs.primary : cs
                                .surfaceContainerHighest,
                            foregroundColor: selectedChapter ? cs.onPrimary : cs
                                .onSurfaceVariant,
                            child: Text('${i + 1}')),
                        title: Text(chapter.title, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w900,
                                color: selectedChapter
                                    ? cs.onPrimaryContainer
                                    : cs.onSurface)),
                        subtitle: Text('${chapter.count}자 · 목표 ${chapter
                            .target} · ${chapter.note
                            .trim()
                            .isEmpty ? '메모 없음' : chapter.note.trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: selectedChapter ? cs.onPrimaryContainer
                                    .withOpacity(.75) : cs.onSurfaceVariant)),
                        trailing: Icon(
                            selectedChapter ? Icons.check_circle_rounded : Icons
                                .chevron_right_rounded,
                            color: selectedChapter ? cs.primary : cs
                                .onSurfaceVariant),
                        onTap: () => Navigator.of(sheetContext).pop(i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) _selectChapter(selected);
  }

  void _selectCharacter(int index) {
    if (index < 0 || index >= _project.characters.length) return;
    setState(() {
      _characterIndex = index;
      _tab = _NovelTab.characters;
    });
    _loadCharacter();
  }

  void _selectTerm(int index) {
    if (index < 0 || index >= _project.terms.length) return;
    setState(() {
      _termIndex = index;
      _tab = _NovelTab.terms;
    });
    _loadTerm();
  }

  void _addChapter() {
    if (!_editMode) return;
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
      _snack('최소 1개의 챕터는 필요합니다.');
      return;
    }
    final ok = await _confirm('챕터 삭제', '현재 챕터를 삭제하시겠습니까?');
    if (ok != true) return;
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
    _snack(_editMode ? '수정 모드가 켜졌습니다.' : '수정 모드가 꺼졌습니다.');
  }

  Future<void> _exit() async {
    await _saveLocal();
    final ok = await _confirm('notensystem 종료', '현재 화면을 종료하시겠습니까?');
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('취소')),
              FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('확인')),
            ],
          ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600)));
  }

  Future<void> _run(String title, Future<String> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _saveLocal();
      final msg = await task();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) =>
            AlertDialog(
              icon: const Icon(Icons.check_circle_rounded),
              title: Text(title),
              content: Text(msg),
              actions: [
                FilledButton(onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('확인'))
              ],
            ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) =>
            AlertDialog(
              icon: const Icon(Icons.error_rounded),
              title: const Text('작업 실패'),
              content: Text('$e'),
              actions: [
                FilledButton(onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('확인'))
              ],
            ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTools() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme
            .of(ctx)
            .colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery
              .of(ctx)
              .viewInsets
              .bottom + 12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 760),
            decoration: BoxDecoration(color: cs.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: cs.outlineVariant.withOpacity(.6))),
            child: Column(
              children: [
                _SheetTitle(title: '저장 · 전송 · Firebase',
                    subtitle: '로컬 저장, PDF/Markdown Gmail 전송, 영역별 Firebase 관리를 실행합니다.'),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    children: [
                      _action(Icons.save_rounded, '로컬 저장',
                          '기기에 현재 프로젝트를 저장합니다.', () =>
                              _run('로컬 저장 완료', () async {
                                await _saveLocal();
                                return '기기에 저장했습니다.';
                              })),
                      _action(Icons.people_alt_rounded, '수신자 보관함',
                          '전송 대상 이메일을 관리합니다.', () => _openRecipients()),
                      _action(
                          Icons.attach_email_rounded, 'PDF + Markdown Gmail 전송',
                          '설계, 인물, 용어, 챕터를 문서로 만들어 전송합니다.', _sendMail),
                      _sectionLabel('Firebase 전체 관리'),
                      _action(Icons.cloud_upload_rounded, '전체 Firebase 저장',
                          '프로젝트, 설계, 챕터, 인물, 용어, 수신자를 저장합니다.', () =>
                              _run('Firebase 저장 완료', () async {
                                await _Remote.pushAll(_project);
                                return '전체 데이터를 저장했습니다.\n${_Remote.projectPath(
                                    _project.id)}';
                              })),
                      _action(Icons.cloud_download_rounded, '전체 Firebase 가져오기',
                          '원격 전체 데이터를 로컬에 반영합니다.', () async {
                            final ok = await _confirm('전체 가져오기',
                                'Firebase 원격본으로 로컬 notensystem 데이터를 덮어쓸까요?');
                            if (ok == true) {
                              await _run('Firebase 가져오기 완료', () async {
                                final p = await _Remote.pullAll(_project.id);
                                _applyPulledProject(p);
                                return '${p.title} 전체 데이터를 가져왔습니다.';
                              });
                            }
                          }),
                      _sectionLabel('Firebase 영역별 관리'),
                      _remoteRow('설계 저장', '설계 가져오기', () =>
                          _run('설계 저장 완료', () async {
                            await _Remote.pushDesign(_project);
                            return '설계 데이터를 저장했습니다.';
                          }), () =>
                          _run('설계 가져오기 완료', () async {
                            final d = await _Remote.pullDesign(_project.id);
                            _setProject(
                                _project.copyWith(design: d), save: false);
                            _loadDesign();
                            await _saveLocal();
                            return '설계 데이터를 가져왔습니다.';
                          })),
                      _remoteRow('챕터 전체 저장', '챕터 전체 가져오기', () =>
                          _run('챕터 저장 완료', () async {
                            await _Remote.pushChapters(_project);
                            return '챕터 ${_project.chapters.length}개를 저장했습니다.';
                          }), () =>
                          _run('챕터 가져오기 완료', () async {
                            final items = await _Remote.pullChapters(
                                _project.id);
                            if (items.isEmpty) throw StateError(
                                '가져올 챕터가 없습니다.');
                            _setProject(_project.copyWith(chapters: items,
                                activeChapterId: items.first.id), save: false);
                            _chapterIndex = 0;
                            _loadChapter();
                            await _saveLocal();
                            return '챕터 ${items.length}개를 가져왔습니다.';
                          })),
                      _remoteRow('현재 챕터 저장', '현재 챕터 가져오기', () =>
                          _run('현재 챕터 저장 완료', () async {
                            final c = _chapter;
                            if (c == null) throw StateError('선택된 챕터가 없습니다.');
                            await _Remote.pushChapter(_project, c);
                            return '${c.title} 챕터를 저장했습니다.';
                          }), () =>
                          _run('현재 챕터 가져오기 완료', () async {
                            final c = _chapter;
                            if (c == null) throw StateError('선택된 챕터가 없습니다.');
                            final pulled = await _Remote.pullChapter(
                                _project.id, c.id);
                            final list = List<_Chapter>.from(_project.chapters);
                            final idx = list.indexWhere((e) =>
                            e.id == pulled.id);
                            if (idx < 0) {
                              list.add(pulled);
                              _chapterIndex = list.length - 1;
                            } else {
                              list[idx] = pulled;
                              _chapterIndex = idx;
                            }
                            _setProject(_project.copyWith(
                                chapters: list, activeChapterId: pulled.id),
                                save: false);
                            _loadChapter();
                            await _saveLocal();
                            return '${pulled.title} 챕터를 가져왔습니다.';
                          })),
                      _remoteRow('인물 저장', '인물 가져오기', () =>
                          _run('인물 저장 완료', () async {
                            await _Remote.pushCharacters(_project);
                            return '인물 ${_project.characters.length}명을 저장했습니다.';
                          }), () =>
                          _run('인물 가져오기 완료', () async {
                            final items = await _Remote.pullCharacters(
                                _project.id);
                            _setProject(_project.copyWith(characters: items),
                                save: false);
                            _characterIndex = _safeIndex(0, items.length);
                            _loadCharacter();
                            await _saveLocal();
                            return '인물 ${items.length}명을 가져왔습니다.';
                          })),
                      _remoteRow('용어 저장', '용어 가져오기', () =>
                          _run('용어 저장 완료', () async {
                            await _Remote.pushTerms(_project);
                            return '용어 ${_project.terms.length}개를 저장했습니다.';
                          }), () =>
                          _run('용어 가져오기 완료', () async {
                            final items = await _Remote.pullTerms(_project.id);
                            _setProject(
                                _project.copyWith(terms: items), save: false);
                            _termIndex = _safeIndex(0, items.length);
                            _loadTerm();
                            await _saveLocal();
                            return '용어 ${items.length}개를 가져왔습니다.';
                          })),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String title, String subtitle,
      Future<void> Function() onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: _busy ? null : () async {
          Navigator.of(context).maybePop();
          await onTap();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: Theme
            .of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(.42),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _remoteRow(String left, String right, Future<void> Function() onLeft,
      Future<void> Function() onRight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : onLeft,
              icon: const Icon(Icons.upload_rounded),
              label: Text(left))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : onRight,
              icon: const Icon(Icons.download_rounded),
              label: Text(right))),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  void _applyPulledProject(_Project p) {
    setState(() {
      _project = p;
      _chapterIndex = _safeIndex(
          _project.chapters.indexWhere((e) => e.id == _project.activeChapterId),
          _project.chapters.length);
      _characterIndex = _safeIndex(0, _project.characters.length);
      _termIndex = _safeIndex(0, _project.terms.length);
    });
    _loadAllControllers();
    _queueSave();
  }

  Future<void> _openRecipients() async {
    _recipientCtrl.clear();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          StatefulBuilder(
            builder: (ctx, setSheet) {
              final cs = Theme
                  .of(ctx)
                  .colorScheme;
              return Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery
                    .of(ctx)
                    .viewInsets
                    .bottom + 12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 640),
                  decoration: BoxDecoration(color: cs.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: cs.outlineVariant.withOpacity(.6))),
                  child: Column(
                    children: [
                      _SheetTitle(title: '수신자 보관함',
                          subtitle: 'PDF와 Markdown을 받을 이메일을 관리합니다.'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: Row(
                          children: [
                            Expanded(child: TextField(
                                controller: _recipientCtrl,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                    labelText: '이메일',
                                    border: OutlineInputBorder(),
                                    isDense: true))),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                final email = _recipientCtrl.text
                                    .trim()
                                    .toLowerCase();
                                if (!_Mail.isValid(email)) {
                                  _snack('이메일 형식을 확인하세요.');
                                  return;
                                }
                                if (_project.recipients.any((e) =>
                                e.email == email)) {
                                  _snack('이미 등록된 이메일입니다.');
                                  return;
                                }
                                final now = DateTime.now();
                                final list = List<_Recipient>.from(
                                    _project.recipients)
                                  ..add(_Recipient(id: _Ids.newId('recipient'),
                                      email: email,
                                      label: _Mail.label(email),
                                      selected: true,
                                      createdAt: now,
                                      updatedAt: now));
                                setState(() =>
                                _project = _project
                                    .copyWith(recipients: list)
                                    .touch());
                                setSheet(() {});
                                _recipientCtrl.clear();
                                _queueSave();
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('추가'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _project.recipients.isEmpty
                            ? const Center(child: Text('등록된 수신자가 없습니다.'))
                            : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                          itemCount: _project.recipients.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                          itemBuilder: (ctx, i) {
                            final r = _project.recipients[i];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              tileColor: cs.surfaceContainerHighest.withOpacity(
                                  .42),
                              leading: Checkbox(
                                value: r.selected,
                                onChanged: (v) {
                                  final list = List<_Recipient>.from(
                                      _project.recipients);
                                  list[i] = r.copyWith(selected: v == true,
                                      updatedAt: DateTime.now());
                                  setState(() =>
                                  _project = _project
                                      .copyWith(recipients: list)
                                      .touch());
                                  setSheet(() {});
                                  _queueSave();
                                },
                              ),
                              title: Text(r.email, maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(r.label),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () {
                                  final list = List<_Recipient>.from(
                                      _project.recipients)
                                    ..removeAt(i);
                                  setState(() =>
                                  _project = _project
                                      .copyWith(recipients: list)
                                      .touch());
                                  setSheet(() {});
                                  _queueSave();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _sendMail() async {
    final selected = _project.recipients.where((e) =>
    e.selected && _Mail.isValid(e.email)).toList();
    if (selected.isEmpty) {
      _snack('수신자 보관함에서 이메일을 선택하세요.');
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
      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      await api.users.messages.send(gmail.Message()
        ..raw = base64UrlEncode(utf8.encode(rawMime)).replaceAll('=', ''),
          'me');
      return '${selected.length}명에게 PDF와 Markdown을 전송했습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _snack('뒤로가기로는 종료되지 않습니다. 상단의 종료 버튼을 사용하세요.');
        return false;
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    if (_checking) return Scaffold(backgroundColor: cs.surface,
        body: const Center(child: CircularProgressIndicator()));
    if (!_authorized) return _locked(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      body: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _focusMode ? [cs.surface, cs.surface] : [
                Color.alphaBlend(
                    cs.primaryContainer.withOpacity(.24), cs.surface),
                cs.surface,
                Color.alphaBlend(
                    cs.secondaryContainer.withOpacity(.14), cs.surface)
              ],
            ),
          ),
          child: Column(
            children: [
              _header(context),
              Expanded(child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: _workspace(context))),
              _metaBar(context),
              if (!(_focusMode && MediaQuery
                  .of(context)
                  .viewInsets
                  .bottom > 0)) _bottomNav(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locked(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 56, color: cs.primary),
                const SizedBox(height: 16),
                Text('개발자 모드가 필요합니다', style: Theme
                    .of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('notensystem은 개발자 모드에서 정확한 검색 명령으로만 진입할 수 있습니다.',
                    textAlign: TextAlign.center, style: Theme
                        .of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(onPressed: _exit,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('종료')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: cs.surface.withOpacity(.86),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withOpacity(.6))),
      child: Row(
        children: [
          FilledButton.tonalIcon(onPressed: _exit,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('종료')),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              readOnly: !_editMode,
              maxLines: 1,
              onChanged: (_) => _updateMeta(),
              decoration: const InputDecoration(border: InputBorder.none,
                  isDense: true,
                  prefixIcon: Icon(Icons.auto_stories_rounded),
),
              style: Theme
                  .of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 6),
          _chip(context,
              _saving ? Icons.sync_rounded : Icons.check_circle_rounded,
              _saving ? '저장 중' : '저장됨',
              _saving ? cs.tertiaryContainer : cs.secondaryContainer),
          const SizedBox(width: 4),
          IconButton.filledTonal(onPressed: _toggleEdit,
              icon: Icon(
                  _editMode ? Icons.edit_rounded : Icons.lock_outline_rounded),
              tooltip: _editMode ? '수정 모드 끄기' : '수정 모드 켜기'),
          IconButton.filledTonal(
              onPressed: () => setState(() => _focusMode = !_focusMode),
              icon: Icon(_focusMode ? Icons.fullscreen_exit_rounded : Icons
                  .center_focus_strong_rounded),
              tooltip: '집중 모드'),
          IconButton.filledTonal(onPressed: _busy ? null : _openTools,
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: '저장·전송·Firebase'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color color) {
    final on = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: on),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900, color: on))
          ]),
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
      case _NovelTab.edit:
        return _chapterWorkspace(context);
    }
  }

  Widget _panel(BuildContext context, String title, String subtitle,
      IconData icon, Widget child, {List<Widget> actions = const []}) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface.withOpacity(.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant.withOpacity(.62))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                    child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme
                              .of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant))
                    ])),
                ...actions,
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.55)),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      VoidCallback onChanged, {int lines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        readOnly: !_editMode,
        maxLines: lines,
        keyboardType: keyboard,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(labelText: label,
            alignLabelWithHint: lines > 1,
            border: const OutlineInputBorder(),
            isDense: true,
            filled: !_editMode),
      ),
    );
  }

  Widget _chapterWorkspace(BuildContext context) {
    final wide = MediaQuery
        .of(context)
        .size
        .width >= 760;
    final editor = _panel(
      context,
      '챕터',
      '챕터별 원고, 목표 글자, 장면 메모를 관리합니다.',
      Icons.article_rounded,
      Column(
        children: [
          if (!wide && !_focusMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(height: 96, child: _chapterHorizontalList()),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                    child: _field('챕터 제목', _chapterTitleCtrl, _updateChapter)),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _openChapterSelector,
                    icon: const Icon(Icons.view_list_rounded),
                    tooltip: '챕터 선택'),
                if (_editMode) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(onPressed: _addChapter,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: '챕터 추가'),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(onPressed: _deleteChapter,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: '챕터 삭제'),
                ],
              ],
            ),
          ),
          if (!_focusMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Row(children: [
                SizedBox(width: 120,
                    child: _field('목표 글자', _chapterTargetCtrl, _updateChapter,
                        keyboard: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: _field('챕터 메모', _chapterNoteCtrl, _updateChapter)),
              ]),
            ),
          Expanded(
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
              decoration: InputDecoration(

                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 24)),
              style: Theme
                  .of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.75, fontSize: 17),
            ),
          ),
        ],
      ),
    );
    if (!wide) return editor;
    return Row(children: [
      SizedBox(width: 260, child: _chapterList()),
      const SizedBox(width: 10),
      Expanded(child: editor)
    ]);
  }

  Widget _chapterList() {
    return _sideList(
      title: '챕터 목록',
      add: _editMode ? _addChapter : null,
      count: _project.chapters.length,
      item: (i) =>
          _listTile(_chapterIndex == i, _project.chapters[i].title,
              '${_project.chapters[i].count}자 · 목표 ${_project.chapters[i]
                  .target}', Icons.article_rounded, () => _selectChapter(i)),
    );
  }

  Widget _designWorkspace(BuildContext context) {
    return _panel(
      context,
      '설계',
      '기본 정보, 세계관, 5막 플롯, 복선, 작가 메모를 관리합니다.',
      Icons.architecture_rounded,
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _label('기본 정보'),
          _field('장르', _genreCtrl, _updateMeta),
          _field('로그라인', _loglineCtrl, _updateMeta, lines: 2),
          _field('핵심 주제', _themeCtrl, _updateDesign, lines: 3),
          _field('전체 시놉시스', _synopsisCtrl, _updateDesign, lines: 6),
          _label('세계관'),
          _field('세계관 / 시대 / 장소 / 규칙', _worldCtrl, _updateDesign, lines: 7),
          _label('플롯 구조'),
          _field('발단', _beginningCtrl, _updateDesign, lines: 4),
          _field('전개', _developmentCtrl, _updateDesign, lines: 4),
          _field('위기', _crisisCtrl, _updateDesign, lines: 4),
          _field('절정', _climaxCtrl, _updateDesign, lines: 4),
          _field('결말', _endingCtrl, _updateDesign, lines: 4),
          _field('복선 / 회수 계획', _foreshadowCtrl, _updateDesign, lines: 5),
          _label('작가 메모'),
          _field('수정할 점 / 다음 집필 계획', _designMemoCtrl, _updateDesign, lines: 6),
        ],
      ),
    );
  }

  Widget _characterWorkspace(BuildContext context) {
    final wide = MediaQuery
        .of(context)
        .size
        .width >= 760;
    final form = _project.characters.isEmpty
        ? _empty('등록된 인물이 없습니다', '수정 모드에서 인물을 추가하세요.', Icons.groups_rounded)
        : ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _field('이름', _charNameCtrl, _updateCharacter),
        _field('역할', _charRoleCtrl, _updateCharacter),
        _field('별칭', _charAliasCtrl, _updateCharacter),
        _field('나이', _charAgeCtrl, _updateCharacter),
        _field('성별', _charGenderCtrl, _updateCharacter),
        _field('직업 / 소속', _charJobCtrl, _updateCharacter),
        _field('외형', _charLookCtrl, _updateCharacter, lines: 4),
        _field('성격', _charPersonalityCtrl, _updateCharacter, lines: 4),
        _field('말투', _charSpeechCtrl, _updateCharacter, lines: 4),
        _field('욕망', _charDesireCtrl, _updateCharacter, lines: 4),
        _field('약점', _charWeaknessCtrl, _updateCharacter, lines: 4),
        _field('비밀', _charSecretCtrl, _updateCharacter, lines: 4),
        _field('성장 arc', _charArcCtrl, _updateCharacter, lines: 4),
        _field(
            '관계 / 감정선 / 등장 챕터', _charRelationCtrl, _updateCharacter, lines: 6),
      ],
    );
    final panel = _panel(
      context,
      '인물',
      '등장인물의 말투, 욕망, 약점, 비밀, 관계 변화를 관리합니다.',
      Icons.groups_rounded,
      form,
      actions: [
        if (_editMode) IconButton.filledTonal(onPressed: _addCharacter,
            icon: const Icon(Icons.person_add_alt_1_rounded)),
        if (_editMode) IconButton.filledTonal(
            onPressed: _project.characters.isEmpty ? null : _deleteCharacter,
            icon: const Icon(Icons.delete_outline_rounded)),
      ],
    );
    if (!wide) return Column(children: [
      SizedBox(height: 112, child: _characterHorizontalList()),
      const SizedBox(height: 8),
      Expanded(child: panel)
    ]);
    return Row(children: [
      SizedBox(width: 260, child: _characterSideList()),
      const SizedBox(width: 10),
      Expanded(child: panel)
    ]);
  }

  Widget _termWorkspace(BuildContext context) {
    final wide = MediaQuery
        .of(context)
        .size
        .width >= 760;
    final form = _project.terms.isEmpty
        ? _empty('등록된 용어가 없습니다', '수정 모드에서 용어를 추가하세요.', Icons.menu_book_rounded)
        : ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _field('용어명', _termNameCtrl, _updateTerm),
        _field('별칭', _termAliasCtrl, _updateTerm),
        _field('카테고리', _termCategoryCtrl, _updateTerm),
        _field('짧은 정의', _termShortCtrl, _updateTerm),
        _field('상세 정의', _termDefinitionCtrl, _updateTerm, lines: 7),
        _field('작중 사용 방식', _termUsageCtrl, _updateTerm, lines: 5),
        _field('관련 인물 / 챕터 / 설계 키워드', _termRelatedCtrl, _updateTerm, lines: 4),
        _field('작가 메모', _termMemoCtrl, _updateTerm, lines: 5),
      ],
    );
    final panel = _panel(
      context,
      '용어',
      '세계관 고유명사, 조직, 기술, 시스템, 금기어의 정의를 저장합니다.',
      Icons.menu_book_rounded,
      form,
      actions: [
        if (_editMode) IconButton.filledTonal(
            onPressed: _addTerm, icon: const Icon(Icons.add_rounded)),
        if (_editMode) IconButton.filledTonal(
            onPressed: _project.terms.isEmpty ? null : _deleteTerm,
            icon: const Icon(Icons.delete_outline_rounded)),
      ],
    );
    if (!wide) return Column(children: [
      SizedBox(height: 112, child: _termHorizontalList()),
      const SizedBox(height: 8),
      Expanded(child: panel)
    ]);
    return Row(children: [
      SizedBox(width: 260, child: _termSideList()),
      const SizedBox(width: 10),
      Expanded(child: panel)
    ]);
  }

  Widget _chapterHorizontalList() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: _project.chapters.length + (_editMode ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == _project.chapters.length) return SizedBox(width: 120,
            child: OutlinedButton.icon(onPressed: _addChapter,
                icon: const Icon(Icons.add_rounded),
                label: const Text('추가')));
        final c = _project.chapters[i];
        return SizedBox(width: 192,
            child: _listTile(
                _chapterIndex == i, c.title, '${c.count}자 · 목표 ${c.target}',
                Icons.article_rounded, () => _selectChapter(i)));
      },
    );
  }

  Widget _characterHorizontalList() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: _project.characters.length + (_editMode ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == _project.characters.length) return SizedBox(width: 120,
            child: OutlinedButton.icon(onPressed: _addCharacter,
                icon: const Icon(Icons.add_rounded),
                label: const Text('추가')));
        final c = _project.characters[i];
        return SizedBox(width: 176,
            child: _listTile(_characterIndex == i, c.displayName,
                c.role.isEmpty ? '역할 미정' : c.role, Icons.person_rounded, () =>
                    _selectCharacter(i)));
      },
    );
  }

  Widget _termHorizontalList() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: _project.terms.length + (_editMode ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == _project.terms.length) return SizedBox(width: 120,
            child: OutlinedButton.icon(onPressed: _addTerm,
                icon: const Icon(Icons.add_rounded),
                label: const Text('추가')));
        final t = _project.terms[i];
        return SizedBox(width: 176,
            child: _listTile(_termIndex == i, t.displayName, t.category,
                Icons.menu_book_rounded, () => _selectTerm(i)));
      },
    );
  }

  Widget _characterSideList() =>
      _sideList(title: '인물 목록',
          add: _editMode ? _addCharacter : null,
          count: _project.characters.length,
          item: (i) {
            final c = _project.characters[i];
            return _listTile(_characterIndex == i, c.displayName,
                c.role.isEmpty ? '역할 미정' : c.role, Icons.person_rounded, () =>
                    _selectCharacter(i));
          });

  Widget _termSideList() =>
      _sideList(title: '용어 목록',
          add: _editMode ? _addTerm : null,
          count: _project.terms.length,
          item: (i) {
            final t = _project.terms[i];
            return _listTile(_termIndex == i, t.displayName, t.category,
                Icons.menu_book_rounded, () => _selectTerm(i));
          });

  Widget _sideList(
      {required String title, required int count, required Widget Function(int) item, VoidCallback? add}) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface.withOpacity(.86),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withOpacity(.55))),
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              child: Row(children: [
                Expanded(child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900))),
                if (add != null) IconButton(
                    onPressed: add, icon: const Icon(Icons.add_rounded))
              ])),
          Expanded(
              child: count == 0 ? const Center(child: Text('목록 없음')) : ListView
                  .separated(padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  itemCount: count,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => item(i))),
        ],
      ),
    );
  }

  Widget _listTile(bool selected, String title, String subtitle, IconData icon,
      VoidCallback onTap) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest
                .withOpacity(.42), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, size: 20,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900,
                        color: selected ? cs.onPrimaryContainer : cs
                            .onSurface)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12,
                        color: selected
                            ? cs.onPrimaryContainer.withOpacity(.76)
                            : cs.onSurfaceVariant))
              ])),
        ]),
      ),
    );
  }

  Widget _label(String label) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text(
              label, style: const TextStyle(fontWeight: FontWeight.w900)));

  Widget _empty(String title, String body, IconData icon) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 32,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  child: Icon(icon, size: 32)),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(body, textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant))
            ]),
      ),
    );
  }

  Widget _metaBar(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    final current = _chapter?.count ?? 0;
    final target = _chapter?.target ?? 0;
    final progress = target <= 0 ? 0.0 : (current / target)
        .clamp(0.0, 1.0)
        .toDouble();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.surface.withOpacity(.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(.5))),
      child: Row(children: [
        Icon(_editMode ? Icons.edit_rounded : Icons.lock_outline_rounded,
            size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(_editMode ? '수정 가능' : '읽기 전용', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant)),
        const SizedBox(width: 10),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 7))),
        const SizedBox(width: 10),
        Text('$current / $target자',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        Text('전체 ${_project.totalCount}자',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  void _handleBottomNavTap(_NovelTab tab) {
    if (tab == _NovelTab.edit) {
      _toggleEdit();
      return;
    }
    if (tab == _NovelTab.chapters && _tab == _NovelTab.chapters &&
        _project.chapters.length > 1) {
      _openChapterSelector();
      return;
    }
    setState(() => _tab = tab);
  }

  Widget _bottomNav(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    final items = <_BottomNavItem>[
      const _BottomNavItem(_NovelTab.chapters, Icons.article_rounded, '챕터'),
      const _BottomNavItem(_NovelTab.design, Icons.architecture_rounded, '설계'),
      const _BottomNavItem(_NovelTab.characters, Icons.groups_rounded, '인물'),
      const _BottomNavItem(_NovelTab.terms, Icons.menu_book_rounded, '용어'),
      _BottomNavItem(_NovelTab.edit,
          _editMode ? Icons.edit_rounded : Icons.lock_outline_rounded,
          _editMode ? '수정ON' : '수정OFF'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(color: cs.surface.withOpacity(.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withOpacity(.62))),
      child: Row(
        children: items.map((item) {
          final selected = item.tab == _tab && item.tab != _NovelTab.edit;
          final editSelected = item.tab == _NovelTab.edit && _editMode;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _handleBottomNavTap(item.tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: selected || editSelected
                    ? cs.primaryContainer
                    : Colors.transparent,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 20,
                          color: selected || editSelected ? cs
                              .onPrimaryContainer : cs.onSurfaceVariant),
                      const SizedBox(height: 2),
                      Text(item.label, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11,
                              fontWeight: selected || editSelected ? FontWeight
                                  .w900 : FontWeight.w700,
                              color: selected || editSelected ? cs
                                  .onPrimaryContainer : cs.onSurfaceVariant))
                    ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BottomNavItem {
  final _NovelTab tab;
  final IconData icon;
  final String label;

  const _BottomNavItem(this.tab, this.icon, this.label);
}

class _SheetTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SheetTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(children: [
        Container(width: 42,
            height: 4,
            decoration: BoxDecoration(color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme
                    .of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
              ])),
          IconButton(onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded))
        ]),
      ]),
    );
  }
}

enum _NovelTab { chapters, design, characters, terms, edit }

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
    if (value is Timestamp) return value.toDate();
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

  Map<String, dynamic> meta({String? uid, String? email}) =>
      {
        'schemaVersion': 1,
        'syncMode': 'notensystemSectionScoped',
        'id': id,
        'title': title,
        'genre': genre,
        'logline': logline,
        'activeChapterId': activeChapterId,
        'chapterIds': chapters.map((e) => e.id).toList(),
        'characterIds': characters.map((e) => e.id).toList(),
        'termIds': terms.map((e) => e.id).toList(),
        'recipients': recipients.map((e) => e.toJson()).toList(),
        'chapterCount': chapters.length,
        'characterCount': characters.length,
        'termCount': terms.length,
        'totalCount': totalCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pushedByUid': uid,
        'pushedByEmail': email,
        'serverUpdatedAt': FieldValue.serverTimestamp()
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

  static Future<_Project> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw
        .trim()
        .isEmpty) return _Project.seed();
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map)
        return _Project.fromJson(Map<String, dynamic>.from(parsed));
    } catch (_) {}
    return _Project.seed();
  }

  static Future<void> save(_Project project) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(project.toJson()));
  }
}

class _Remote {
  static const libraryCollection = 'note_system_libraries';
  static const libraryDocument = 'headquarter_default';

  static DocumentReference<Map<String, dynamic>> get root =>
      FirebaseFirestore.instance.collection(libraryCollection).doc(
          libraryDocument);

  static DocumentReference<Map<String, dynamic>> project(String id) =>
      root.collection('projects').doc(id);

  static DocumentReference<Map<String, dynamic>> meta(String id) =>
      project(id).collection('meta').doc('main');

  static DocumentReference<Map<String, dynamic>> design(String id) =>
      project(id).collection('design').doc('main');

  static CollectionReference<Map<String, dynamic>> chapters(String id) =>
      project(id).collection('chapters');

  static CollectionReference<Map<String, dynamic>> characters(String id) =>
      project(id).collection('characters');

  static CollectionReference<Map<String, dynamic>> terms(String id) =>
      project(id).collection('terms');

  static String projectPath(String id) =>
      '$libraryCollection/$libraryDocument/projects/$id';

  static Map<String, String?> user() {
    final fu = FirebaseAuth.instance.currentUser;
    final gu = GoogleAuthSession.instance.currentUser;
    return {'uid': fu?.uid, 'email': fu?.email ?? gu?.email};
  }

  static Future<void> pushMeta(_Project p) async {
    final u = user();
    final now = DateTime.now().toIso8601String();
    await root.set({
      'schemaVersion': 1,
      'syncMode': 'notensystemSectionScoped',
      'activeProjectId': p.id,
      'updatedAt': now,
      'serverUpdatedAt': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
    await project(p.id).set(
        p.meta(uid: u['uid'], email: u['email']), SetOptions(merge: true));
    await meta(p.id).set(
        p.meta(uid: u['uid'], email: u['email']), SetOptions(merge: true));
  }

  static Future<void> pushAll(_Project p) async {
    await pushMeta(p);
    await pushDesign(p);
    await pushChapters(p);
    await pushCharacters(p);
    await pushTerms(p);
  }

  static Future<void> pushDesign(_Project p) async {
    await pushMeta(p);
    await design(p.id).set({
      ...p.design.toJson(),
      'schemaVersion': 1,
      'projectId': p.id,
      'serverUpdatedAt': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
  }

  static Future<void> pushChapters(_Project p) async {
    await pushMeta(p);
    if (p.chapters.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final c in p.chapters) {
      batch.set(chapters(p.id).doc(c.id), {
        ...c.toJson(),
        'schemaVersion': 1,
        'projectId': p.id,
        'serverUpdatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> pushChapter(_Project p, _Chapter c) async {
    await pushMeta(p);
    await chapters(p.id).doc(c.id).set({
      ...c.toJson(),
      'schemaVersion': 1,
      'projectId': p.id,
      'serverUpdatedAt': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
  }

  static Future<void> pushCharacters(_Project p) async {
    await pushMeta(p);
    if (p.characters.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final c in p.characters) {
      batch.set(characters(p.id).doc(c.id), {
        ...c.toJson(),
        'schemaVersion': 1,
        'projectId': p.id,
        'serverUpdatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> pushTerms(_Project p) async {
    await pushMeta(p);
    if (p.terms.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final t in p.terms) {
      batch.set(terms(p.id).doc(t.id), {
        ...t.toJson(),
        'schemaVersion': 1,
        'projectId': p.id,
        'serverUpdatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<_Project> pullAll(String id) async {
    final metaSnap = await meta(id).get();
    if (!metaSnap.exists) throw StateError(
        'Firebase에 notensystem 메타 문서가 없습니다.');
    final m = Map<String, dynamic>.from(metaSnap.data() ?? {});
    final d = await pullDesign(id);
    final cs = await pullChapters(id);
    final chars = await pullCharacters(id);
    final ts = await pullTerms(id);
    final rs = (m['recipients'] as List?)?.whereType<Map>().map((e) =>
        _Recipient.fromJson(Map<String, dynamic>.from(e))).where((e) =>
        _Mail.isValid(e.email)).toList() ?? <_Recipient>[];
    final now = DateTime.now();
    final safeChapters = cs.isEmpty ? _Project
        .seed()
        .chapters : cs;
    return _Project(id: id,
        title: ((m['title'] as String?) ?? '')
            .trim()
            .isEmpty ? '무제 소설' : (m['title'] as String).trim(),
        genre: (m['genre'] as String?) ?? '',
        logline: (m['logline'] as String?) ?? '',
        design: d,
        chapters: safeChapters,
        characters: chars,
        terms: ts,
        recipients: rs,
        activeChapterId: ((m['activeChapterId'] as String?) ?? '')
            .trim()
            .isEmpty ? safeChapters.first.id : (m['activeChapterId'] as String)
            .trim(),
        createdAt: _Dates.parse(m['createdAt']) ?? now,
        updatedAt: _Dates.parse(m['updatedAt']) ?? now);
  }

  static Future<_Design> pullDesign(String id) async {
    final snap = await design(id).get();
    if (!snap.exists) throw StateError('Firebase에 설계 문서가 없습니다.');
    return _Design.fromJson(Map<String, dynamic>.from(snap.data() ?? {}));
  }

  static Future<List<_Chapter>> pullChapters(String id) async {
    final m = (await meta(id).get()).data();
    final ids = (m?['chapterIds'] as List?)?.whereType<String>().toList() ??
        <String>[];
    final snap = await chapters(id).orderBy('order').get();
    final list = <_Chapter>[];
    for (final doc in snap.docs) {
      if (ids.isNotEmpty && !ids.contains(doc.id)) continue;
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = ((data['id'] as String?) ?? '')
          .trim()
          .isEmpty ? doc.id : data['id'];
      list.add(_Chapter.fromJson(data));
    }
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static Future<_Chapter> pullChapter(String projectId,
      String chapterId) async {
    final snap = await chapters(projectId).doc(chapterId).get();
    if (!snap.exists) throw StateError('Firebase에 선택한 챕터 문서가 없습니다.');
    final data = Map<String, dynamic>.from(snap.data() ?? {});
    data['id'] = ((data['id'] as String?) ?? '')
        .trim()
        .isEmpty ? chapterId : data['id'];
    return _Chapter.fromJson(data);
  }

  static Future<List<_Character>> pullCharacters(String id) async {
    final m = (await meta(id).get()).data();
    final ids = (m?['characterIds'] as List?)?.whereType<String>().toList() ??
        <String>[];
    final snap = await characters(id).get();
    final list = <_Character>[];
    for (final doc in snap.docs) {
      if (ids.isNotEmpty && !ids.contains(doc.id)) continue;
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = ((data['id'] as String?) ?? '')
          .trim()
          .isEmpty ? doc.id : data['id'];
      list.add(_Character.fromJson(data));
    }
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  static Future<List<_Term>> pullTerms(String id) async {
    final m = (await meta(id).get()).data();
    final ids = (m?['termIds'] as List?)?.whereType<String>().toList() ??
        <String>[];
    final snap = await terms(id).get();
    final list = <_Term>[];
    for (final doc in snap.docs) {
      if (ids.isNotEmpty && !ids.contains(doc.id)) continue;
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = ((data['id'] as String?) ?? '')
          .trim()
          .isEmpty ? doc.id : data['id'];
      list.add(_Term.fromJson(data));
    }
    list.sort((a, b) {
      final c = a.category.compareTo(b.category);
      return c != 0 ? c : a.displayName.compareTo(b.displayName);
    });
    return list;
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
