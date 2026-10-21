import 'dart:math' as math;

class AdaptiveCoachState {
  final double estimatedMassKg;
  final double tissueVelocityKgPerDay;
  final double p00;
  final double p01;
  final double p10;
  final double p11;
  final double tdeeKcal;
  final double resVariance;
  final double informationGain;
  final double tissueEnthalpy;

  const AdaptiveCoachState({
    required this.estimatedMassKg,
    required this.tissueVelocityKgPerDay,
    this.p00 = 0.10,
    this.p01 = 0.001,
    this.p10 = 0.001,
    this.p11 = 0.0001,
    required this.tdeeKcal,
    this.resVariance = 0.0050,
    this.informationGain = 0.0,
    this.tissueEnthalpy = 7700.0,
  });

  factory AdaptiveCoachState.initial({
    required double initialWeightKg,
    required double initialTdeeKcal,
    double initialFatMassKg = 20.0,
  }) {
    final pFat = initialFatMassKg / (initialFatMassKg + 10.4);
    final enthalpy = (pFat * 9400.0) + ((1.0 - pFat) * 1800.0);

    return AdaptiveCoachState(
      estimatedMassKg: initialWeightKg,
      tissueVelocityKgPerDay: 0.0,
      p00: 0.10,
      p01: 0.001,
      p10: 0.001,
      p11: 0.0001,
      tdeeKcal: initialTdeeKcal,
      resVariance: 0.0050,
      informationGain: 0.0,
      tissueEnthalpy: enthalpy,
    );
  }
}

class PrescriptionVector {
  final int caloriesKcal;
  final int proteinG;
  final int fatG;
  final int carbsG;
  final double calculatedTdeeKcal;
  final double trendWeightKg;
  final double tissueVelocityKgPerDay;
  final double informationGain;
  final double piAdjustmentKcal;

  const PrescriptionVector({
    required this.caloriesKcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.calculatedTdeeKcal,
    required this.trendWeightKg,
    required this.tissueVelocityKgPerDay,
    required this.informationGain,
    required this.piAdjustmentKcal,
  });
}

class AdaptiveCoachEngine {
  static const double sigmaQL2 = 1.0e-3;
  static const double sigmaQv2 = 2.0e-5;
  static const double rwVariance = 0.35;
  static const double deltaPos = 0.70;
  static const double deltaNeg = 0.90;
  static const double velocityDampingMissing = 0.90;

  static const double kappaForbes = 10.4;
  static const double rhoFat = 9400.0;
  static const double rhoLean = 1800.0;

  static const double lambdaRes = 0.05;
  static const double maxTdeeDailyStep = 24.0;

  static const double catchupDays = 42.0;
  static const double maxCatchupKgPerDay = 0.05;
  static const double maxWeeklyChangeKcal = 200.0;
  static const double positionDeadbandKg = 0.25;
  static const double velocityDeadbandKgPerDay = 0.01;
  static const double clinicalFloorKcal = 1200.0;
  static const double clinicalCeilingKcal = 4500.0;

  static double estimateInitialFatMass({
    required double weightKg,
    required double heightCm,
    required int ageYears,
    required String gender,
  }) {
    final heightM = heightCm / 100.0;
    final bmi = weightKg / (heightM * heightM);
    final isMale = gender.toLowerCase() == 'male' ? 1 : 0;

    final bfPct = (63.7 - (864.0 / bmi) - (12.1 * isMale) + (0.12 * ageYears))
        .clamp(5.0, 60.0) / 100.0;
    return weightKg * bfPct;
  }

  static double calculateBmr({
    required double weightKg,
    required double heightCm,
    required int ageYears,
    required String gender,
  }) {
    final isMale = gender.toLowerCase() == 'male';
    if (isMale) {
      return (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * ageYears) + 5.0;
    } else {
      return (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * ageYears) - 161.0;
    }
  }

