import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/daily_log.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/macro_donut_chart.dart';

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
  final VoidCallback onNavigateToLog;

  const DashboardScreen({
    super.key,
    required this.onNavigateToLog,
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
  }

  @override
  void dispose() {
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
            colorScheme: const ColorScheme.dark(
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
                                    const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.primary),
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
                        dayLogs: dayLogs,
                        profile: profile,
                        showRemainingNotifier: _showRemainingNotifier,
                        onNavigateToLog: widget.onNavigateToLog,
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
  final List<DailyLog> dayLogs;
  final UserProfile profile;
  final ValueNotifier<bool> showRemainingNotifier;
  final VoidCallback onNavigateToLog;

  const _DashboardDayView({
    super.key,
    required this.dayLogs,
    required this.profile,
    required this.showRemainingNotifier,
    required this.onNavigateToLog,
  });

  @override
  State<_DashboardDayView> createState() => _DashboardDayViewState();
}

class _DashboardDayViewState extends State<_DashboardDayView> with AutomaticKeepAliveClientMixin {
  final Set<String> _expandedLogIds = {};

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
    final targetCals = widget.profile.targetCalories > 0 ? widget.profile.targetCalories : 2000.0;
    final targetPro = widget.profile.targetProteinG > 0 ? widget.profile.targetProteinG : 150.0;
    final targetCarbs = widget.profile.targetCarbsG > 0 ? widget.profile.targetCarbsG : 200.0;
    final targetFat = widget.profile.targetFatG > 0 ? widget.profile.targetFatG : 65.0;

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
                          _buildMacroRow('Protein', totalPro, targetPro, AppColors.primary, showRemaining),
                          const SizedBox(height: 8),
                          _buildMacroRow('Carbs', totalCarbs, targetCarbs, AppColors.secondary, showRemaining),
                          const SizedBox(height: 8),
                          _buildMacroRow('Fat', totalFat, targetFat, AppColors.warning, showRemaining),
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
          onPressed: widget.onNavigateToLog,
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
    for (final l in logs) {
      phaseCals += l.macros.calories;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8, left: 2, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${phaseCals.round()} kcal',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...logs.map((log) => _buildCompactLogCard(log)),
      ],
    );
  }

  Widget _buildCompactLogCard(DailyLog log) {
    final isExpanded = _expandedLogIds.contains(log.id);
    String servingLabel = log.servingName.isNotEmpty
        ? (log.servings == 1 ? log.servingName : '${log.servingName}s')
        : (log.servings == 1 ? 'serving' : 'servings');

    String timeStr = '';
    if (log.loggedAt.isNotEmpty) {
      try {
        timeStr = DateFormat('hh:mm a').format(DateTime.parse(log.loggedAt));
      } catch (_) {}
    }

    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await _showDeleteConfirmation(log);
      },
      onDismissed: (direction) {
        FirestoreService().deleteLog(log.id);
      },
      background: Container(
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
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                log.emoji.isNotEmpty ? log.emoji : '🍽️',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  log.foodName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMain,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${timeStr.isNotEmpty ? '$timeStr • ' : ''}${log.servings % 1 == 0 ? log.servings.toInt() : log.servings.toStringAsFixed(1)} $servingLabel (${log.servingSizeG.round()}${log.baseUnit})',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () async {
                        final confirm = await _showDeleteConfirmation(log);
                        if (confirm == true) {
                          await FirestoreService().deleteLog(log.id);
                        }
                      },
                      tooltip: 'Delete Log',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildCompactCapsule('Calories', '${log.macros.calories.round()}', color: AppColors.primary),
                    const SizedBox(width: 6),
                    _buildCompactCapsule('Protein', '${log.macros.proteinG.toStringAsFixed(1)}g', color: AppColors.primary),
                    const SizedBox(width: 6),
                    _buildCompactCapsule('Carbs', '${log.macros.carbsG.toStringAsFixed(1)}g', color: AppColors.secondary),
                    const SizedBox(width: 6),
                    _buildCompactCapsule('Fat', '${log.macros.fatG.toStringAsFixed(1)}g', color: AppColors.warning),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: isExpanded
                      ? Container(
                          margin: const EdgeInsets.only(top: 10),
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
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCapsule(String label, String value, {required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4.5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
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
            child: const Icon(Icons.fastfood_rounded, size: 24, color: AppColors.primary),
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
            onPressed: widget.onNavigateToLog,
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