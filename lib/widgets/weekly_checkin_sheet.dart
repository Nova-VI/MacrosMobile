import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/adaptive_coach_service.dart';
import '../theme/app_theme.dart';

class WeeklyCheckInSheet extends StatelessWidget {
  final WeeklyCheckInProposal proposal;

  const WeeklyCheckInSheet({
    super.key,
    required this.proposal,
  });

  static void show(BuildContext context, WeeklyCheckInProposal proposal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WeeklyCheckInSheet(proposal: proposal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calDelta = proposal.proposedCalories - proposal.currentCalories;
    final calDeltaStr = calDelta > 0 ? '+$calDelta' : '$calDelta';

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Adaptive Check-In',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textMain),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'State-Space Observer Calibration',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CALCULATED TDEE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4)),
                          const SizedBox(height: 3),
                          Text('${proposal.currentTdeeKcal.round()} kcal / day', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('TREND WEIGHT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4)),
                          const SizedBox(height: 3),
                          Text('${proposal.trendWeightKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('PROPOSED TARGET ADJUSTMENT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: calDelta == 0
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : (calDelta > 0 ? AppColors.secondary.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              calDelta == 0 ? 'NO CHANGE' : '$calDeltaStr kcal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: calDelta == 0 ? AppColors.primary : (calDelta > 0 ? AppColors.secondary : AppColors.warning),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      _buildMacroComparisonRow('Calories', '${proposal.currentCalories} kcal', '${proposal.proposedCalories} kcal', AppColors.primary),
                      const SizedBox(height: 8),
                      _buildMacroComparisonRow('Protein', '${proposal.currentProteinG}g', '${proposal.proposedProteinG}g', AppColors.protein),
                      const SizedBox(height: 8),
                      _buildMacroComparisonRow('Carbs', '${proposal.currentCarbsG}g', '${proposal.proposedCarbsG}g', AppColors.carbs),
                      const SizedBox(height: 8),
                      _buildMacroComparisonRow('Fat', '${proposal.currentFatG}g', '${proposal.proposedFatG}g', AppColors.fat),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  'Based on your past 14 days of scale readings and caloric intake, the closed-loop regulator recommends adjusting your daily targets to maintain exact progress toward your goal.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await AdaptiveCoachService().acceptProposal(proposal);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Accept & Update Daily Targets'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    AdaptiveCoachService().dismissProposal();
                    Navigator.pop(context);
                  },
                  child: const Text('Keep Current Targets', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroComparisonRow(String label, String currentVal, String proposedVal, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
            ],
          ),
          Row(
            children: [
              Text(currentVal, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(proposedVal, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}