  static AdaptiveCoachState stepObserver({
    required AdaptiveCoachState prevState,
    required double? scaleWeightLogKg,
    required double validMeanCalories14d,
    required int validIntakeDaysCount,
    required double initialFatMassKg,
    required double heightCm,
    required int ageYears,
    required String gender,
    required int studyDayIndex,
    double activityMultiplier = 1.38,
  }) {
    // Predict tissue mass and velocity before incorporating the next scale reading.
    final xPredL = prevState.estimatedMassKg + prevState.tissueVelocityKgPerDay;
    final xPredV = prevState.tissueVelocityKgPerDay;

    final pPred00 = prevState.p00 + (2.0 * prevState.p01) + prevState.p11 + sigmaQL2;
    final pPred01 = prevState.p01 + prevState.p11;
    final pPred10 = pPred01;
    final pPred11 = prevState.p11 + sigmaQv2;

    double updatedL = xPredL;
    double updatedV = xPredV;
    double updatedP00 = pPred00;
    double updatedP01 = pPred01;
    double updatedP10 = pPred10;
    double updatedP11 = pPred11;

    if (scaleWeightLogKg != null && scaleWeightLogKg > 0) {
      final yk = scaleWeightLogKg - xPredL;
      final sk = pPred00 + rwVariance;

      final k0 = pPred00 / sk;
      final k1 = pPred10 / sk;

      double psi = 1.0;
      if (yk > 0) {
        psi = math.min(1.0, deltaPos / yk);
      } else {
        psi = math.min(1.0, deltaNeg / yk.abs());
      }

      // Huber attenuation limits the influence of sudden weight jumps.
      final k0Star = k0 * psi;
      final k1Star = k1 * psi;

      updatedL = xPredL + (k0Star * yk);
      updatedV = xPredV + (k1Star * yk);

      updatedP00 = (1.0 - k0Star) * pPred00;
      updatedP01 = (1.0 - k0Star) * pPred01;
      updatedP10 = pPred10 - (k1Star * pPred00);
      updatedP11 = pPred11 - (k1Star * pPred01);
    } else {
      updatedV = xPredV * velocityDampingMissing;
      updatedL = prevState.estimatedMassKg + updatedV;
    }

    // Convert trend-weight velocity to stored energy using the Forbes fat fraction.
    final pFat = initialFatMassKg / (initialFatMassKg + kappaForbes);
    final rhoW = (pFat * rhoFat) + ((1.0 - pFat) * rhoLean);
    final energyStoredFlux = updatedV * rhoW;

    final bmr = calculateBmr(
      weightKg: updatedL,
      heightCm: heightCm,
      ageYears: ageYears,
      gender: gender,
    );
    final tdeePrior = bmr * activityMultiplier;

    final bool hasSufficientIntake = validIntakeDaysCount >= 4 && validMeanCalories14d > 0;

    double omegaK = 0.0;
    double updatedResVariance = prevState.resVariance;
    double? tdeeThermo;

    if (hasSufficientIntake) {
      final qCoverage = ((validIntakeDaysCount - 3.0) / 8.0).clamp(0.0, 1.0);
      final cImplied = math.max(1000.0, prevState.tdeeKcal + energyStoredFlux);
      final rk = (validMeanCalories14d - cImplied) / cImplied;

      updatedResVariance = ((1.0 - lambdaRes) * prevState.resVariance) + (lambdaRes * (rk * rk));

      final rReliability = math.exp(-updatedResVariance / (2.0 * 0.12 * 0.12));

      omegaK = qCoverage * rReliability;

      // Intake completeness cannot be inferred independently from expenditure.
      tdeeThermo = validMeanCalories14d - energyStoredFlux;
    }

    // Without enough intake logs, freeze expenditure after its initial estimate.
    double updatedTdee = prevState.tdeeKcal;

    if (hasSufficientIntake && tdeeThermo != null) {
      final tdeeTarget = ((1.0 - omegaK) * tdeePrior) + (omegaK * tdeeThermo);
      final tdeeBounded = tdeeTarget.clamp(1.05 * bmr, 2.10 * bmr);

      final learningRate = 0.05 + (0.15 * omegaK);
      final rawStep = (tdeeBounded - prevState.tdeeKcal) * learningRate;
      final clampedStep = rawStep.clamp(-maxTdeeDailyStep, maxTdeeDailyStep);
      updatedTdee = prevState.tdeeKcal + clampedStep;
    } else if (studyDayIndex == 0) {
      updatedTdee = tdeePrior;
    }

    return AdaptiveCoachState(
      estimatedMassKg: updatedL,
      tissueVelocityKgPerDay: updatedV,
      p00: updatedP00,
      p01: updatedP01,
      p10: updatedP10,
      p11: updatedP11,
      tdeeKcal: updatedTdee,
      resVariance: updatedResVariance,
      informationGain: omegaK,
      tissueEnthalpy: rhoW,
    );
  }

