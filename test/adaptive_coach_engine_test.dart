import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/services/adaptive_coach_engine.dart';

void main() {
  group('AdaptiveCoachEngine Deterministic Reference Vector Audit', () {
    test('Matches Section 6 specification exactly on Day k=14', () {
      // 1. Set incoming state at k=13
      final stateK13 = AdaptiveCoachState(
        estimatedMassKg: 89.20,
        tissueVelocityKgPerDay: -0.040,
        p00: 0.042,
        p01: 0.0012,
        p10: 0.0012,
        p11: 0.00015,
        tdeeKcal: 2620.0,
        latentIntakeBias: 0.88,
        integratorKcalDays: 1.20,
        resVariance: 0.0050,
        biasVariance: 0.00005,
      );

      // 2. Step observer for Day k=14
      final stateK14 = AdaptiveCoachEngine.stepObserver(
        prevState: stateK13,
        scaleWeightLogKg: 89.40,
        validMeanCalories14d: 2100.0,
        validIntakeDaysCount: 12,
        initialFatMassKg: 21.69,
        heightCm: 180.0,
        ageYears: 30,
        gender: 'male',
        studyDayIndex: 14,
        activityMultiplier: 1.38,
      );

      // Verify Kalman state updates
      expect(stateK14.estimatedMassKg, closeTo(89.188, 0.001));
      expect(stateK14.tissueVelocityKgPerDay, closeTo(-0.03918, 0.0001));

      // Verify Forbes enthalpy & Information gain
      expect(stateK14.tissueEnthalpy, closeTo(6936.84, 0.1));
      expect(stateK14.informationGain, closeTo(0.7585, 0.001));

      // Verify TDEE state
      expect(stateK14.tdeeKcal, closeTo(2621.31, 0.05));

      // 3. Synthesize Closed-Loop Prescription
      final prescription = AdaptiveCoachEngine.synthesizePrescription(
        currentState: stateK14,
        initialPhaseMassKg: 90.0,
        targetWeeklyWeightDeltaKg: -0.50, // -0.07143 kg/day
        phaseDayIndex: 14,
        proteinMultiplierGPerKg: 2.0,
        lipidFloorMultiplierGPerKg: 0.60,
      );

      // Verify PI feedback & Caloric target
      expect(prescription.piAdjustmentKcal, closeTo(197.91, 0.2));
      expect(prescription.caloriesKcal, equals(1928));

      // Verify Integer Macronutrients
      expect(prescription.proteinG, equals(178));
      expect(prescription.fatG, equals(54));
      expect(prescription.carbsG, equals(182));
    });
  });
}