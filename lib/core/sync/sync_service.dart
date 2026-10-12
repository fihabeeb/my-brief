import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../supabase/supabase_service.dart';

final syncServiceProvider = Provider<SyncService>(
    (ref) => SyncService(ref.watch(appDatabaseProvider)));

/// Two-way sync between the local Drift cache and Supabase.
///
/// - Push: local rows flagged `needsSync` are upserted to Supabase, then the
///   flag is cleared.
/// - Pull + realtime: remote rows are merged into the local DB with a
///   last-write-wins rule on `updated_at`, and incoming rows are never
///   re-flagged for sync (no echo loop).
class SyncService {
  SyncService(this._db);
  final AppDatabase _db;

  RealtimeChannel? _channel;

  bool get _enabled => SupabaseService.isConfigured;
  String get _uid => SupabaseService.auth.currentUser?.id ?? '';

  Future<void> syncNow() async {
    if (!_enabled || _uid.isEmpty) return;
    final uid = _uid;
    await _pushTasks(uid);
    await _pushReminders(uid);
    await _pullTasks(uid);
    await _pullReminders(uid);
  }

  void subscribe() {
    if (!_enabled || _uid.isEmpty) return;
    final uid = _uid;
    _channel?.unsubscribe();

    final ch = SupabaseService.client
        .channel('mybrief-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec.isNotEmpty) _mergeTask(rec);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reminders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec.isNotEmpty) _mergeReminder(rec);
          },
        );
    ch.subscribe();
    _channel = ch;
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  // ---- Push ----

  Future<void> _pushTasks(String uid) async {
    final dirty = await (_db.select(_db.tasks)
          ..where((t) => t.needsSync.equals(true) & t.userId.equals(uid)))
        .get();
    if (dirty.isEmpty) return;

    final rows = dirty
        .map((t) => <String, dynamic>{
              'id': t.id,
              'user_id': t.userId,
              'title': t.title,
              'notes': t.notes,
              'due_date': t.dueDate.toIso8601String(),
              'priority': t.priority,
              'status': t.status,
              'recurrence_rule': t.recurrenceRule,
              'completed_at': t.completedAt?.toIso8601String(),
              'created_at': t.createdAt.toIso8601String(),
              'updated_at': t.updatedAt.toIso8601String(),
              'deleted_at': t.deletedAt?.toIso8601String(),
            })
        .toList();

    await SupabaseService.client.from('tasks').upsert(rows);
    final ids = dirty.map((t) => t.id).toList();
    await (_db.update(_db.tasks)..where((t) => t.id.isIn(ids)))
        .write(const TasksCompanion(needsSync: Value(false)));
  }

  Future<void> _pushReminders(String uid) async {
    final dirty = await (_db.select(_db.reminders)
          ..where((r) => r.needsSync.equals(true) & r.userId.equals(uid)))
        .get();
    if (dirty.isEmpty) return;

    final rows = dirty
        .map((r) => <String, dynamic>{
              'id': r.id,
              'user_id': r.userId,
              'title': r.title,
              'notes': r.notes,
              'remind_at': r.remindAt.toIso8601String(),
              'recurrence_rule': r.recurrenceRule,
              'status': r.status,
              'snoozed_until': r.snoozedUntil?.toIso8601String(),
              'completed_at': r.completedAt?.toIso8601String(),
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
              'deleted_at': r.deletedAt?.toIso8601String(),
            })
        .toList();

    await SupabaseService.client.from('reminders').upsert(rows);
    final ids = dirty.map((r) => r.id).toList();
    await (_db.update(_db.reminders)..where((r) => r.id.isIn(ids)))
        .write(const RemindersCompanion(needsSync: Value(false)));
  }

  // ---- Pull ----

  Future<void> _pullTasks(String uid) async {
    final remote = await SupabaseService.client
        .from('tasks')
        .select()
        .eq('user_id', uid)
        .order('updated_at', ascending: false)
        .limit(500);
    for (final row in remote) {
      await _mergeTask(Map<String, dynamic>.from(row));
    }
  }

  Future<void> _pullReminders(String uid) async {
    final remote = await SupabaseService.client
        .from('reminders')
        .select()
        .eq('user_id', uid)
        .order('updated_at', ascending: false)
        .limit(500);
    for (final row in remote) {
      await _mergeReminder(Map<String, dynamic>.from(row));
    }
  }

  // ---- Last-write-wins merge (never re-flag for sync) ----

  Future<void> _mergeTask(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = _ts(row['updated_at']);
    final local =
        await (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !remoteUpdated.isAfter(local.updatedAt)) return;

    await _db.into(_db.tasks).insertOnConflictUpdate(TasksCompanion(
          id: Value(id),
          userId: Value(row['user_id'] as String),
          title: Value(row['title'] as String),
          notes: Value(row['notes'] as String?),
          dueDate: Value(_ts(row['due_date'])),
          priority: Value(row['priority'] as int? ?? 1),
          status: Value(row['status'] as String? ?? 'pending'),
          recurrenceRule: Value(row['recurrence_rule'] as String?),
          completedAt: Value(_optTs(row['completed_at'])),
          createdAt: Value(_optTs(row['created_at']) ?? remoteUpdated),
          updatedAt: Value(remoteUpdated),
          deletedAt: Value(_optTs(row['deleted_at'])),
          needsSync: const Value(false),
        ));
  }

  Future<void> _mergeReminder(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = _ts(row['updated_at']);
    final local =
        await (_db.select(_db.reminders)..where((r) => r.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !remoteUpdated.isAfter(local.updatedAt)) return;

    await _db.into(_db.reminders).insertOnConflictUpdate(RemindersCompanion(
          id: Value(id),
          userId: Value(row['user_id'] as String),
          title: Value(row['title'] as String),
          notes: Value(row['notes'] as String?),
          remindAt: Value(_ts(row['remind_at'])),
          recurrenceRule: Value(row['recurrence_rule'] as String?),
          status: Value(row['status'] as String? ?? 'upcoming'),
          snoozedUntil: Value(_optTs(row['snoozed_until'])),
          completedAt: Value(_optTs(row['completed_at'])),
          createdAt: Value(_optTs(row['created_at']) ?? remoteUpdated),
          updatedAt: Value(remoteUpdated),
          deletedAt: Value(_optTs(row['deleted_at'])),
          needsSync: const Value(false),
        ));
  }

  static DateTime _ts(dynamic v) => DateTime.parse(v as String).toUtc();
  static DateTime? _optTs(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();
}
