import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/profile_repository.dart';
import '../supabase/supabase_service.dart';
import '../utils/logger.dart';

/// Manages Supabase auth via email OTP (6-digit code). No password.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    if (!SupabaseService.isConfigured) return;
    final sub = SupabaseService.auth.onAuthStateChange.listen((_) {
      // Nudge listeners (router redirect) whenever auth state flips.
      state = AsyncData<void>(null);
    });
    ref.onDispose(sub.cancel);
  }

  Future<void> sendOtp(String email) async {
    await SupabaseService.auth.signInWithOtp(email: email.trim());
  }

  Future<void> verifyOtp(String email, String token) async {
    await SupabaseService.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
    // Best-effort: create the profile row on first sign-in.
    try {
      await ProfileRepository().ensureProfile();
    } catch (e) {
      log.warning('ensureProfile failed: $e');
    }
  }

  Future<void> signOut() async {
    await SupabaseService.auth.signOut();
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
