import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../supabase/supabase_service.dart';
import 'sync_service.dart';

/// Starts sync when a user is signed in. Watches [authControllerProvider] so it
/// (re)subscribes after sign-in / re-auth, and re-tears-down on sign-out.
///
/// - Immediate push of any offline edits, then a pull.
/// - Realtime subscription so changes land on this device within seconds.
/// - A periodic pull as a safety net (covers missed realtime events / cold
///   starts) — cheap for a single user.
final syncBootstrapProvider = Provider<void>((ref) {
  ref.watch(authControllerProvider);

  if (!SupabaseService.isConfigured) return;
  final uid = SupabaseService.auth.currentUser?.id;
  if (uid == null) return;

  final svc = ref.read(syncServiceProvider);
  svc.subscribe();
  svc.syncNow();

  final timer = Timer.periodic(
      const Duration(minutes: 2), (_) => svc.syncNow());

  ref.onDispose(() {
    timer.cancel();
    svc.unsubscribe();
  });
});
