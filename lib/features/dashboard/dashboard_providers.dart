import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/supabase/supabase_service.dart';
import '../tasks/task_providers.dart';

/// Day boundary used by the dashboard.
///
/// The day rolls over at a fixed local hour rather than midnight, so a digest
/// read at 02:00 still describes the day that has been running since the
/// previous morning instead of one that has not begun. The plan carries this
/// on `profiles.day_reset_hour`; until profile editing lands it is a constant,
/// and the value is threaded through [dayStartFor] so that change is local.
const int dayResetHour = 6;

/// When the current day began: the most recent [resetHour]:00 local time.
///
/// Pure and clock-free — callers supply `now` so this is testable at the
/// boundary rather than only whenever the app happens to run.
DateTime dayStartFor(DateTime now, {required int resetHour}) {
  final start = DateTime(now.year, now.month, now.day, resetHour);
  // Before the reset hour the day that is still running began yesterday.
  return now.isBefore(start) ? start.subtract(const Duration(days: 1)) : start;
}

/// Whether the morning digest should be offered on this open.
///
/// Once per day: any open after the reset hour, provided the digest was not
/// already shown for this day.
bool digestDue({
  required DateTime now,
  required DateTime? lastShown,
  required int resetHour,
}) {
  final start = dayStartFor(now, resetHour: resetHour);
  if (lastShown == null) return true;
  return lastShown.isBefore(start);
}

/// How much of today's work is done.
///
/// Counts tasks completed since the day began against everything due today or
/// earlier that is still open, so the bar answers "how much of today is left?"
/// rather than "how many tasks exist?".
@immutable
class TodayProgress {
  const TodayProgress({required this.done, required this.open});

  final int done;
  final int open;

  int get total => done + open;
  bool get isEmpty => total == 0;
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

final todayProgressProvider = Provider<TodayProgress>((ref) {
  final board = ref.watch(taskBoardProvider);
  final open = board.overdue.length + board.today.length;
  final dayStart = dayStartFor(DateTime.now(), resetHour: dayResetHour);

  final done = board.completed.where((t) {
    final at = t.completedAt;
    if (at == null) return false;
    // `completedAt` is a UTC instant; `dayStart` is a local wall-clock
    // midnight, so align on the local side before comparing.
    return !at.toLocal().isBefore(dayStart);
  }).length;

  return TodayProgress(done: done, open: open);
});

/// Name shown in the greeting.
///
/// Email OTP gives us little else, and a full address reads poorly in a
/// greeting, so the local part is used unless the provider sent a real name.
final greetingNameProvider = Provider<String?>((ref) {
  if (!SupabaseService.isConfigured) return null;
  final user = SupabaseService.auth.currentUser;
  if (user == null) return null;

  final metadata = user.userMetadata;
  final fullName = metadata?['full_name'] ?? metadata?['name'];
  if (fullName is String && fullName.trim().isNotEmpty) {
    return fullName.trim();
  }

  final email = user.email;
  if (email == null || email.isEmpty) return null;
  return email.split('@').first;
});

/// Owns whether the digest is currently offered.
///
/// Reads [sharedPreferencesProvider] rather than watching it: the digest is a
/// once-a-day thing, and rebuilding this on every preference write would
/// re-evaluate the clock for no benefit.
class DigestController extends Notifier<bool> {
  static const _shownForKey = 'digest_shown_for';

  @override
  bool build() => _isDue();

  bool _isDue() {
    final raw = ref.read(sharedPreferencesProvider).getString(_shownForKey);
    final lastShown = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    return digestDue(
      now: DateTime.now(),
      lastShown: lastShown,
      resetHour: dayResetHour,
    );
  }

  /// Records the digest as seen for this day and hides it.
  void dismiss() {
    ref
        .read(sharedPreferencesProvider)
        .setString(_shownForKey, DateTime.now().toIso8601String());
    state = false;
  }

  /// Re-checks the clock, for when the app stays open across the reset hour.
  void recheck() => state = _isDue();
}

final digestProvider =
    NotifierProvider<DigestController, bool>(DigestController.new);
