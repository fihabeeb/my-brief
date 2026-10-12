import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/supabase/supabase_service.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/setup_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/tasks_screen.dart';
import 'app_shell.dart';

/// Re-evaluates GoRouter redirects whenever auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this.ref) {
    _sub = ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
  late final ProviderSubscription<AsyncValue<void>> _sub;

  @override
  void dispose() {
    _sub.close();
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
  final refresh = _AuthRefresh(ref);
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
