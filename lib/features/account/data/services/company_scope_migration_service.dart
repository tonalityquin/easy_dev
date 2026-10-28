import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'company_bootstrap_service.dart';

class CompanyScopeMigrationResult {
  const CompanyScopeMigrationResult({
    required this.updated,
    required this.skipped,
    this.checked = 0,
    this.conflicted = 0,
    this.invalidCompany = 0,
    this.ambiguous = 0,
    this.parentMismatch = 0,
    this.unresolved = 0,
    this.failed = 0,
    this.plannedUpdates = 0,
    this.appliedUpdates = 0,
    this.issues = const <String>[],
    this.dryRun = false,
  });

  final int updated;
  final int skipped;
  final int checked;
  final int conflicted;
  final int invalidCompany;
  final int ambiguous;
  final int parentMismatch;
  final int unresolved;
  final int failed;
  final int plannedUpdates;
  final int appliedUpdates;
  final List<String> issues;
  final bool dryRun;
}

class CompanyScopeMigrationService {
  const CompanyScopeMigrationService();

  static const List<String> _collections = <String>[
    'bill', 'voice_channels', 'commute_true_false', 'plate_counters',
    'plates', 'plate_status', 'parking_requests_view',
    'departure_requests_view', 'parking_completed_view',
    'monthly_plate_status', 'monthly_plate_status_view',
    'plate_out_log', 'plate_billing_counts', 'end_work_reports',
    'head_memo_libraries', 'commute_user_logs', 'personal_accounts',
    'locations', 'sector', 'locationSlotReservations',
  ];

