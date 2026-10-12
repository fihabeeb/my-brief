import 'package:flutter/material.dart';

/// Shown when Supabase credentials are missing. Keeps the app runnable on both
/// platforms before any backend exists.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Connect your Supabase backend',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'My Brief runs without a backend for now, but sign-in and sync '
                  'need Supabase. Credentials are supplied at build time:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'flutter run --dart-define-from-file=config/dev.json',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _step(theme, '1.', 'Create a Supabase project (free tier).'),
                _step(theme, '2.', 'Copy config/dev.example.json to config/dev.json and fill in SUPABASE_URL and SUPABASE_ANON_KEY.'),
                _step(theme, '3.', 'Run supabase/migrations/0001_init.sql in the Supabase SQL editor.'),
                _step(theme, '4.', 'In Authentication → Providers, enable Email (with OTP, confirmation off).'),
                const SizedBox(height: 8),
                Text(
                  'See supabase/README.md for the full walkthrough.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Text(n, style: theme.textTheme.bodyMedium)),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