  static PrescriptionVector synthesizePrescription({
    required AdaptiveCoachState currentState,
    required double initialPhaseMassKg,
    required double targetWeeklyWeightDeltaKg,
    required int phaseDayIndex,
    double? currentTargetCaloriesKcal,
    required double proteinMultiplierGPerKg,
    double lipidFloorMultiplierGPerKg = 0.60,
  }) {
    final vTarget = targetWeeklyWeightDeltaKg / 7.0;
    final lIdeal = initialPhaseMassKg + (vTarget * phaseDayIndex);

    final ePos = currentState.estimatedMassKg - lIdeal;
    final catchupVelocity = (ePos / catchupDays)
        .clamp(-maxCatchupKgPerDay, maxCatchupKgPerDay);
    final desiredVelocity = vTarget - catchupVelocity;
    final velocityGap = desiredVelocity - currentState.tissueVelocityKgPerDay;
    double changeKcal = velocityGap.abs() < velocityDeadbandKgPerDay
        ? 0.0
        : (velocityGap * currentState.tissueEnthalpy)
            .clamp(-maxWeeklyChangeKcal, maxWeeklyChangeKcal);
    if (ePos > positionDeadbandKg) changeKcal = math.min(0.0, changeKcal);
    if (ePos < -positionDeadbandKg) changeKcal = math.max(0.0, changeKcal);

    final baseline = currentTargetCaloriesKcal != null &&
            currentTargetCaloriesKcal.isFinite && currentTargetCaloriesKcal > 0
        ? currentTargetCaloriesKcal
        : currentState.tdeeKcal + (targetWeeklyWeightDeltaKg * 7700.0 / 7.0);
    final eTargetContinuous = (baseline + changeKcal)
        .clamp(clinicalFloorKcal, clinicalCeilingKcal);
    final int eTarget = eTargetContinuous.round();

    final int proteinG = (currentState.estimatedMassKg * proteinMultiplierGPerKg).round();
    final double lipidFloorG = currentState.estimatedMassKg * lipidFloorMultiplierGPerKg;
    final double lipidNominalG = (0.25 * eTargetContinuous) / 9.0;
    int fatG = math.max(lipidFloorG, lipidNominalG).round();

    double energyCarbs = eTargetContinuous - (proteinG * 4 + fatG * 9);
    if (energyCarbs < (0.10 * eTargetContinuous)) {
      fatG = lipidFloorG.round();
      energyCarbs = eTargetContinuous - (proteinG * 4 + fatG * 9);
    }

    final int carbsG = math.max(30.0, energyCarbs / 4.0).round();

    return PrescriptionVector(
      caloriesKcal: eTarget,
      proteinG: proteinG,
      fatG: fatG,
      carbsG: carbsG,
      calculatedTdeeKcal: currentState.tdeeKcal,
      trendWeightKg: currentState.estimatedMassKg,
      tissueVelocityKgPerDay: currentState.tissueVelocityKgPerDay,
      informationGain: currentState.informationGain,
      piAdjustmentKcal: -changeKcal,
    );
  }
}
