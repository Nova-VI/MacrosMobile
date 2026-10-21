import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/services/adaptive_coach_engine.dart';

void main() {
  test('logged intake is not increased by an assumed reporting bias', () {
    final state = AdaptiveCoachState.initial(
      initialWeightKg: 70,
      initialTdeeKcal: 2400,
    );
    final next = AdaptiveCoachEngine.stepObserver(
      prevState: state,
      scaleWeightLogKg: 70,
      validMeanCalories14d: 2400,
      validIntakeDaysCount: 14,
      initialFatMassKg: 20,
      heightCm: 175,
      ageYears: 30,
      gender: 'male',
      studyDayIndex: 30,
    );
    expect(next.tdeeKcal, lessThanOrEqualTo(2400));
  });

  PrescriptionVector prescribe({
    required double mass,
    required double velocity,
    double tdee = 2600,
    double target = 2500,
  }) => AdaptiveCoachEngine.synthesizePrescription(
        currentState: AdaptiveCoachState(
          estimatedMassKg: mass,
          tissueVelocityKgPerDay: velocity,
          tdeeKcal: tdee,
          tissueEnthalpy: 7000,
        ),
        initialPhaseMassKg: 80,
        targetWeeklyWeightDeltaKg: 0.2,
        phaseDayIndex: 35,
        currentTargetCaloriesKcal: target,
        proteinMultiplierGPerKg: 2,
      );

  test('above-path bulk lowers current target despite high TDEE', () {
    final proposal = prescribe(mass: 84, velocity: 0.07, tdee: 3000);
    expect(proposal.caloriesKcal, 2300);
  });

  test('weekly change is capped and never rises while far above path', () {
    final proposal = prescribe(mass: 84, velocity: -0.1, tdee: 3000);
    expect(proposal.caloriesKcal, 2500);
    final slower = prescribe(mass: 84, velocity: 0.02);
    expect(slower.caloriesKcal, inInclusiveRange(2300, 2500));
  });

  test('on-path trend at goal velocity holds current target', () {
    final goalVelocity = 0.2 / 7;
    final goalMass = 80 + 35 * goalVelocity;
    final proposal = prescribe(mass: goalMass, velocity: goalVelocity);
    expect(proposal.caloriesKcal, 2500);
  });
}
