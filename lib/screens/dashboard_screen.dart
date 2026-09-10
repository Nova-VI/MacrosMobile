import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/daily_log.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import '../services/adaptive_coach_service.dart';
import '../theme/app_theme.dart';
import '../widgets/macro_donut_chart.dart';
import '../widgets/weekly_checkin_banner.dart';

enum DayPhase {
  morning('Morning', 5, 11),
  afternoon('Afternoon', 12, 17),
  evening('Evening', 18, 4);

  final String title;
  final int startHour;
  final int endHour;
  const DayPhase(this.title, this.startHour, this.endHour);
}

class DashboardScreen extends StatefulWidget {
  final Function(DateTime date, {DailyLog? editLog}) onNavigateToLogWithDate;

  const DashboardScreen({
    super.key,
    required this.onNavigateToLogWithDate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const int _initialPage = 5000;
  late final PageController _pageController;
  late final DateTime _today;
  late final ValueNotifier<DateTime> _selectedDateNotifier;
  final ValueNotifier<bool> _showRemainingNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selectedDateNotifier = ValueNotifier(_today);
    _pageController = PageController(initialPage: _initialPage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdaptiveCoachService().recomputeAndEvaluate();
    });

    FirestoreService().logsNotifier.addListener(_onDataChanged);
    FirestoreService().weightLogsNotifier.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    AdaptiveCoachService().recomputeAndEvaluate();
  }

  @override
  void dispose() {
    FirestoreService().logsNotifier.removeListener(_onDataChanged);
    FirestoreService().weightLogsNotifier.removeListener(_onDataChanged);
    _pageController.dispose();
    _selectedDateNotifier.dispose();
    _showRemainingNotifier.dispose();
    super.dispose();
  }

  DateTime _getDateForPage(int pageIndex) {
    return _today.add(Duration(days: pageIndex - _initialPage));
  }

