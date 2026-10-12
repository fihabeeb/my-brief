import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase client.
///
/// Credentials are supplied at build time via dart-define:
///   flutter run --dart-define-from-file=config/dev.json
/// with keys SUPABASE_URL and SUPABASE_ANON_KEY.
class SupabaseService {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  /// Initialises Supabase only when configured. Returns true when the backend
  /// is available; false puts the app into "unconfigured" mode (Setup screen).
  static Future<bool> initIfConfigured() async {
    if (!isConfigured) return false;
    await Supabase.initialize(url: _url, publishableKey: _anonKey);
    return true;
  }
}
