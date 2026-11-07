import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/screens/login_screen.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/utils/app_error.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
    if (!dotenv.isEveryDefined(['SUPABASE_URL', 'SUPABASE_ANON_KEY'])) {
      throw StateError('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env.');
    }

    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
  } catch (error, stack) {
    final message = AppError.handle(error, stack, action: ErrorAction.startup);
    runApp(ProviderScope(child: MyApp(startupError: message)));
    return;
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.startupError});
  final String? startupError;

  // this widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Meet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF4F4F1),
        colorScheme: .fromSeed(seedColor: Color(0xFF111111)),
      ),
      // Responsive: limits very large phone font settings so layouts don't
      // break, and keeps the app a comfortable column (max 600 px wide) when
      
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.15,
            ),
          ),
          child: ColoredBox(
            color: const Color(0xFFF4F4F1),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: child,
              ),
            ),
          ),
        );
      },
      home: startupError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CustomText(text: startupError!, color: Colors.red),
                ),
              ),
            )
          : Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const MainScreen(),
    );
  }
}
