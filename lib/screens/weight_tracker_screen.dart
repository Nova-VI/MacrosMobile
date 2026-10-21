import '../widgets/app_toast.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_log.dart';
import '../services/firestore_service.dart';
import '../services/adaptive_coach_service.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../utils/weight_goal.dart';

class WeightTrackerScreen extends StatefulWidget {
  final bool autoEditLatest;

  const WeightTrackerScreen({
    super.key,
    this.autoEditLatest = false,
  });

  @override
  State<WeightTrackerScreen> createState() => _WeightTrackerScreenState();
}

class _WeightTrackerScreenState extends State<WeightTrackerScreen> {
  final _weightInputController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  late DateTime _selectedLogDate;
  String _activePreset = 'month';
  bool _isHistoryExpanded = false;
  bool _focusTrend = false;
  bool _showGoalPath = false;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _selectedLogDate = DateTime.now();

    if (widget.autoEditLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerAutoEditLatest();
      });
    }
  }

  void _triggerAutoEditLatest() {
    final logs = _firestoreService.weightLogsNotifier.value;
    if (logs.isNotEmpty) {
      _openEditWeightModal(logs.last);
    } else {
      _showToast('No weight logs yet');
    }
  }

  @override
  void dispose() {
    _weightInputController.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController controller) {
    Future.delayed(Duration.zero, () {
      if (controller.text.isNotEmpty) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  Future<void> _pickLogDate() async {
    HapticFeedback.selectionClick();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedLogDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedLogDate = picked);
    }
  }

  Future<void> _openCustomDateFilter() async {
    HapticFeedback.lightImpact();
    final today = DateTime.now();
    final phaseStart = currentPhaseStartDate(_firestoreService.profileNotifier.value, today);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phaseStart != null)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: AppColors.warning),
                title: const Text('Use current phase start'),
                subtitle: Text(DateFormat('MMM d, yyyy').format(phaseStart)),
                onTap: () => Navigator.pop(sheetContext, 'phase'),
              ),
            ListTile(
              leading: Icon(Icons.date_range_rounded, color: AppColors.primary),
              title: const Text('Choose dates'),
              onTap: () => Navigator.pop(sheetContext, 'dates'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'phase' && phaseStart != null) {
      setState(() {
        _activePreset = 'custom';
        _customStartDate = phaseStart;
        _customEndDate = DateTime(today.year, today.month, today.day);
      });
      return;
    }
    if (choice != 'dates') return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
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

    if (range != null) {
      setState(() {
        _activePreset = 'custom';
        _customStartDate = range.start;
        _customEndDate = range.end;
      });
    }
  }

  Future<void> _submitWeightLog() async {
    final weight = double.tryParse(_weightInputController.text);
    if (weight == null || weight <= 0) {
      _showToast('Enter a valid weight', isError: true);
      return;
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedLogDate);

    try {
      await _firestoreService.setWeightLog(WeightLog(date: dateKey, weightKg: weight));
    } catch (error) {
      if (mounted) _showToast('Could not save', isError: true);
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _showToast('Saved');
    _weightInputController.clear();
    setState(() {
      _selectedLogDate = DateTime.now();
    });
  }

  void _showToast(String message, {bool isError = false}) =>
      showAppToast(context, message, isError: isError);

  String _formatWeightChange(double change) =>
      '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg';

  List<WeightLog> _filterLogs(List<WeightLog> allLogs) {
    if (allLogs.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_activePreset == 'week') {
      final start = today.subtract(const Duration(days: 6));
      final startKey = DateFormat('yyyy-MM-dd').format(start);
      final endKey = DateFormat('yyyy-MM-dd').format(today);
      return allLogs.where((l) => l.date.compareTo(startKey) >= 0 && l.date.compareTo(endKey) <= 0).toList();
    }

    if (_activePreset == 'month') {
      final start = today.subtract(const Duration(days: 29));
      final startKey = DateFormat('yyyy-MM-dd').format(start);
      final endKey = DateFormat('yyyy-MM-dd').format(today);
      return allLogs.where((l) => l.date.compareTo(startKey) >= 0 && l.date.compareTo(endKey) <= 0).toList();
    }

    if (_activePreset == 'custom' && _customStartDate != null && _customEndDate != null) {
      final startKey = DateFormat('yyyy-MM-dd').format(_customStartDate!);
      final endKey = DateFormat('yyyy-MM-dd').format(_customEndDate!);
      return allLogs.where((l) => l.date.compareTo(startKey) >= 0 && l.date.compareTo(endKey) <= 0).toList();
    }

    return allLogs;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WeightLog>>(
      valueListenable: _firestoreService.weightLogsNotifier,
      builder: (context, allLogs, _) {
        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: AdaptiveCoachService().trendWeightsNotifier,
          builder: (context, trendWeightsMap, _) {
            final filteredLogs = _filterLogs(allLogs);
            final historyDesc = List<WeightLog>.from(filteredLogs).reversed.toList();

            return ValueListenableBuilder<UserProfile>(
              valueListenable: _firestoreService.profileNotifier,
              builder: (context, profile, _) => Scaffold(
              appBar: widget.autoEditLatest
                  ? AppBar(
                      title: const Text('Weight Tracker'),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    )
                  : null,
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildQuickLogCard(),
                    const SizedBox(height: 14),
                    _buildChartCard(filteredLogs, trendWeightsMap, profile),
                    const SizedBox(height: 14),
                    _buildHistorySection(historyDesc, trendWeightsMap),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickLogCard() {
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
                'Log Body Weight',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
              InkWell(
                onTap: _pickLogDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHover,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                       Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d').format(_selectedLogDate),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMain),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightInputController,
                  onTap: () => _selectAll(_weightInputController),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Body Weight',
                    suffixText: 'kg',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _submitWeightLog,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(110, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Save Log', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(List<WeightLog> logs, Map<String, double> trendWeightsMap, UserProfile profile) {
    final latestScale = logs.isNotEmpty ? logs.last.weightKg : null;
    final today = DateTime.now();
    final periodStart = _activePreset == 'week' ? today.subtract(const Duration(days: 6))
        : _activePreset == 'month' ? today.subtract(const Duration(days: 29))
        : _activePreset == 'custom' ? _customStartDate
        : (logs.isNotEmpty ? DateTime.tryParse(logs.first.date) : null);
    final periodEnd = _activePreset == 'custom' ? _customEndDate
        : _activePreset == 'all' ? (logs.isNotEmpty ? DateTime.tryParse(logs.last.date) : null)
        : today;
    final weightChange = periodStart != null && periodEnd != null
        ? periodTrendChange(trendWeightsMap, periodStart, periodEnd) : null;
    final latestTrend = logs.isNotEmpty
        ? (trendWeightsMap[logs.last.date] ?? AdaptiveCoachService().liveObserverStateNotifier.value?.estimatedMassKg)
        : null;

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
                'Weight Trend',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),

              Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _focusTrend = !_focusTrend);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: _focusTrend ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceHover,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _focusTrend ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _focusTrend ? Icons.insights_rounded : Icons.show_chart_rounded,
                        size: 14,
                        color: _focusTrend ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _focusTrend ? 'Trend Focus' : 'Scale Focus',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _focusTrend ? AppColors.primary : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                PopupMenuButton<bool>(
                  tooltip: 'Weight chart options',
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
                  onSelected: (value) => setState(() => _showGoalPath = value),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem<bool>(
                      value: !_showGoalPath,
                      checked: _showGoalPath,
                      child: const Text('Show goal path'),
                    ),
                  ],
                ),
              ]),
            ],
          ),

          if (logs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  _focusTrend
                      ? (latestTrend != null ? '${latestTrend.toStringAsFixed(1)} kg' : '${latestScale!.toStringAsFixed(1)} kg')
                      : '${latestScale!.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _focusTrend ? 'Trend Weight' : 'Scale Weight',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                if (_focusTrend && latestScale != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(Scale: ${latestScale.toStringAsFixed(1)} kg)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                  ),
                ] else if (!_focusTrend && latestTrend != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(Trend: ${latestTrend.toStringAsFixed(1)} kg)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ],
          if (weightChange != null) ...[
            const SizedBox(height: 6),
            Text(
              'Trend change in selected period: ${_formatWeightChange(weightChange)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text('Trend change in selected period: —',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),

          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildPresetChip('30 Days', 'month'),
                const SizedBox(width: 8),
                _buildPresetChip('7 Days', 'week'),
                const SizedBox(width: 8),
                _buildPresetChip('All Time', 'all'),
                const SizedBox(width: 8),
                _buildPresetChip(
                  _activePreset == 'custom' && _customStartDate != null
                      ? '${DateFormat('M/d').format(_customStartDate!)} - ${DateFormat('M/d').format(_customEndDate!)}'
                      : 'Custom',
                  'custom',
                  onTap: _openCustomDateFilter,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _focusTrend ? 'Trend (Solid)' : 'Scale (Solid)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMain),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 2,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _focusTrend ? 'Scale (Dashed)' : 'Trend (Dashed)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                ],
              ),
              if (_showGoalPath)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 2, color: AppColors.warning),
                    const SizedBox(width: 6),
                    const Text('Goal Path (Dashed)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 200,
            child: logs.isEmpty || (logs.length < 2 && !_showGoalPath)
                ? Center(
                    child: Text(
                      logs.isEmpty ? 'No weight logs in this period.' : 'Log at least 2 days to render curve.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : _buildWeightLineChart(logs, trendWeightsMap, profile),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String preset, {VoidCallback? onTap}) {
    final isSelected = _activePreset == preset;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (onTap != null) {
          onTap();
        } else {
          setState(() => _activePreset = preset);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildWeightLineChart(List<WeightLog> logs, Map<String, double> trendWeightsMap, UserProfile profile) {
    final parsedDates = logs.map((l) {
      try {
        return DateTime.parse('${l.date}T00:00:00Z');
      } catch (_) {
        return DateTime.now();
      }
    }).toList();

    final minDate = parsedDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastLogDate = parsedDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final periodEnd = _activePreset == 'custom' ? _customEndDate
        : (_activePreset == 'week' || _activePreset == 'month') ? DateTime.now() : null;
    final maxDate = _showGoalPath && periodEnd != null && periodEnd.isAfter(lastLogDate)
        ? DateTime.utc(periodEnd.year, periodEnd.month, periodEnd.day) : lastLogDate;
    final totalDaysSpan = math.max(1, maxDate.difference(minDate).inDays).toDouble();

    final scaleSpots = <FlSpot>[];
    final trendSpots = <FlSpot>[];
    final goalSpots = <FlSpot>[];
    double minWeight = logs.first.weightKg;
    double maxWeight = logs.first.weightKg;

    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      final w = log.weightKg;
      final trend = trendWeightsMap[log.date] ?? log.trendWeightKg ?? w;

      if (w < minWeight) minWeight = w;
      if (w > maxWeight) maxWeight = w;
      if (trend < minWeight) minWeight = trend;
      if (trend > maxWeight) maxWeight = trend;

      final dayOffset = parsedDates[i].difference(minDate).inDays.toDouble();
      scaleSpots.add(FlSpot(dayOffset, w));
      trendSpots.add(FlSpot(dayOffset, trend));
    }

    if (_showGoalPath) {
      for (int day = 0; day <= totalDaysSpan.toInt(); day++) {
        final weight = goalWeightAtDate(profile, _firestoreService.weightLogsNotifier.value,
            minDate.add(Duration(days: day)), trendWeightsMap: trendWeightsMap);
        if (weight == null) continue;
        goalSpots.add(FlSpot(day.toDouble(), weight));
        if (weight < minWeight) minWeight = weight;
        if (weight > maxWeight) maxWeight = weight;
      }
    }

    final weightDelta = maxWeight - minWeight;
    final paddingY = weightDelta == 0 ? 2.0 : (weightDelta * 0.15).clamp(1.0, 5.0);
    final double dateInterval = math.max(1.0, (totalDaysSpan / 4).floorToDouble());

    final primarySpots = _focusTrend ? trendSpots : scaleSpots;
    final secondarySpots = _focusTrend ? scaleSpots : trendSpots;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: totalDaysSpan,
        minY: (minWeight - paddingY).floorToDouble(),
        maxY: (maxWeight + paddingY).ceilToDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.border.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (val, meta) {
                if (val == meta.min || val == meta.max) return const SizedBox.shrink();
                return Text(
                  val.round().toString(),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: dateInterval,
              getTitlesWidget: (val, meta) {
                if (val < 0 || val > totalDaysSpan) return const SizedBox.shrink();
                final targetDate = minDate.add(Duration(days: val.round()));
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M/d').format(targetDate),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            tooltipBorder: const BorderSide(color: AppColors.border),
            getTooltipItems: (touchedSpots) {
              if (touchedSpots.isEmpty) return [];

              return touchedSpots.asMap().entries.map((entry) {
                if (entry.key > 0) return null;
                final spot = entry.value;
                final targetDate = minDate.add(Duration(days: spot.x.round()));
                final dateStr = DateFormat('EEE, MMM d').format(targetDate);

                WeightLog? matchedLog;
                for (int j = 0; j < logs.length; j++) {
                  if (parsedDates[j].difference(minDate).inDays == spot.x.round()) {
                    matchedLog = logs[j];
                    break;
                  }
                }

                final scaleVal = matchedLog?.weightKg;
                final trendVal = matchedLog != null ? (trendWeightsMap[matchedLog.date] ?? matchedLog.trendWeightKg) : null;
                final goalVal = _showGoalPath
                    ? goalWeightAtDate(profile, _firestoreService.weightLogsNotifier.value,
                        targetDate, trendWeightsMap: trendWeightsMap)
                    : null;

                return LineTooltipItem(
                  '$dateStr\n',
                  const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500),
                  children: [
                    if (scaleVal != null)
                      TextSpan(
                        text: 'Scale: ${scaleVal.toStringAsFixed(1)} kg\n',
                        style: TextStyle(
                          color: !_focusTrend ? AppColors.primary : Colors.white,
                          fontSize: 12.5,
                          fontWeight: !_focusTrend ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    if (trendVal != null)
                      TextSpan(
                        text: 'Trend: ${trendVal.toStringAsFixed(1)} kg${goalVal != null ? '\n' : ''}',
                        style: TextStyle(
                          color: _focusTrend ? AppColors.primary : AppColors.textMuted,
                          fontSize: 12.5,
                          fontWeight: _focusTrend ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    if (goalVal != null)
                      TextSpan(
                        text: 'Goal path: ${goalVal.toStringAsFixed(1)} kg',
                        style: const TextStyle(color: AppColors.warning, fontSize: 12.5,
                            fontWeight: FontWeight.w700),
                      ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: primarySpots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primary,
            barWidth: 3.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          LineChartBarData(
            spots: secondarySpots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.textMuted.withValues(alpha: 0.65),
            barWidth: 2.0,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
          if (goalSpots.isNotEmpty)
            LineChartBarData(
              spots: goalSpots,
              isCurved: false,
              color: AppColors.warning,
              barWidth: 2,
              dashArray: [7, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<WeightLog> logs, Map<String, double> trendWeightsMap) {
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
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isHistoryExpanded = !_isHistoryExpanded);
            },
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Log History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${logs.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      _isHistoryExpanded ? 'Collapse' : 'Show',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isHistoryExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isHistoryExpanded) ...[
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No weight history found for this range.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
              )
            else
              ...logs.map((log) => _buildWeightHistoryTile(log, trendWeightsMap[log.date])),
          ],
        ],
      ),
    );
  }

  Widget _buildWeightHistoryTile(WeightLog log, double? computedTrend) {
    final parsedDate = DateTime.tryParse(log.date);
    final dateDisplay = parsedDate != null ? DateFormat('EEEE, MMM d, yyyy').format(parsedDate) : log.date;
    final trendVal = computedTrend ?? log.trendWeightKg;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${log.weightKg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: AppColors.textMain, letterSpacing: -0.3),
                  ),
                  if (trendVal != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Trend: ${trendVal.toStringAsFixed(1)} kg',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                dateDisplay,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.textMuted),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => _openEditWeightModal(log),
                tooltip: 'Edit Log',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => _confirmDeleteWeight(log),
                tooltip: 'Delete Log',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openEditWeightModal(WeightLog log) {
    final editCtrl = TextEditingController(text: log.weightKg.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: AppColors.border)),
        title: const Text('Edit Weight Log', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${log.date}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: editCtrl,
              onTap: () => _selectAll(editCtrl),
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 16),
              decoration: const InputDecoration(labelText: 'Body Weight (kg)'),
            ),
          ],
        ),
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
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final newW = double.tryParse(editCtrl.text);
                    if (newW != null && newW > 0) {
                      Navigator.pop(ctx);
                      try {
                        await _firestoreService.setWeightLog(WeightLog(date: log.date, weightKg: newW));
                      } catch (error) {
                        if (mounted) _showToast('Could not update', isError: true);
                        return;
                      }
                      if (!mounted) return;
                      HapticFeedback.mediumImpact();
                      _showToast('Updated');
                    }
                  },
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWeight(WeightLog log) {
    HapticFeedback.mediumImpact();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
        title: const Text('Delete Weight Log', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete the log for ${log.date}?', style: const TextStyle(color: AppColors.textMuted)),
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
                  child: const Text('Cancel'),
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
                  onPressed: () async {
                    Navigator.pop(ctx, true);
                    try {
                      await _firestoreService.deleteWeightLog(log.date);
                    } catch (error) {
                      if (mounted) _showToast('Could not delete', isError: true);
                      return;
                    }
                    if (!mounted) return;
                    HapticFeedback.mediumImpact();
                    _showToast('Deleted');
                  },
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
