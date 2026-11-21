import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recrea_app/features/attendance/attendance_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:recrea_app/features/payments/payment_parent_view.dart';
import 'package:recrea_app/features/payments/payments_admin_view.dart';
import 'package:recrea_app/features/enrollment/enrollment_parent_view.dart';
import 'package:recrea_app/features/supplies/supplies_parent_view.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/home_screen.dart';
import '../../features/enrollment/enrollment_screen.dart';
import '../../features/agenda/calendar_screen.dart';
import '../../features/agenda/agenda_screen.dart';
import '../../features/profile/profile_screen.dart';
import 'responsive_shell.dart';

final routerProvider = Provider((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggingIn = state.uri.toString() == '/login';

      if (session == null && !isLoggingIn) return '/login';
      if (session != null && isLoggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      
      // LA MAGIA: StatefulShellRoute mantiene vivas las pantallas en memoria (0ms de recarga)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ResponsiveLayoutShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (context, state) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (context, state) => const CalendarScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/payments', builder: (context, state) => const PaymentsAdminView())]),
          StatefulShellBranch(routes: [GoRoute(path: '/payments_parent', builder: (context, state) => const PaymentsParentView())]),
          StatefulShellBranch(routes: [GoRoute(path: '/enrollment', builder: (context, state) => const EnrollmentScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/enrollment_parent', builder: (context, state) => const EnrollmentParentView())]),
          StatefulShellBranch(routes: [GoRoute(path: '/supplies', builder: (context, state) => const SuppliesParentView())]),
          StatefulShellBranch(routes: [GoRoute(path: '/attendance', builder: (context, state) => const AttendanceScreen())]),
        ],
      ),
    ],
  );
});