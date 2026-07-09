import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/contacts_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/authentication.dart';
import 'screens/link_management_screen.dart';
import 'screens/scheduled_messages_screen.dart';
import 'screens/add_schedule_screen.dart';
import 'screens/onboard_screen.dart';
import 'screens/session_detail_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String auth = '/auth';
  static const String createEvent = '/create-event';
  static const String links = '/links';
  static const String scheduled = '/scheduled';
  static const String addSchedule = '/scheduled/add';
  static const String onboarding = '/onboarding';
  static const String sessionDetail = '/scheduled/session';

  // Routes that don't require an authenticated session.
  static const Set<String> _publicRoutes = {
    splash,
    auth,
    onboarding,
  };

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

  // Guards every navigation attempt: if the user hasn't logged in or
  // registered yet (no `isLoggedIn` flag in the settings box), any attempt
  // to reach a protected route (home, settings, create-event, etc.) is
  // bounced back to the auth screen instead. Splash/auth/onboarding stay
  // reachable so the user can actually get to sign-in in the first place.
  static String? _authGuard(BuildContext context, GoRouterState state) {
    final settingsBox = Hive.box('settings');
    final bool isLoggedIn = settingsBox.get('isLoggedIn', defaultValue: false) as bool;

    final String location = state.matchedLocation;
    final bool isPublicRoute = _publicRoutes.contains(location);

    // Already logged in and sitting on the auth screen? Send them home
    // instead of letting them re-visit the login/register form.
    if (isLoggedIn && location == auth) {
      return home;
    }

    // Not logged in and trying to reach a protected route? Send them to
    // auth instead.
    if (!isLoggedIn && !isPublicRoute) {
      return auth;
    }

    // No redirect needed.
    return null;
  }

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    redirect: _authGuard,
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
        path: '$sessionDetail/:id',
        name: 'sessionDetail',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: SessionDetailScreen(sessionId: state.pathParameters['id']!),
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
        path: createEvent, // Keeping path same to avoid deep link issues if any
        name: 'contacts',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const ContactsScreen(),
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
      GoRoute(
        path: onboarding,
        name: 'onboarding',
        pageBuilder: (context, state) => _buildSmoothTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
    ],
  );
}