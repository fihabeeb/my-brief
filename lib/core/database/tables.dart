import 'package:drift/drift.dart';

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get needsSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('upcoming'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get needsSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// An OAuth-connected mailbox.
///
/// Written in two places: the client creates and deletes the row when the user
/// connects or disconnects, and the Edge Function updates the sync position
/// and health. That split is why accounts bypass the LWW outbox used by tasks
/// and reminders — two writers racing through a client-side outbox would
/// overwrite each other's fields. Tokens are never stored here; `secretRef`
/// names the Supabase Vault entry that holds them.
class EmailAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get provider => text()();
  TextColumn get emailAddress => text()();
  TextColumn get displayName => text().nullable()();

  /// 'connected' | 'needs_reauth' | 'error'.
  TextColumn get status => text().withDefault(const Constant('connected'))();
  TextColumn get lastError => text().nullable()();

  /// Opaque provider-specific sync position — Gmail's historyId, Graph's
  /// delta token. Only the Edge Function reads it.
  TextColumn get syncCursor => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get secretRef => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A read-only mirror of a mailbox.
///
/// No `needsSync`: the client never authors an email, it only reads one. The
/// Edge Function is the sole writer, and `providerMessageId` is what makes an
/// incremental sync idempotent.
class Emails extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get accountId => text()();
  TextColumn get providerMessageId => text()();
  TextColumn get threadId => text().nullable()();
  TextColumn get fromName => text().nullable()();
  TextColumn get fromEmail => text().nullable()();
  TextColumn get subject => text().withDefault(const Constant(''))();

  /// A short preview, not the message body. Storing full MIME would make this
  /// the fastest-growing table in the app, and the dashboard wants highlights;
  /// `webLink` opens the real message in the browser.
  TextColumn get snippet => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();
  BoolColumn get hasAttachments => boolean().withDefault(const Constant(false))();
  TextColumn get webLink => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
