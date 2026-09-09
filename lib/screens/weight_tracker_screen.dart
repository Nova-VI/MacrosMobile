import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_log.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class WeightTrackerScreen extends StatefulWidget {
  const WeightTrackerScreen({super.key});

  @override
  State<WeightTrackerScreen> createState() => _WeightTrackerScreenState();
}

class _WeightTrackerScreenState extends State<WeightTrackerScreen> {
  final _weightInputController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  late DateTime _selectedLogDate;
  String _activePreset = 'month'; // Defaults to 30 days
  bool _isHistoryExpanded = false; // Collapsed by default
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _selectedLogDate = DateTime.now();
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
      _showToast('Please enter a valid body weight.', isError: true);
      return;
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedLogDate);
    await _firestoreService.setWeightLog(WeightLog(date: dateKey, weightKg: weight));

    HapticFeedback.mediumImpact();
    _showToast('Weight logged for ${DateFormat('MMM d').format(_selectedLogDate)}!');
    _weightInputController.clear();
    setState(() {
      _selectedLogDate = DateTime.now();
    });
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: isError ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isError ? AppColors.danger : AppColors.primary),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
        final filteredLogs = _filterLogs(allLogs);
        final historyDesc = List<WeightLog>.from(filteredLogs).reversed.toList();

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildQuickLogCard(),
                const SizedBox(height: 14),
                _buildChartCard(filteredLogs),
                const SizedBox(height: 14),
                _buildHistorySection(historyDesc),
              ],
            ),
          ),
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
                  decoration:  InputDecoration(
                    labelText: 'Body Weight',
                    suffixText: 'kg',
                    suffixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14),
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

  Widget _buildChartCard(List<WeightLog> logs) {
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
              if (logs.isNotEmpty)
                Text(
                  '${logs.last.weightKg.toStringAsFixed(1)} kg',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Period Filters Row
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
          const SizedBox(height: 18),

          SizedBox(
            height: 200,
            child: logs.length < 2
                ? Center(
                    child: Text(
                      logs.isEmpty ? 'No weight logs in this period.' : 'Log at least 2 days to render trend line.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : _buildWeightLineChart(logs),
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

  Widget _buildWeightLineChart(List<WeightLog> logs) {
    final spots = <FlSpot>[];
    double minWeight = logs.first.weightKg;
    double maxWeight = logs.first.weightKg;

    for (int i = 0; i < logs.length; i++) {
      final w = logs[i].weightKg;
      if (w < minWeight) minWeight = w;
      if (w > maxWeight) maxWeight = w;
      spots.add(FlSpot(i.toDouble(), w));
    }

    final paddingY = ((maxWeight - minWeight) * 0.15).clamp(1.0, 5.0);

    return LineChart(
      LineChartData(
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
              interval: (logs.length / 4).clamp(1.0, 10.0),
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx < 0 || idx >= logs.length) return const SizedBox.shrink();
                final d = logs[idx].date.split('-');
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${d[1]}/${d[2]}',
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
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final dateStr = logs[idx].date;
                return LineTooltipItem(
                  '$dateStr\n',
                  const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                  children: [
                    TextSpan(
                      text: '${spot.y.toStringAsFixed(1)} kg',
                      style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: logs.length <= 15,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3.5,
                color: AppColors.primary,
                strokeWidth: 2,
                strokeColor: AppColors.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.25),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<WeightLog> logs) {
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
              ...logs.map((log) => _buildWeightHistoryTile(log)),
          ],
        ],
      ),
    );
  }

  Widget _buildWeightHistoryTile(WeightLog log) {
    final parsedDate = DateTime.tryParse(log.date);
    final dateDisplay = parsedDate != null ? DateFormat('EEEE, MMM d, yyyy').format(parsedDate) : log.date;

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
              Text(
                '${log.weightKg.toStringAsFixed(1)} kg',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: -0.3),
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
                      await _firestoreService.setWeightLog(WeightLog(date: log.date, weightKg: newW));
                      HapticFeedback.mediumImpact();
                      _showToast('Weight log updated!');
                      if (mounted) Navigator.pop(ctx);
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

  void _confirmDeleteWeight(WeightLog log) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deleteWeightLog(log.date);
      _showToast('Weight log deleted.');
    }
  }
}