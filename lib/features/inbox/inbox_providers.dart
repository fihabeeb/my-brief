import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/email_repository.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';

final emailRepositoryProvider = Provider<EmailRepository>(
    (ref) => EmailRepository(ref.watch(appDatabaseProvider)));

/// The merged inbox, newest first. One provider rather than a `.family` over
/// limits: the dashboard takes the first few and the inbox the rest, and a
/// shared stream means one query rather than one per screen.
final recentEmailsProvider = StreamProvider<List<Email>>(
    (ref) => ref.watch(emailRepositoryProvider).watchRecent());

final emailAccountsProvider = StreamProvider<List<EmailAccount>>(
    (ref) => ref.watch(emailRepositoryProvider).watchAccounts());

final unreadEmailCountProvider = StreamProvider<int>(
    (ref) => ref.watch(emailRepositoryProvider).watchUnreadCount());
