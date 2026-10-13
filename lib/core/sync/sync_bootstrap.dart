import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_service.dart';
import 'sync_service.dart';

/// Starts sync when a user signs in, and stops when they sign out.
///
/// Subscribes to Supabase's [GoTrueClient.onAuthStateChange] directly (the same
/// reliable pattern the router uses) so it reacts to sign-in regardless of
/// provider value-equality. On sign-in: push offline edits, pull, then start a
/// realtime subscription plus a periodic pull as a safety net.
final syncBootstrapProvider = Provider<void>((ref) {
  if (!SupabaseService.isConfigured) return;

  final svc = ref.read(syncServiceProvider);
  StreamSubscription<AuthState>? sub;
  Timer? timer;

  void start() {
    svc.subscribe();
    svc.syncNow();
    timer ??= Timer.periodic(const Duration(minutes: 2), (_) => svc.syncNow());
  }

  void stop() {
    timer?.cancel();
    timer = null;
    svc.unsubscribe();
  }

  sub = SupabaseService.auth.onAuthStateChange.listen((event) {
    if (event.session != null) {
      start();
    } else {
      stop();
    }
  });

  ref.onDispose(() {
    sub?.cancel();
    timer?.cancel();
    svc.unsubscribe();
  });
});
