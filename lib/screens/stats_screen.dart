import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/daily_log.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  String _currentRange = '7'; // Default 7 days
  String _currentMetric = 'calories'; // 'calories', 'protein', 'carbs', 'fat'
  bool _isMicrosExpanded = true;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DailyLog>>(
      valueListenable: _firestoreService.logsNotifier,
      builder: (context, allLogs, _) {
        return ValueListenableBuilder<UserProfile>(
          valueListenable: _firestoreService.profileNotifier,
          builder: (context, profile, _) {
            final statsData = _computeAggregates(allLogs, profile);

            return Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Period Filter Chips
                    _buildRangeFilterRow(),
                    const SizedBox(height: 14),

                    // Creative Metric: Adherence Index Banner
                    _buildAdherenceBanner(statsData, profile),
                    const SizedBox(height: 14),

                    // Island 1: Meta Summary Card (Days Tracked, Total Logs, Avg Logs)
                    _buildMetaCard(statsData),
                    const SizedBox(height: 14),

                    // Island 2: 4 Goal-Aware Summary Cards Grid
                    _buildSummaryCardsGrid(statsData, profile),
                    const SizedBox(height: 14),

                    // Island 3: Clean Daily Trend Chart (No black bars, clean Y-axis)
                    _buildDailyTrendCard(statsData, profile),
                    const SizedBox(height: 14),

                    // Island 4: Macro Distribution Donut Card
                    _buildMacroBreakdownCard(statsData),
                    const SizedBox(height: 14),

                    // Island 5: Balanced Dual-Column Micronutrient Matrix
                    _buildMicronutrientCard(statsData),
                    const SizedBox(height: 14),

                    // Island 6: Automated Insights Card
                    _buildInsightsCard(statsData, profile),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRangeFilterRow() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildRangeChip('7 Days', '7'),
          const SizedBox(width: 8),
          _buildRangeChip('30 Days', '30'),
          const SizedBox(width: 8),
          _buildRangeChip('90 Days', '90'),
          const SizedBox(width: 8),
          _buildRangeChip('All Time', 'all'),
        ],
      ),
    );
  }

  Widget _buildRangeChip(String label, String rangeKey) {
    final isSelected = _currentRange == rangeKey;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentRange = rangeKey);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  // Creative Metric: Adherence & Consistency Score
  Widget _buildAdherenceBanner(_StatsData data, UserProfile profile) {
    final score = _calculateAdherenceScore(data, profile);
    final goalLabel = profile.goalTypeLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$score%',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Diet Adherence Score',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMain),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        profile.goalType.name.toUpperCase(),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  score >= 85
                      ? 'Target locked! Hitting your goals for $goalLabel.'
                      : score >= 65
                          ? 'Consistent progress. Watch your protein minimums and portion sizes.'
                          : 'Adherence slipping. Prioritize protein and stay within your target energy window.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Smart Non-Linear Scoring Engine ---

  int _calculateAdherenceScore(_StatsData data, UserProfile profile) {
    if (data.daysWithData == 0) return 0;

    final targetCal = profile.targetCalories > 0 ? profile.targetCalories : 2000.0;
    final targetPro = profile.targetProteinG > 0 ? profile.targetProteinG : 150.0;
    final goalType = profile.goalType;

    double cumulativeDailyScore = 0.0;
    int evaluatedDays = 0;

    for (final day in data.dailyMap.values) {
      if (day.calories > 0) {
        final proScore = _computeProteinScore(day.proteinG, targetPro);
        final calScore = _computeCalorieScore(day.calories, targetCal, goalType);

        // Day Score: Protein modifies calories. If calories are blown, day score drops to 0.
        final dayScore = calScore * (0.25 + (0.75 * proScore));

        cumulativeDailyScore += dayScore;
        evaluatedDays++;
      }
    }

    if (evaluatedDays == 0) return 0;

    // Component 1: Daily Habit & Consistency (65% Weight)
    final dailyConsistencyScore = cumulativeDailyScore / evaluatedDays;

    // Component 2: Overall Net Energy Budget (35% Weight)
    // Evaluates whether your net average stayed within your goal direction
    final netEnergyScore = _computeCalorieScore(data.avgCalories, targetCal, goalType);

    // Weighted blend: Outliers hurt the score proportionately without zeroing out good days
    final finalScore = (dailyConsistencyScore * 0.50) + (netEnergyScore * 0.50);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // Protein Curve: Over-target is NEVER penalized. Under-target follows a non-linear decay curve.
  double _computeProteinScore(double actual, double target) {
    if (actual >= target) return 1.0; // Extra protein is 100% rewarded

    final deficit = target - actual;
    if (deficit >= 55.0) return 0.0; // 55g+ under target drops score to 0

    // Non-linear decay: (deficit / 55)^2.4
    final penalty = math.pow(deficit / 55.0, 2.4).toDouble();
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  // Calorie Curve: Objective-aware (Cut vs Bulk vs Maintain)
  double _computeCalorieScore(double actual, double target, GoalType goalType) {
    final diff = actual - target;
    double effectiveError;

    switch (goalType) {
      case GoalType.cut:
        if (diff <= 0) {
          // Under target on a cut: High tolerance (0.55).
          // Eating deeper into a deficit still serves the primary fat-loss goal.
          effectiveError = diff.abs() * 0.55;
        } else {
          // Over target on a cut: Strict penalty (1.35).
          // Overeating wipes out the calorie deficit.
          effectiveError = diff * 1.35;
        }
        break;

      case GoalType.bulk:
        if (diff >= 0) {
          // Over target on a bulk: Moderate tolerance (1.0).
          // Allows a clean surplus, but penalizes dirty bulk fat spillover.
          effectiveError = diff * 1.0;
        } else {
          // Under target on a bulk: Strict penalty (1.35).
          // Undereating stops muscle hypertrophy.
          effectiveError = diff.abs() * 1.35;
        }
        break;

      case GoalType.maintain:
        effectiveError = diff.abs(); // Symmetric for maintenance
        break;
    }

    if (effectiveError >= 500.0) return 0.0;

    final penalty = math.pow(effectiveError / 500.0, 2.2).toDouble();
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  Widget _buildMetaCard(_StatsData data) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetaItem('${data.daysWithData}', 'Days Tracked'),
          Container(width: 1, height: 32, color: AppColors.border),
          _buildMetaItem('${data.totalLogsCount}', 'Total Logs'),
          Container(width: 1, height: 32, color: AppColors.border),
          _buildMetaItem(
            data.daysWithData > 0 ? (data.totalLogsCount / data.daysWithData).toStringAsFixed(1) : '0',
            'Avg Logs/Day',
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textMain, letterSpacing: -0.4),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4),
        ),
      ],
    );
  }

  Widget _buildSummaryCardsGrid(_StatsData data, UserProfile profile) {
    final targetCals = profile.targetCalories > 0 ? profile.targetCalories : 2000.0;
    final targetPro = profile.targetProteinG > 0 ? profile.targetProteinG : 150.0;
    final targetCarbs = profile.targetCarbsG > 0 ? profile.targetCarbsG : 200.0;
    final targetFat = profile.targetFatG > 0 ? profile.targetFatG : 65.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                label: 'Avg Calories',
                value: '${data.avgCalories.round()} kcal',
                target: 'Target: ${targetCals.round()} kcal',
                progress: (data.avgCalories / targetCals).clamp(0.0, 1.0),
                color: AppColors.primary,
                status: _getCalorieStatus(data.avgCalories, targetCals, profile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                label: 'Avg Protein',
                value: '${data.avgProtein.toStringAsFixed(1)}g',
                target: 'Target: ${targetPro.round()}g',
                progress: (data.avgProtein / targetPro).clamp(0.0, 1.0),
                color: AppColors.protein,
                status: _getProteinStatus(data.avgProtein, targetPro, data.daysWithData),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                label: 'Avg Carbs',
                value: '${data.avgCarbs.toStringAsFixed(1)}g',
                target: 'Target: ${targetCarbs.round()}g',
                progress: (data.avgCarbs / targetCarbs).clamp(0.0, 1.0),
                color: AppColors.carbs,
                status: const _StatusInfo('Tracked', AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                label: 'Avg Fat',
                value: '${data.avgFat.toStringAsFixed(1)}g',
                target: 'Target: ${targetFat.round()}g',
                progress: (data.avgFat / targetFat).clamp(0.0, 1.0),
                color: AppColors.fat,
                status: const _StatusInfo('Tracked', AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required String target,
    required double progress,
    required Color color,
    required _StatusInfo status,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: status.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textMain, letterSpacing: -0.3),
          ),
          const SizedBox(height: 2),
          Text(
            target,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.background,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTrendCard(_StatsData data, UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Intake Trend',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _currentMetric,
                    dropdownColor: AppColors.surface,
                    style: TextStyle(color: AppColors.textMain, fontSize: 12, fontWeight: FontWeight.w700),
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 16),
                    onChanged: (val) {
                      if (val != null) setState(() => _currentMetric = val);
                    },
                    items: const [
                      DropdownMenuItem(value: 'calories', child: Text('Calories')),
                      DropdownMenuItem(value: 'protein', child: Text('Protein')),
                      DropdownMenuItem(value: 'carbs', child: Text('Carbs')),
                      DropdownMenuItem(value: 'fat', child: Text('Fat')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 220,
            child: data.dailyDateKeys.isEmpty
                ? const Center(
                    child: Text('No log data available for this range.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  )
                : _buildCleanTrendBarChart(data, profile),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanTrendBarChart(_StatsData data, UserProfile profile) {
    final dateKeys = data.dailyDateKeys;
    final barGroups = <BarChartGroupData>[];

    double targetValue = 2000.0;
    Color primaryBarColor = AppColors.primary;
    double intervalStep = 500;

    if (_currentMetric == 'calories') {
      targetValue = profile.targetCalories > 0 ? profile.targetCalories : 2000.0;
      primaryBarColor = AppColors.primary;
      intervalStep = 500;
    } else if (_currentMetric == 'protein') {
      targetValue = profile.targetProteinG > 0 ? profile.targetProteinG : 150.0;
      primaryBarColor = AppColors.protein;
      intervalStep = 50;
    } else if (_currentMetric == 'carbs') {
      targetValue = profile.targetCarbsG > 0 ? profile.targetCarbsG : 200.0;
      primaryBarColor = AppColors.carbs;
      intervalStep = 50;
    } else if (_currentMetric == 'fat') {
      targetValue = profile.targetFatG > 0 ? profile.targetFatG : 65.0;
      primaryBarColor = AppColors.fat;
      intervalStep = 25;
    }

    // Find actual highest bar
    double maxBarValue = 0;
    for (int i = 0; i < dateKeys.length; i++) {
      final key = dateKeys[i];
      final day = data.dailyMap[key];
      double barVal = 0;
      if (day != null) {
        if (_currentMetric == 'calories') barVal = day.calories;
        if (_currentMetric == 'protein') barVal = day.proteinG;
        if (_currentMetric == 'carbs') barVal = day.carbsG;
        if (_currentMetric == 'fat') barVal = day.fatG;
      }
      if (barVal > maxBarValue) maxBarValue = barVal;
    }

    // Snap ceiling to clean interval to prevent label collision
    final referencePeak = math.max(maxBarValue, targetValue);
    final ceiling = (math.max(referencePeak * 1.15, intervalStep * 2) / intervalStep).ceil() * intervalStep;

    for (int i = 0; i < dateKeys.length; i++) {
      final key = dateKeys[i];
      final day = data.dailyMap[key];

      double barVal = 0;
      if (day != null) {
        if (_currentMetric == 'calories') barVal = day.calories;
        if (_currentMetric == 'protein') barVal = day.proteinG;
        if (_currentMetric == 'carbs') barVal = day.carbsG;
        if (_currentMetric == 'fat') barVal = day.fatG;
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: barVal,
              color: primaryBarColor,
              width: dateKeys.length > 14 ? 6 : (dateKeys.length == 7 ? 18 : 12),
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: ceiling,
        barGroups: barGroups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: intervalStep,
          getDrawingHorizontalLine: (val) {
            return FlLine(
              color: AppColors.border.withValues(alpha: 0.35),
              strokeWidth: 1,
            );
          },
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: targetValue,
              color: AppColors.danger.withValues(alpha: 0.75),
              strokeWidth: 1.5,
              dashArray: [6, 4],
            ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: intervalStep,
              getTitlesWidget: (val, meta) {
                // Drop collision on top ceiling
                if (val >= ceiling || val == 0) return const SizedBox.shrink();
                return Text(
                  val.round().toString(),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx < 0 || idx >= dateKeys.length) return const SizedBox.shrink();

                // For 7 days, always show all 7
                if (dateKeys.length > 7) {
                  final step = (dateKeys.length / 5).ceil();
                  if (idx % step != 0 && idx != dateKeys.length - 1) return const SizedBox.shrink();
                }

                final parts = dateKeys[idx].split('-');
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${parts[1]}/${parts[2]}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            tooltipBorder: BorderSide(color: AppColors.border),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final dateStr = dateKeys[group.x];
              final unit = _currentMetric == 'calories' ? 'kcal' : 'g';
              return BarTooltipItem(
                '$dateStr\n',
                TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                    text: '${rod.toY.round()} $unit',
                    style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: '\nTarget: ${targetValue.round()} $unit',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMacroBreakdownCard(_StatsData data) {
    final totalGrams = data.avgProtein + data.avgCarbs + data.avgFat;
    final hasData = totalGrams > 0;

    final proPct = hasData ? (data.avgProtein / totalGrams * 100).round() : 0;
    final carbPct = hasData ? (data.avgCarbs / totalGrams * 100).round() : 0;
    final fatPct = hasData ? (data.avgFat / totalGrams * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Macronutrient Distribution',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DistributionDonutPainter(
                    proRatio: hasData ? (data.avgProtein / totalGrams) : 0,
                    carbRatio: hasData ? (data.avgCarbs / totalGrams) : 0,
                    fatRatio: hasData ? (data.avgFat / totalGrams) : 0,
                  ),
                  child: Center(
                    child: Text(
                      hasData ? '${totalGrams.round()}g' : '0g',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textMain),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildDistributionLegendTile('Protein', '${data.avgProtein.round()}g', '$proPct%', AppColors.protein),
                    const SizedBox(height: 8),
                    _buildDistributionLegendTile('Carbs', '${data.avgCarbs.round()}g', '$carbPct%', AppColors.carbs),
                    const SizedBox(height: 8),
                    _buildDistributionLegendTile('Fat', '${data.avgFat.round()}g', '$fatPct%', AppColors.fat),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionLegendTile(String label, String grams, String pct, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          ],
        ),
        Row(
          children: [
            Text(grams, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMain)),
            const SizedBox(width: 6),
            Text('($pct)', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  // Redesigned Symmetrical 2-Column Micronutrient Matrix
  Widget _buildMicronutrientCard(_StatsData data) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isMicrosExpanded = !_isMicrosExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Micronutrient Health Matrix',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Daily averages vs standard reference intake',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Icon(
                  _isMicrosExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          if (_isMicrosExpanded) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildMicroMatrixTile('Fiber', '${data.avgMicros['fiber_g']?.toStringAsFixed(1) ?? '0'}g', (data.avgMicros['fiber_g'] ?? 0) / 30.0),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Sodium', '${data.avgMicros['sodium_mg']?.round() ?? '0'}mg', (data.avgMicros['sodium_mg'] ?? 0) / 2300.0, isLimit: true),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Cholesterol', '${data.avgMicros['cholesterol_mg']?.round() ?? '0'}mg', (data.avgMicros['cholesterol_mg'] ?? 0) / 300.0, isLimit: true),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Vitamin A', '${data.avgMicros['vitamin_a_ug']?.round() ?? '0'}µg', (data.avgMicros['vitamin_a_ug'] ?? 0) / 900.0),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Vitamin D', '${data.avgMicros['vitamin_d_ug']?.toStringAsFixed(1) ?? '0'}µg', (data.avgMicros['vitamin_d_ug'] ?? 0) / 20.0),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Iron', '${data.avgMicros['iron_mg']?.toStringAsFixed(1) ?? '0'}mg', (data.avgMicros['iron_mg'] ?? 0) / 18.0),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      _buildMicroMatrixTile('Sugar', '${data.avgMicros['sugar_g']?.toStringAsFixed(1) ?? '0'}g', (data.avgMicros['sugar_g'] ?? 0) / 50.0, isLimit: true),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Saturated Fat', '${data.avgMicros['saturated_fat_g']?.toStringAsFixed(1) ?? '0'}g', (data.avgMicros['saturated_fat_g'] ?? 0) / 20.0, isLimit: true),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Potassium', '${data.avgMicros['potassium_mg']?.round() ?? '0'}mg', (data.avgMicros['potassium_mg'] ?? 0) / 3400.0),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Vitamin C', '${data.avgMicros['vitamin_c_mg']?.toStringAsFixed(1) ?? '0'}mg', (data.avgMicros['vitamin_c_mg'] ?? 0) / 90.0),
                      const SizedBox(height: 8),
                      _buildMicroMatrixTile('Calcium', '${data.avgMicros['calcium_mg']?.round() ?? '0'}mg', (data.avgMicros['calcium_mg'] ?? 0) / 1000.0),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMicroMatrixTile(String name, String value, double progress, {bool isLimit = false}) {
    final clamped = progress.clamp(0.0, 1.0);
    final color = isLimit && progress > 1.0 ? AppColors.warning : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 12, color: AppColors.textMain, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 3.5,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsCard(_StatsData data, UserProfile profile) {
    final insights = _generateInsights(data, profile);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Automated Insights',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (insights.isEmpty)
            const Text(
              'Log at least 2 days of food to view personalized insights and adherence trends.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            )
          else
            ...insights.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.icon, style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.text,
                          style: TextStyle(fontSize: 13, color: AppColors.textMain, height: 1.4, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // Exact calendar range generation (Guarantees exactly 7, 30, or 90 days)
  _StatsData _computeAggregates(List<DailyLog> allLogs, UserProfile profile) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<String> targetDateSequence = [];

    if (_currentRange == '7') {
      for (int i = 6; i >= 0; i--) {
        targetDateSequence.add(DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i))));
      }
    } else if (_currentRange == '30') {
      for (int i = 29; i >= 0; i--) {
        targetDateSequence.add(DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i))));
      }
    } else if (_currentRange == '90') {
      for (int i = 89; i >= 0; i--) {
        targetDateSequence.add(DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i))));
      }
    } else {
      // 'all' -> all logged dates sorted
      final loggedDates = allLogs.map((l) => l.date).toSet().toList()..sort();
      if (loggedDates.isNotEmpty) {
        DateTime cursor = DateFormat('yyyy-MM-dd').parse(loggedDates.first);
        while (!cursor.isAfter(today)) {
          targetDateSequence.add(DateFormat('yyyy-MM-dd').format(cursor));
          cursor = cursor.add(const Duration(days: 1));
        }
      } else {
        targetDateSequence.add(DateFormat('yyyy-MM-dd').format(today));
      }
    }

    final Map<String, _DayAggregate> dailyMap = {};
    for (final k in targetDateSequence) {
      dailyMap[k] = _DayAggregate();
    }

    int totalLogsCount = 0;
    int daysWithData = 0;

    for (final l in allLogs) {
      if (dailyMap.containsKey(l.date)) {
        final d = dailyMap[l.date]!;
        d.calories += l.macros.calories;
        d.proteinG += l.macros.proteinG;
        d.carbsG += l.macros.carbsG;
        d.fatG += l.macros.fatG;

        d.micros['fiber_g'] = (d.micros['fiber_g'] ?? 0) + l.micros.fiberG;
        d.micros['sugar_g'] = (d.micros['sugar_g'] ?? 0) + l.micros.sugarG;
        d.micros['sodium_mg'] = (d.micros['sodium_mg'] ?? 0) + l.micros.sodiumMg;
        d.micros['saturated_fat_g'] = (d.micros['saturated_fat_g'] ?? 0) + l.micros.saturatedFatG;
        d.micros['cholesterol_mg'] = (d.micros['cholesterol_mg'] ?? 0) + l.micros.cholesterolMg;
        d.micros['potassium_mg'] = (d.micros['potassium_mg'] ?? 0) + l.micros.potassiumMg;
        d.micros['vitamin_a_ug'] = (d.micros['vitamin_a_ug'] ?? 0) + l.micros.vitaminAUg;
        d.micros['vitamin_c_mg'] = (d.micros['vitamin_c_mg'] ?? 0) + l.micros.vitaminCMg;
        d.micros['vitamin_d_ug'] = (d.micros['vitamin_d_ug'] ?? 0) + l.micros.vitaminDUg;
        d.micros['calcium_mg'] = (d.micros['calcium_mg'] ?? 0) + l.micros.calciumMg;
        d.micros['iron_mg'] = (d.micros['iron_mg'] ?? 0) + l.micros.ironMg;
        d.logCount++;
        totalLogsCount++;
      }
    }

    double sumCals = 0, sumPro = 0, sumCarb = 0, sumFat = 0;
    final Map<String, double> sumMicros = {};

    for (final d in dailyMap.values) {
      if (d.calories > 0) {
        daysWithData++;
        sumCals += d.calories;
        sumPro += d.proteinG;
        sumCarb += d.carbsG;
        sumFat += d.fatG;

        d.micros.forEach((k, v) {
          sumMicros[k] = (sumMicros[k] ?? 0) + v;
        });
      }
    }

    final divisor = math.max(1, daysWithData);
    final Map<String, double> avgMicros = {};
    sumMicros.forEach((k, v) => avgMicros[k] = v / divisor);

    return _StatsData(
      daysWithData: daysWithData,
      totalLogsCount: totalLogsCount,
      avgCalories: sumCals / divisor,
      avgProtein: sumPro / divisor,
      avgCarbs: sumCarb / divisor,
      avgFat: sumFat / divisor,
      avgMicros: avgMicros,
      dailyDateKeys: targetDateSequence,
      dailyMap: dailyMap,
    );
  }

  _StatusInfo _getCalorieStatus(double avg, double target, UserProfile profile) {
    final goalOffset = double.tryParse(profile.goal) ?? 0.0;
    final margin = math.max(100.0, target * 0.05);

    if (avg >= target - margin && avg <= target + margin) {
      return  _StatusInfo('On Track', AppColors.primary);
    }

    if (goalOffset > 0) {
      if (avg > target + margin) return const _StatusInfo('Surplus', AppColors.warning);
      return const _StatusInfo('Needs Boost', AppColors.danger);
    } else if (goalOffset < 0) {
      if (avg < target - margin) return const _StatusInfo('Deep Cut', AppColors.warning);
      return const _StatusInfo('Over Target', AppColors.danger);
    }

    return const _StatusInfo('Off Target', AppColors.warning);
  }

  _StatusInfo _getProteinStatus(double avg, double target, int days) {
    if (days == 0) return const _StatusInfo('No Data', AppColors.textMuted);
    final margin = math.max(10.0, target * 0.10);
    if (avg >= target - margin) return  _StatusInfo('On Track', AppColors.primary);
    return const _StatusInfo('Needs Boost', AppColors.warning);
  }

  List<_InsightItem> _generateInsights(_StatsData data, UserProfile profile) {
    if (data.daysWithData < 2) return [];

    final list = <_InsightItem>[];
    final targetCals = profile.targetCalories > 0 ? profile.targetCalories : 2000.0;
    final targetPro = profile.targetProteinG > 0 ? profile.targetProteinG : 150.0;

    final calDiff = data.avgCalories - targetCals;
    if (calDiff.abs() < targetCals * 0.05) {
      list.add(const _InsightItem('🎯', 'Your average calorie intake is right on target. Excellent consistency!'));
    } else if (calDiff > 0) {
      list.add(_InsightItem('📈', 'You are averaging ${calDiff.round()} kcal over your daily target. Consider trimming portion multipliers.'));
    } else {
      list.add(_InsightItem('📉', 'You are averaging ${calDiff.abs().round()} kcal below your daily target. Ensure you are meeting minimum energy needs.'));
    }

    final proRatio = data.avgProtein / targetPro;
    if (proRatio >= 0.95) {
      list.add(const _InsightItem('💪', 'Great job hitting your daily protein target consistently!'));
    } else if (proRatio >= 0.75) {
      list.add(_InsightItem('🥩', 'You are reaching ${(proRatio * 100).round()}% of your protein target. Try adding a high-protein snack.'));
    } else {
      list.add(_InsightItem('⚠️', 'You are only reaching ${(proRatio * 100).round()}% of your protein target, which may impact muscle recovery.'));
    }

    final goalOffset = double.tryParse(profile.goal) ?? 0.0;
    final maintenance = targetCals - goalOffset;
    final diffFromMaintenance = data.avgCalories - maintenance;
    final weeklySurplus = diffFromMaintenance * 7;
    final kgChange = weeklySurplus / 7700.0;

    if (kgChange.abs() > 0.05) {
      final dir = kgChange > 0 ? 'gain' : 'lose';
      list.add(_InsightItem('⚖️', 'At your current daily intake, your estimated pace is to $dir ~${kgChange.abs().toStringAsFixed(1)} kg/week.'));
    }

    return list;
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo(this.label, this.color);
}

class _InsightItem {
  final String icon;
  final String text;
  const _InsightItem(this.icon, this.text);
}

class _DayAggregate {
  double calories = 0;
  double proteinG = 0;
  double carbsG = 0;
  double fatG = 0;
  final Map<String, double> micros = {};
  int logCount = 0;
}

class _StatsData {
  final int daysWithData;
  final int totalLogsCount;
  final double avgCalories;
  final double avgProtein;
  final double avgCarbs;
  final double avgFat;
  final Map<String, double> avgMicros;
  final List<String> dailyDateKeys;
  final Map<String, _DayAggregate> dailyMap;

  _StatsData({
    required this.daysWithData,
    required this.totalLogsCount,
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.avgFat,
    required this.avgMicros,
    required this.dailyDateKeys,
    required this.dailyMap,
  });
}

class _DistributionDonutPainter extends CustomPainter {
  final double proRatio;
  final double carbRatio;
  final double fatRatio;

  _DistributionDonutPainter({
    required this.proRatio,
    required this.carbRatio,
    required this.fatRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;
    const strokeWidth = 8.0;

    final bgPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final total = proRatio + carbRatio + fatRatio;
    if (total <= 0) return;

    double startAngle = -math.pi / 2;

    void drawArc(double ratio, Color color) {
      if (ratio <= 0) return;
      final sweep = (ratio / total) * 2 * math.pi;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep > 0.08 ? sweep - 0.04 : sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }

    drawArc(proRatio, AppColors.protein);
    drawArc(carbRatio, AppColors.carbs);
    drawArc(fatRatio, AppColors.fat);
  }

  @override
  bool shouldRepaint(covariant _DistributionDonutPainter old) {
    return old.proRatio != proRatio || old.carbRatio != carbRatio || old.fatRatio != fatRatio;
  }
}