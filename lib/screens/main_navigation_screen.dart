import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/daily_log.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'log_food_screen.dart';
import 'recipes_library_screen.dart';
import 'weight_tracker_screen.dart';
import 'stats_screen.dart';
import 'profile_settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  DateTime _targetLogDate = DateTime.now();
  DailyLog? _editingLog;

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentIndex = index;
        if (index != 1) {
          _editingLog = null; // Reset edit mode when leaving the log tab
        }
      });
    }
  }

  void _openLogScreen(DateTime date, {DailyLog? editLog}) {
    HapticFeedback.mediumImpact();
    setState(() {
      _targetLogDate = date;
      _editingLog = editLog;
      _currentIndex = 1; // Switch to Log tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardScreen(
        onNavigateToLogWithDate: (date, {editLog}) => _openLogScreen(date, editLog: editLog),
      ),
      LogFoodScreen(
        key: ValueKey('log_food_${_targetLogDate.toIso8601String()}_${_editingLog?.id ?? 'new'}'),
        initialDate: _targetLogDate,
        editLog: _editingLog,
        onLogCompleted: () {
          setState(() {
            _editingLog = null;
            _currentIndex = 0; // Return to Home on complete
          });
        },
      ),
      const RecipesLibraryScreen(),
      const WeightTrackerScreen(),
      const StatsScreen(),
    ];

    final List<String> titles = const [
      'MacroTracker',
      'Log Food',
      'Foods & Recipes',
      'Weight Tracker',
      'Stats & Insights',
    ];

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    titles[_currentIndex],
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMain,
                      letterSpacing: -0.6,
                    ),
                  ),
                  // User Avatar & Profile Access
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: StreamBuilder<User?>(
                        stream: AuthService().authStateChanges,
                        builder: (context, snap) {
                          final photoUrl = snap.data?.photoURL;
                          if (photoUrl != null && photoUrl.isNotEmpty) {
                            return CircleAvatar(
                              radius: 17,
                              backgroundImage: NetworkImage(photoUrl),
                            );
                          }
                          return Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: AppColors.primary,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
            ),
          ],
        ),
      ),
      // Floating Minimalist Navigation Bar with True Circular Indicators
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCircularNavItem(
              index: 0,
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              tooltip: 'Home',
            ),
            _buildCircularNavItem(
              index: 1,
              icon: Icons.add_circle_outline_rounded,
              selectedIcon: Icons.add_circle_rounded,
              tooltip: 'Log Food',
            ),
            _buildCircularNavItem(
              index: 2,
              icon: Icons.restaurant_menu_rounded,
              selectedIcon: Icons.restaurant_rounded,
              tooltip: 'Foods & Recipes',
            ),
            _buildCircularNavItem(
              index: 3,
              icon: Icons.monitor_weight_outlined,
              selectedIcon: Icons.monitor_weight_rounded,
              tooltip: 'Weight Tracker',
            ),
            _buildCircularNavItem(
              index: 4,
              icon: Icons.insights_rounded,
              selectedIcon: Icons.analytics_rounded,
              tooltip: 'Stats & Insights',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String tooltip,
  }) {
    final isSelected = _currentIndex == index;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _onTabSelected(index),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Icon(
            isSelected ? selectedIcon : icon,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
            size: 23,
          ),
        ),
      ),
    );
  }
}