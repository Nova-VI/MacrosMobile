import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/user_profile.dart';

void main() {
  test('goal change preserves old target history and closes previous day', () {
    final oldPhase = GoalPhase(
      id: 'old', startDate: '2026-10-10', goal: '-500',
      goalType: GoalType.cut, initialCalories: 1900,
      initialProteinG: 150, initialCarbsG: 180, initialFatG: 65,
    );
    final oldProfile = UserProfile(goal: '-500', goalPhases: [oldPhase]);
    final newProfile = UserProfile(goal: '0', targetCalories: 2200,
        goalPhases: [oldPhase]);

    final phases = buildGoalPhasesForSave(
      oldProfile, newProfile, '2026-10-15');
    expect(phases, hasLength(2));
    expect(phases.first.goal, '-500');
    expect(phases.first.endDate, '2026-10-14');
    expect(phases.last.goal, '0');
    expect(phases.last.startDate, '2026-10-15');

    final saved = UserProfile.fromFirestore({
      ...newProfile.toMap(),
      'goal_phases': phases.map((phase) => phase.toMap()).toList(),
    });
    expect(saved.getTargetForDate('2026-10-14').goal, '-500');
    expect(saved.getTargetForDate('2026-10-15').goal, '0');
  });

  test('repeated same-day goal change replaces the open phase', () {
    final current = UserProfile(goal: '-500');
    final first = UserProfile(goal: '0');
    final firstPhases = buildGoalPhasesForSave(current, first, '2026-10-15');
    final second = UserProfile(goal: '+250', goalPhases: firstPhases);
    final phases = buildGoalPhasesForSave(
      UserProfile(goal: '0', goalPhases: firstPhases), second, '2026-10-15');
    expect(phases, hasLength(1));
    expect(phases.single.goal, '+250');
    expect(phases.single.endDate, isNull);
  });
}