  Future<CompanyScopeMigrationResult> migrate({
    void Function(String message)? onProgress,
    bool dryRun = false,
  }) async {
    await CompanyBootstrapService.requireDeveloper(
      source: 'company_scope_migration',
      forceAccountSelection: false,
    );
    final firestore = FirebaseFirestore.instance;
    final divisions = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('divisions')
        .get(const GetOptions(source: Source.server)), source: 'company_scope_migration_service.get');
    final validCompanies = divisions.docs.map((doc) => doc.id).toSet();
    final areas = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('areas')
        .get(const GetOptions(source: Source.server)), source: 'company_scope_migration_service.get');
    final areaCompanies = <String, Set<String>>{};

    void indexArea(String value, String company) {
      final key = value.trim();
      if (key.isEmpty || !validCompanies.contains(company)) return;
      areaCompanies.putIfAbsent(key, () => <String>{}).add(company);
    }

    for (final doc in areas.docs) {
      final data = doc.data();
      final company = (data['division'] ?? data['companyId'] ?? '')
          .toString().trim();
      indexArea(doc.id, company);
      indexArea((data['name'] ?? '').toString(), company);
      indexArea((data['area'] ?? '').toString(), company);
    }

    String? ownerForArea(String area) {
      final owners = areaCompanies[area.trim()];
      return owners != null && owners.length == 1 ? owners.single : null;
    }

    String? areaFor(DocumentSnapshot<Map<String, dynamic>> doc,
        {String? inherited}) {
      final data = doc.data() ?? <String, dynamic>{};
      final value = (data['area'] ?? data['areaName'] ??
          data['currentArea'] ?? data['areaKey'] ?? inherited ?? '')
          .toString().trim();
      if (value.isNotEmpty) return value;
      if (doc.id.startsWith('area_')) return doc.id.substring(5);
      if (areaCompanies.containsKey(doc.id)) return doc.id;
      return null;
    }

    ({String? company, String reason}) verifyCompany(
      DocumentSnapshot<Map<String, dynamic>> doc, {
      String? inheritedCompany,
      String? inheritedArea,
    }) {
      final data = doc.data() ?? <String, dynamic>{};
      final field = (data['companyId'] ?? data['division'] ??
          data['company'] ?? '').toString().trim();
      final area = areaFor(doc, inherited: inheritedArea);
      final owners = area == null ? null : areaCompanies[area];
      final byArea = ownerForArea(area ?? '');
      final byId = validCompanies.contains(doc.id) ? doc.id : null;
      if (field.isNotEmpty && !validCompanies.contains(field)) {
        return (company: null, reason: 'invalid_company');
      }
      if (inheritedCompany != null && field.isNotEmpty &&
          field != inheritedCompany) {
        return (company: null, reason: 'parent_mismatch');
      }
      if (owners != null && owners.length > 1 &&
          field.isEmpty && inheritedCompany == null && byId == null) {
        return (company: null, reason: 'ambiguous_area');
      }
      final candidates = <String>{
        if (field.isNotEmpty) field,
        if (byArea != null) byArea,
        if (byId != null) byId,
        if (inheritedCompany != null) inheritedCompany,
      };
      if (candidates.length > 1) {
        return (company: null, reason: 'company_conflict');
      }
      if (candidates.isEmpty) {
        return (company: null, reason: 'unresolved');
      }
      return (company: candidates.single, reason: 'verified');
    }

    var updated = 0;
    var plannedUpdates = 0;
    var appliedUpdates = 0;
    var failed = 0;
    final issues = <String>[];
    void noteFailure(String path, Object error, StackTrace stackTrace, {int count = 1}) {
      failed += count;
      final message = 'write_or_read_failed=$path error=$error';
      if (issues.length < 120) issues.add(message);
      debugPrint('[SCOPE-MIGRATION] $message\n$stackTrace');
      onProgress?.call('업무 문서 점검 실패: $path ($error)');
    }
    var skipped = 0;
    var checked = 0;
    var conflicted = 0;
    var invalidCompany = 0;
    var ambiguous = 0;
    var parentMismatch = 0;
    var unresolved = 0;
    for (final doc in divisions.docs) {
      checked++;
      final stored = (doc.data()['companyId'] ?? '').toString().trim();
      if (stored.isNotEmpty && stored != doc.id) {
        conflicted++;
        onProgress?.call('회사 ID 충돌: ${doc.reference.path}');
        debugPrint('[SCOPE-MIGRATION] company_conflict=${doc.reference.path}');
      } else if (stored.isEmpty) {
        plannedUpdates++;
        if (dryRun) {
          updated++;
        } else {
          try {
            await FirebaseActivityMonitor.track(FirebaseActivityKind.update, () => doc.reference.update(<String, dynamic>{'companyId': doc.id}), source: 'company_scope_migration_service.update');
            appliedUpdates++;
            updated++;
          } catch (error, stackTrace) {
            noteFailure(doc.reference.path, error, stackTrace);
          }
        }
      }
    }
    void reportRejected(String path, String reason) {
      skipped++;
      if (reason == 'company_conflict') conflicted++;
      if (reason == 'invalid_company') invalidCompany++;
      if (reason == 'ambiguous_area') ambiguous++;
      if (reason == 'parent_mismatch') parentMismatch++;
      if (reason == 'unresolved') unresolved++;
      debugPrint('[SCOPE-MIGRATION] manual_check=$path reason=$reason');
      if (issues.length < 120) issues.add('manual_check=$path reason=$reason');
      if (skipped <= 80) {
        onProgress?.call('회사 소속 확인 필요: $path ($reason)');
      }
    }

    Future<void> migrateCollection(
      CollectionReference<Map<String, dynamic>> collection, {
      String? inheritedCompany,
      String? inheritedArea,
      Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc,
          String company, String? area)? afterDocument,
    }) async {
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        Query<Map<String, dynamic>> query = collection.limit(150);
        if (cursor != null) query = query.startAfterDocument(cursor);
        QuerySnapshot<Map<String, dynamic>> page;
        try {
          page = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => query.get(const GetOptions(source: Source.server)), source: 'company_scope_migration_service.get');
        } catch (error, stackTrace) {
          noteFailure(collection.path, error, stackTrace);
          break;
        }
        if (page.docs.isEmpty) break;
        final batch = firestore.batch();
        var pending = 0;
        final children = <({DocumentSnapshot<Map<String, dynamic>> doc,
          String company, String? area})>[];
        for (final doc in page.docs) {
          checked++;
          try {
            final data = doc.data();
            final verification = verifyCompany(doc,
                inheritedCompany: inheritedCompany,
                inheritedArea: inheritedArea);
            final company = verification.company;
            final area = areaFor(doc, inherited: inheritedArea);
            if (company == null) {
              reportRejected(doc.reference.path, verification.reason);
              continue;
            }
            final stored = (data['companyId'] ?? '').toString().trim();
            if (stored != company) {
              if (!dryRun) {
                FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.update, () => batch.update(doc.reference, <String, dynamic>{'companyId': company}));
              }
              pending++;
            }
            if (afterDocument != null) {
              children.add((doc: doc, company: company, area: area));
            }
          } catch (error, stackTrace) {
            noteFailure(doc.reference.path, error, stackTrace);
          }
        }
        plannedUpdates += pending;
        var parentWritten = true;
        if (pending > 0) {
          if (dryRun) {
            updated += pending;
          } else {
            try {
              await FirebaseActivityMonitor.track(FirebaseActivityKind.batch, () => batch.commit(), batch: batch, source: 'company_scope_migration_service.commit');
              updated += pending;
              appliedUpdates += pending;
            } catch (error, stackTrace) {
              parentWritten = false;
              noteFailure(collection.path, error, stackTrace, count: pending);
            }
          }
        }
        if (parentWritten && afterDocument != null) {
          for (final child in children) {
            try {
              await afterDocument(child.doc, child.company, child.area);
            } catch (error, stackTrace) {
              noteFailure(child.doc.reference.path, error, stackTrace);
            }
          }
        }
        cursor = page.docs.last;
        if (page.docs.length < 150) break;
      }
    }

    Future<void> processMonths(
      DocumentSnapshot<Map<String, dynamic>> parent,
      String company,
      String? area, {
      required String childCollection,
    }) async {
      await migrateCollection(parent.reference.collection('months'),
        inheritedCompany: company,
        inheritedArea: area,
        afterDocument: (month, monthCompany, monthArea) async {
          await migrateCollection(month.reference.collection(childCollection),
            inheritedCompany: monthCompany,
            inheritedArea: monthArea,
          );
        },
      );
    }

    for (final name in _collections) {
      onProgress?.call('$name 회사 식별값 검사');
      await migrateCollection(firestore.collection(name),
        afterDocument: (doc, company, area) async {
          if (name == 'voice_channels') {
            await migrateCollection(doc.reference.collection('messages'),
              inheritedCompany: company, inheritedArea: area);
          } else if (name == 'plate_status' || name == 'plate_out_log') {
            await processMonths(doc, company, area, childCollection: 'plates');
          } else if (name == 'end_work_reports') {
            await processMonths(doc, company, area, childCollection: 'submissions');
          } else if (name == 'commute_user_logs') {
            await migrateCollection(doc.reference.collection('months'),
              inheritedCompany: company, inheritedArea: area);
          } else if (name == 'head_memo_libraries') {
            await migrateCollection(doc.reference.collection('meta'),
              inheritedCompany: company, inheritedArea: area);
            await migrateCollection(doc.reference.collection('books'),
              inheritedCompany: company, inheritedArea: area,
              afterDocument: (book, bookCompany, bookArea) async {
                await migrateCollection(book.reference.collection('pages'),
                  inheritedCompany: bookCompany, inheritedArea: bookArea);
              },
            );
          }
        },
      );
    }
    onProgress?.call('상위 문서가 없는 업무 보고서 검사');
    for (final entry in areaCompanies.entries) {
      if (entry.value.length != 1) continue;
      final company = entry.value.single;
      final area = entry.key;
      await migrateCollection(
        firestore.collection('end_work_reports')
            .doc('area_$area').collection('months'),
        inheritedCompany: company,
        inheritedArea: area,
        afterDocument: (month, owner, monthArea) async {
          await migrateCollection(month.reference.collection('submissions'),
            inheritedCompany: owner,
            inheritedArea: monthArea,
          );
        },
      );
    }
    onProgress?.call('상위 문서가 없는 메모북 검사');
    final memoRoot = firestore.collection('head_memo_libraries')
        .doc('headquarter_default');
    await migrateCollection(memoRoot.collection('books'),
      afterDocument: (book, owner, area) async {
        await migrateCollection(book.reference.collection('pages'),
          inheritedCompany: owner, inheritedArea: area);
      },
    );
    onProgress?.call('상위 문서가 없는 차량 이력 검사');
    DocumentSnapshot<Map<String, dynamic>>? historyCursor;
    while (true) {
      Query<Map<String, dynamic>> query = firestore
          .collectionGroup('plates').limit(150);
      if (historyCursor != null) {
        query = query.startAfterDocument(historyCursor);
      }
      QuerySnapshot<Map<String, dynamic>> page;
      try {
        page = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => query.get(const GetOptions(source: Source.server)), source: 'company_scope_migration_service.get');
      } catch (error, stackTrace) {
        noteFailure('collectionGroup/plates', error, stackTrace);
        break;
      }
      if (page.docs.isEmpty) break;
      final batch = firestore.batch();
      var pending = 0;
      for (final doc in page.docs) {
        checked++;
        final segments = doc.reference.path.split('/');
        if (segments.length != 6 ||
            (segments[0] != 'plate_status' &&
             segments[0] != 'plate_out_log') ||
            segments[2] != 'months' || segments[4] != 'plates') {
          continue;
        }
        final owner = ownerForArea(segments[1]);
        final verification = verifyCompany(doc,
            inheritedCompany: owner, inheritedArea: segments[1]);
        final company = verification.company;
        if (company == null) {
          reportRejected(doc.reference.path, verification.reason);
          continue;
        }
        if ((doc.data()['companyId'] ?? '').toString().trim() == company) {
          continue;
        }
        if (!dryRun) {
          FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.update, () => batch.update(doc.reference, <String, dynamic>{'companyId': company}));
        }
        pending++;
      }
      if (pending > 0) {
        plannedUpdates += pending;
        if (dryRun) {
          updated += pending;
        } else {
          try {
            await FirebaseActivityMonitor.track(FirebaseActivityKind.batch, () => batch.commit(), batch: batch, source: 'company_scope_migration_service.commit');
            updated += pending;
            appliedUpdates += pending;
          } catch (error, stackTrace) {
            noteFailure('collectionGroup/plates', error, stackTrace, count: pending);
          }
        }
      }
      historyCursor = page.docs.last;
      if (page.docs.length < 150) break;
    }
    onProgress?.call('${dryRun ? '미리 점검' : '회사 식별값 보완'} 계획 $plannedUpdates개 · 적용 $appliedUpdates개 · 수동 확인 $skipped개 · 충돌 $conflicted개 · 회사 오류 $invalidCompany개 · 지역 모호 $ambiguous개 · 부모 불일치 $parentMismatch개 · 소속 불명 $unresolved개 · 실패 $failed개');
    return CompanyScopeMigrationResult(
      updated: updated,
      skipped: skipped,
      checked: checked,
      conflicted: conflicted,
      invalidCompany: invalidCompany,
      ambiguous: ambiguous,
      parentMismatch: parentMismatch,
      unresolved: unresolved,
      failed: failed,
      plannedUpdates: plannedUpdates,
      appliedUpdates: appliedUpdates,
      issues: List<String>.unmodifiable(issues),
      dryRun: dryRun,
    );
  }
}
