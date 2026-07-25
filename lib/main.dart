import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'navigation/app_router.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization or auth failed: $e');
  }

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Global Error Handler
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0F1115),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 48),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(
    const ProviderScope(
      child: ConveneApp(),
    ),
  );
}

class ConveneApp extends ConsumerWidget {
  const ConveneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Block rendering any real screen until Firebase Auth's first snapshot
    // arrives - otherwise widgets that read appUserProvider before then would
    // see "nobody signed in" and briefly attribute data to a fallback identity.
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (authState.isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: 'Convene',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
