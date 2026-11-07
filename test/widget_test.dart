import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/main.dart' as app;
import 'package:livemeet/screens/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _preferences = MethodChannel('plugins.flutter.io/shared_preferences');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    rootBundle.evict('.env');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _preferences,
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_preferences, null);
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    dotenv.clean();
  });

  testWidgets(
    'Startup loads bundled config, initializes Supabase and Riverpod',
    (tester) async {
      await tester.runAsync(app.main);
      addTearDown(() => Supabase.instance.dispose());
      await tester.pumpAndSettle();

      expect(dotenv.isInitialized, isTrue);
      expect(Supabase.instance.isInitialized, isTrue);
      // Boolean comparisons keep credential values out of assertion output.
      expect(
        Supabase.instance.client.rest.url ==
            '${dotenv.get('SUPABASE_URL')}/rest/v1',
        isTrue,
      );
      expect(
        Supabase.instance.client.auth.headers['apikey'] ==
            dotenv.get('SUPABASE_ANON_KEY'),
        isTrue,
      );
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(find.byType(ProviderScope), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final missing in ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    testWidgets('Startup shows a safe error for missing $missing', (
      tester,
    ) async {
      final config = {
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'sb_publishable_test-only',
      }..remove(missing);
      binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        message,
      ) async {
        if (utf8.decode(message!.buffer.asUint8List()) != '.env') return null;
        return ByteData.sublistView(
          utf8.encode(
            config.entries.map((e) => '${e.key}=${e.value}').join('\n'),
          ),
        );
      });

      await tester.runAsync(app.main);
      await tester.pumpAndSettle();
      expect(find.byType(app.MyApp), findsOneWidget);
      expect(find.textContaining('Unable to start Live Meet'), findsOneWidget);
      expect(find.textContaining('SUPABASE_'), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