  int _getPageForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return _initialPage + d.difference(_today).inDays;
  }

  String _getDateHeaderTitle(DateTime date) {
    final diff = DateTime(date.year, date.month, date.day).difference(_today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(date);
  }

  void _goToPageOffset(int offset) {
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      _pageController.page!.round() + offset,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickDate() async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateNotifier.value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: AppTheme.darkTheme.copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
              onSurface: AppColors.textMain,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final targetPage = _getPageForDate(picked);
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return ValueListenableBuilder<List<DailyLog>>(
      valueListenable: firestoreService.logsNotifier,
      builder: (context, allLogs, _) {
        return ValueListenableBuilder<UserProfile>(
          valueListenable: firestoreService.profileNotifier,
          builder: (context, profile, _) {
            return Column(
              children: [
                const WeeklyCheckInBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: _selectedDateNotifier,
                    builder: (context, currentDate, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textMain, size: 26),
                              onPressed: () => _goToPageOffset(-1),
                              tooltip: 'Previous Day',
                            ),
                            InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                child: Row(
                                  children: [
                                     Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      _getDateHeaderTitle(currentDate),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textMain,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textMain, size: 26),
                              onPressed: () => _goToPageOffset(1),
                              tooltip: 'Next Day',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (pageIndex) {
                      _selectedDateNotifier.value = _getDateForPage(pageIndex);
                    },
                    itemBuilder: (context, pageIndex) {
                      final pageDate = _getDateForPage(pageIndex);
                      final dateKey = DateFormat('yyyy-MM-dd').format(pageDate);
                      final dayLogs = allLogs.where((l) => l.date == dateKey).toList();

                      return _DashboardDayView(
                        key: ValueKey(dateKey),
                        pageDate: pageDate,
                        dayLogs: dayLogs,
                        profile: profile,
                        showRemainingNotifier: _showRemainingNotifier,
                        onNavigateToLogWithDate: widget.onNavigateToLogWithDate,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DashboardDayView extends StatefulWidget {
  final DateTime pageDate;
  final List<DailyLog> dayLogs;
  final UserProfile profile;
  final ValueNotifier<bool> showRemainingNotifier;
  final Function(DateTime date, {DailyLog? editLog}) onNavigateToLogWithDate;

  const _DashboardDayView({
    super.key,
    required this.pageDate,
    required this.dayLogs,
    required this.profile,
    required this.showRemainingNotifier,
    required this.onNavigateToLogWithDate,
  });

  @override
  State<_DashboardDayView> createState() => _DashboardDayViewState();
}

class _DashboardDayViewState extends State<_DashboardDayView> with AutomaticKeepAliveClientMixin {
  final Set<String> _expandedLogIds = {};
  final Set<DayPhase> _collapsedPhases = {};

  @override
  bool get wantKeepAlive => true;

  DayPhase _getLogPhase(DailyLog log) {
    if (log.loggedAt.isEmpty) return DayPhase.afternoon;
    try {
      final dt = DateTime.parse(log.loggedAt).toLocal();
      final h = dt.hour;
      if (h >= 5 && h < 12) return DayPhase.morning;
      if (h >= 12 && h < 18) return DayPhase.afternoon;
      return DayPhase.evening;
    } catch (_) {
      return DayPhase.afternoon;
    }
  }

  String _formatAmount(double val) {
    if (val % 1 == 0) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  void _copyLogToToday(DailyLog log) {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final newLog = DailyLog(
      id: '',
      date: todayStr,
      loggedAt: now.toIso8601String(), // Explicitly set to current time of day
      foodId: log.foodId,
      foodName: log.foodName,
      servingName: log.servingName,
      baseUnit: log.baseUnit,
      emoji: log.emoji,
      servings: log.servings,
      servingSizeG: log.servingSizeG,
      macros: log.macros,
      micros: log.micros,
    );

    // Instant optimistic write to in-memory list and non-blocking background Firestore write
    FirestoreService().addLog(newLog);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied "${log.foodName}" to Today!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:  BorderSide(color: AppColors.primary),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    double totalCals = 0;
    double totalPro = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (final log in widget.dayLogs) {
      totalCals += log.macros.calories;
      totalPro += log.macros.proteinG;
      totalCarbs += log.macros.carbsG;
      totalFat += log.macros.fatG;
    }

    final Map<DayPhase, List<DailyLog>> phaseMap = {
      DayPhase.morning: [],
      DayPhase.afternoon: [],
      DayPhase.evening: [],
    };

    for (final log in widget.dayLogs) {
      phaseMap[_getLogPhase(log)]!.add(log);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildOverviewCard(
          totalCals: totalCals,
          totalPro: totalPro,
          totalCarbs: totalCarbs,
          totalFat: totalFat,
        ),
        const SizedBox(height: 18),
        _buildSectionHeader(widget.dayLogs.length),
        const SizedBox(height: 10),

        if (widget.dayLogs.isEmpty)
          _buildEmptyState()
        else ...[
          if (phaseMap[DayPhase.morning]!.isNotEmpty)
            _buildPhaseSection(DayPhase.morning, phaseMap[DayPhase.morning]!),
          if (phaseMap[DayPhase.afternoon]!.isNotEmpty)
            _buildPhaseSection(DayPhase.afternoon, phaseMap[DayPhase.afternoon]!),
          if (phaseMap[DayPhase.evening]!.isNotEmpty)
            _buildPhaseSection(DayPhase.evening, phaseMap[DayPhase.evening]!),
        ],
      ],
    );
  }

  Widget _buildOverviewCard({
    required double totalCals,
    required double totalPro,
    required double totalCarbs,
    required double totalFat,
  }) {
    final dateKey = DateFormat('yyyy-MM-dd').format(widget.pageDate);
    final dayTarget = widget.profile.getTargetForDate(dateKey);

    final targetCals = dayTarget.targetCalories > 0 ? dayTarget.targetCalories : 2000.0;
    final targetPro = dayTarget.targetProteinG > 0 ? dayTarget.targetProteinG : 150.0;
    final targetCarbs = dayTarget.targetCarbsG > 0 ? dayTarget.targetCarbsG : 200.0;
    final targetFat = dayTarget.targetFatG > 0 ? dayTarget.targetFatG : 65.0;

    final calProgress = (totalCals / targetCals).clamp(0.0, 1.0);
    final isCalOver = totalCals > targetCals;
    final calDiff = (targetCals - totalCals).round();

    return ValueListenableBuilder<bool>(
      valueListenable: widget.showRemainingNotifier,
      builder: (context, showRemaining, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daily Targets',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMain,
                        letterSpacing: -0.3,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.showRemainingNotifier.value = !showRemaining;
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: showRemaining ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceHover,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: showRemaining ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
                          ),
                        ),
                        child: Text(
                          showRemaining ? 'Show Consumed' : 'Show Remaining',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: showRemaining ? AppColors.primary : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    MacroDonutChart(
                      proteinG: totalPro,
                      carbsG: totalCarbs,
                      fatG: totalFat,
                      totalCalories: totalCals,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          _buildMacroRow('Protein', totalPro, targetPro, AppColors.protein, showRemaining),
                          const SizedBox(height: 8),
                          _buildMacroRow('Carbs', totalCarbs, targetCarbs, AppColors.carbs, showRemaining),
                          const SizedBox(height: 8),
                          _buildMacroRow('Fat', totalFat, targetFat, AppColors.fat, showRemaining),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Calories Target',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            key: ValueKey(showRemaining),
                            showRemaining
                                ? (calDiff >= 0 ? '$calDiff kcal left' : '+${calDiff.abs()} kcal over')
                                : '${totalCals.round()} / ${targetCals.round()} kcal',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isCalOver ? AppColors.danger : AppColors.textMain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: calProgress),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: AppColors.background,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCalOver
                                  ? AppColors.danger
                                  : value >= 0.9
                                      ? AppColors.warning
                                      : AppColors.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMacroRow(String label, double current, double target, Color color, bool showRemaining) {
    final progress = (current / target).clamp(0.0, 1.0);
    final diff = (target - current).round();
    final isOver = current > target;

    final String displayVal;
    if (showRemaining) {
      displayVal = isOver ? '+${diff.abs()}g over' : '${diff}g left';
    } else {
      displayVal = '${current.round()}/${target.round()}g';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMain),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  key: ValueKey('$displayVal-$showRemaining'),
                  displayVal,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: (showRemaining && isOver) ? AppColors.warning : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 3.5,
                  backgroundColor: AppColors.surfaceHover,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Daily Logs',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
                letterSpacing: -0.3,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHover,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        TextButton.icon(
          onPressed: () => widget.onNavigateToLogWithDate(widget.pageDate),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Food', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildPhaseSection(DayPhase phase, List<DailyLog> logs) {
    double phaseCals = 0;
    double phasePro = 0;
    double phaseCarbs = 0;
    double phaseFat = 0;

    for (final l in logs) {
      phaseCals += l.macros.calories;
      phasePro += l.macros.proteinG;
      phaseCarbs += l.macros.carbsG;
      phaseFat += l.macros.fatG;
    }

    final isCollapsed = _collapsedPhases.contains(phase);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8, left: 2, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isCollapsed) {
                      _collapsedPhases.remove(phase);
                    } else {
                      _collapsedPhases.add(phase);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      Text(
                        phase.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textMain,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_formatAmount(phasePro)}p ',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.protein.withValues(alpha: 0.95)),
                        ),
                        TextSpan(
                          text: '${_formatAmount(phaseCarbs)}c ',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.carbs.withValues(alpha: 0.95)),
                        ),
                        TextSpan(
                          text: '${_formatAmount(phaseFat)}f',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.fat.withValues(alpha: 0.95)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${phaseCals.round()} kcal',
                      style:  TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isCollapsed)
          ...logs.map((log) => _buildCompactLogCard(log)),
      ],
    );
  }

  Widget _buildCompactLogCard(DailyLog log) {
    final isExpanded = _expandedLogIds.contains(log.id);
    final String servingLabel = log.servingName.isNotEmpty
        ? (log.servings == 1 ? log.servingName : '${log.servingName}s')
        : (log.servings == 1 ? 'serving' : 'servings');

    final servingsStr = log.servings % 1 == 0
        ? log.servings.toInt().toString()
        : log.servings.toStringAsFixed(1);
    final portionStr = '$servingsStr $servingLabel';

    final int cVal = log.macros.calories.round();
    final String pVal = _formatAmount(log.macros.proteinG);
    final String cCarbVal = _formatAmount(log.macros.carbsG);
    final String fVal = _formatAmount(log.macros.fatG);

    String timeStr = '';
    if (log.loggedAt.isNotEmpty) {
      try {
        timeStr = DateFormat('h:mm a').format(DateTime.parse(log.loggedAt).toLocal());
      } catch (_) {}
    }

    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          widget.onNavigateToLogWithDate(widget.pageDate, editLog: log);
          return false;
        } else {
          return await _showDeleteConfirmation(log);
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          FirestoreService().deleteLog(log.id);
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(left: 18),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isExpanded ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (isExpanded) {
                _expandedLogIds.remove(log.id);
              } else {
                _expandedLogIds.add(log.id);
              }
            });
          },
          onLongPress: () {
            HapticFeedback.heavyImpact();
            _copyLogToToday(log);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12, left: 2),
                      child: Text(
                        log.emoji.isNotEmpty ? log.emoji : '🍽️',
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.foodName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$cVal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                TextSpan(
                                  text: 'cal  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary.withValues(alpha: 0.95),
                                  ),
                                ),
                                TextSpan(
                                  text: '$pVal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                TextSpan(
                                  text: 'p  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.protein.withValues(alpha: 0.95),
                                  ),
                                ),
                                TextSpan(
                                  text: '$cCarbVal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                TextSpan(
                                  text: 'c  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.carbs.withValues(alpha: 0.95),
                                  ),
                                ),
                                TextSpan(
                                  text: '$fVal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                TextSpan(
                                  text: 'f',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.fat.withValues(alpha: 0.95),
                                  ),
                                ),
                                TextSpan(
                                  text: ' • $portionStr',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timeStr.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        const SizedBox(height: 2),
                        IconButton(
                          icon: const Icon(Icons.edit_note_rounded, size: 22, color: AppColors.textMuted),
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => widget.onNavigateToLogWithDate(widget.pageDate, editLog: log),
                          tooltip: 'Edit / Delete Log',
                        ),
                      ],
                    ),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
                    ),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _buildMicroItem('Fiber', '${log.micros.fiberG.toStringAsFixed(1)}g'),
                        _buildMicroItem('Sugar', '${log.micros.sugarG.toStringAsFixed(1)}g'),
                        _buildMicroItem('Sodium', '${log.micros.sodiumMg.round()}mg'),
                        _buildMicroItem('Sat Fat', '${log.micros.saturatedFatG.toStringAsFixed(1)}g'),
                        _buildMicroItem('Cholesterol', '${log.micros.cholesterolMg.round()}mg'),
                        _buildMicroItem('Potassium', '${log.micros.potassiumMg.round()}mg'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicroItem(String label, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        Text(val, style: const TextStyle(fontSize: 11, color: AppColors.textMain, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:  Icon(Icons.fastfood_rounded, size: 24, color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          const Text(
            'No Food Logged Yet',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textMain),
          ),
          const SizedBox(height: 4),
          const Text(
            'Swipe between days or log your meals to track your daily progress.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => widget.onNavigateToLogWithDate(widget.pageDate),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log Food Now'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(150, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(DailyLog log) {
    HapticFeedback.mediumImpact();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Entry', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800)),
        content: Text('Remove "${log.foodName}" from this day\'s log?', style: const TextStyle(color: AppColors.textMuted)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textMain,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}