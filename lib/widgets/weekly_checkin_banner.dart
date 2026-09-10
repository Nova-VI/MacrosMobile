import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/adaptive_coach_service.dart';
import '../theme/app_theme.dart';
import 'weekly_checkin_sheet.dart';

class WeeklyCheckInBanner extends StatelessWidget {
  const WeeklyCheckInBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeeklyCheckInProposal?>(
      valueListenable: AdaptiveCoachService().checkInProposalNotifier,
      builder: (context, proposal, _) {
        if (proposal == null) return const SizedBox.shrink();

        final calDelta = proposal.proposedCalories - proposal.currentCalories;
        final deltaText = calDelta > 0 ? '+$calDelta' : '$calDelta';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weekly Check-In Ready',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMain),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TDEE: ${proposal.currentTdeeKcal.round()} kcal • Target: ${proposal.proposedCalories} kcal ($deltaText)',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(60, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  WeeklyCheckInSheet.show(context, proposal);
                },
                child: const Text('Review', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }
}