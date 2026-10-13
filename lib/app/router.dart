import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_service.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/setup_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/tasks_screen.dart';
import 'app_shell.dart';

/// Re-evaluates GoRouter redirects whenever Supabase auth state changes.
///
/// We subscribe to Supabase's [GoTrueClient.onAuthStateChange] directly rather
/// than a Riverpod provider. After a successful OTP sign-in the session flips
/// from `null` to a value; this stream always emits on that transition, so
/// `notifyListeners()` fires and GoRouter re-runs its redirect (leaving
/// `/login`). A void-valued provider would set an equal state and never notify.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    if (SupabaseService.isConfigured) {
      _sub = SupabaseService.auth.onAuthStateChange
          .listen((_) => notifyListeners());
    }
  }

  StreamSubscription<AuthState>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

String? _redirect(GoRouterState state) {
  final location = state.matchedLocation;

  if (!SupabaseService.isConfigured) {
    return location == '/setup' ? null : '/setup';
  }

  final signedIn = SupabaseService.client.auth.currentSession != null;
  if (!signedIn) {
    return location == '/login' ? null : '/login';
  }
  if (location == '/login' || location == '/setup') {
    return '/';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (_, state) => _redirect(state),
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
