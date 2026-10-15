import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Tasks, Reminders, EmailAccounts, Emails])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'mybrief'));

  /// Used by tests with an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 shipped tasks and reminders only; email arrived in Phase 4.
          // Both tables are new, so adding them is additive and no existing
          // row is touched.
          if (from < 2) {
            await m.createTable(emailAccounts);
            await m.createTable(emails);
          }
        },
      );
}
