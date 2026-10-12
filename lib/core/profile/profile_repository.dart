import '../supabase/supabase_service.dart';

class ProfileRepository {
  /// Ensures a `profiles` row exists for the signed-in user (created on first
  /// sign-in). Safe to call repeatedly.
  Future<void> ensureProfile() async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) return;

    final existing = await SupabaseService.client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing == null) {
      await SupabaseService.client.from('profiles').insert({
        'id': user.id,
        'display_name': user.email,
        'day_reset_hour': 6,
      });
    }
  }
}
