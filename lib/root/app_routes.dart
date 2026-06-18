import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/create_event_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/authentication.dart';
import 'screens/link_management_screen.dart';
import 'screens/scheduled_messages_screen.dart';
import 'screens/add_schedule_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String auth = '/auth';
  static const String createEvent = '/create-event';
  static const String links = '/links';
  static const String scheduled = '/scheduled';
  static const String addSchedule = '/scheduled/add';

  static Page<dynamic> _buildSmoothTransitionPage({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideIn = Tween<Offset>(
          begin: const Offset(0.0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        final fadeIn = CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        );

        return FadeTransition(
          opacity: fadeIn,
          child: SlideTransition(
            position: slideIn,
            child: child,
          ),
        );
      },
    );
  }

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    routes: [
      GoRoute(
        path: splash,
        name: 'splash',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: auth,
        name: 'auth',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const SynCalAuthPage(),
        ),
      ),
      GoRoute(
        path: home,
        name: 'home',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
        ),
      ),
      GoRoute(
        path: settings,
        name: 'settings',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: createEvent,
        name: 'createEvent',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const CreateEventScreen(),
        ),
      ),
      GoRoute(
        path: links,
        name: 'links',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const LinkManagementScreen(),
        ),
      ),
      GoRoute(
        path: scheduled,
        name: 'scheduled',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const ScheduledMessagesScreen(),
        ),
      ),
      GoRoute(
        path: addSchedule,
        name: 'addSchedule',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const AddScheduleScreen(),
        ),
      ),
    ],
  );
}