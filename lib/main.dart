import 'package:flutter/material.dart';
import 'package:livemeet/screens/login_screen.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kgfmeyypggnwwmpfvygv.supabase.co',
    // Keep the existing Supabase initialization outside this feature's scope.
    // ignore: deprecated_member_use
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnZm1leXlwZ2dud3dtcGZ2eWd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3Mjg1MTMsImV4cCI6MjEwODMwNDUxM30.5FAcKGQFn9TUG1Ex2a5cRptDQau_9mc-NNyG9o1hG9c',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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
      // opened on desktop/tablet.
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
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const MainScreen(),
    );
  }
}