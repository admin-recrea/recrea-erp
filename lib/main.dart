import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recrea_app/features/auth/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui'; 
import 'core/constants/app_theme.dart';
import 'core/constants/supabase_keys.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseKeys.url,
    anonKey: SupabaseKeys.anonKey,
  );
  runApp(const ProviderScope(child: RecreaApp()));
}

class RecreaApp extends ConsumerWidget {
  const RecreaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Centro Infantil Recrea',
      debugShowCheckedModeBanner: false,
      theme: RecreaTheme.lightTheme,
      routerConfig: goRouter,
      // 2. <-- AÑADE ESTO PARA PERMITIR DESLIZAR CARRUSELES CON MOUSE EN WEB
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      
    );
  }
}