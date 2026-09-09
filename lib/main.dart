import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await AuthService().initialize();
  await ThemeManager.init();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    FirestoreService().initializeListeners(currentUser.uid);
  }

  runApp(const MacroTrackerApp());
}

class MacroTrackerApp extends StatelessWidget {
  const MacroTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeManager.notifier,
      builder: (context, _, __) {
        return MaterialApp(
          title: 'MacroTracker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              if (snapshot.hasData && snapshot.data != null) {
                final uid = snapshot.data!.uid;

                return FutureBuilder<bool>(
                  future: AuthService().checkIsOnboardingCompleted(uid),
                  builder: (context, onboardingSnap) {
                    if (onboardingSnap.connectionState == ConnectionState.waiting) {
                      return Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      );
                    }

                    return ValueListenableBuilder<bool>(
                      valueListenable: AuthService.onboardingCompletedNotifier,
                      builder: (context, isCompleted, _) {
                        if (isCompleted) {
                          return const MainNavigationScreen();
                        }
                        return const OnboardingScreen();
                      },
                    );
                  },
                );
              }
              return const AuthScreen();
            },
          ),
        );
      },
    );
  }
}