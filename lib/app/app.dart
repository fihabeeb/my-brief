import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_mode_provider.dart';
import '../core/sync/sync_bootstrap.dart';
import '../core/theme/app_theme.dart';
import 'notification_bootstrap.dart';
import 'router.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiates sync (starts push/pull + realtime once signed in).
    ref.watch(syncBootstrapProvider);
    // Instantiates the in-process notification scheduler.
    ref.watch(notificationBootstrapProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'My Brief',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
