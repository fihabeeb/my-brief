import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybrief/app/app.dart';

void main() {
  testWidgets('renders setup screen when Supabase is unconfigured',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    // No credentials in tests => the app routes to the setup screen.
    expect(find.text('Connect your Supabase backend'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
