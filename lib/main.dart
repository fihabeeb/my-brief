import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/supabase/supabase_service.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  // Only initialise Supabase when credentials are provided via
  // --dart-define / --dart-define-from-file. This keeps the app runnable on
  // both platforms before any backend exists (Phase 0 "unconfigured" mode).
  await SupabaseService.initIfConfigured();

  runApp(const ProviderScope(child: MyApp()));
}
