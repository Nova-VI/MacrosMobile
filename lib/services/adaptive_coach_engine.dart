import 'dart:math' as math;

/// State container representing the complete latent state of the observer & controller.
class AdaptiveCoachState {
  final double estimatedMassKg; // L_k
  final double tissueVelocityKgPerDay; // v_k
  final double p00;
  final double p01;
  final double p10;
  final double p11;
  final double tdeeKcal; // μ_TDEE,k
  final double latentIntakeBias; // b^{intake}_k
  final double integratorKcalDays; // I_k
  final double resVariance; // σ²_res,k
  final double biasVariance; // σ²_bias,k
  final double informationGain; // Ω_k
  final double tissueEnthalpy; // ρ_W(F_k)

  const AdaptiveCoachState({
    required this.estimatedMassKg,
    required this.tissueVelocityKgPerDay,
    this.p00 = 0.10,
    this.p01 = 0.001,
    this.p10 = 0.001,
    this.p11 = 0.0001,
    required this.tdeeKcal,
    this.latentIntakeBias = 0.88,
    this.integratorKcalDays = 0.0,
    this.resVariance = 0.0050,
    this.biasVariance = 0.00005,
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
      latentIntakeBias: 0.88,
      integratorKcalDays: 0.0,
      resVariance: 0.0050,
      biasVariance: 0.00005,
      informationGain: 0.0,
      tissueEnthalpy: enthalpy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'estimated_mass_kg': estimatedMassKg,
      'tissue_velocity_kg_day': tissueVelocityKgPerDay,
      'p00': p00,
      'p01': p01,
      'p10': p10,
      'p11': p11,
      'tdee_kcal': tdeeKcal,
      'latent_intake_bias': latentIntakeBias,
      'integrator_kcal_days': integratorKcalDays,
      'res_variance': resVariance,
      'bias_variance': biasVariance,
      'information_gain': informationGain,
      'tissue_enthalpy': tissueEnthalpy,
    };
  }

  factory AdaptiveCoachState.fromMap(Map<String, dynamic> data) {
    return AdaptiveCoachState(
      estimatedMassKg: (data['estimated_mass_kg'] as num?)?.toDouble() ?? 70.0,
      tissueVelocityKgPerDay: (data['tissue_velocity_kg_day'] as num?)?.toDouble() ?? 0.0,
      p00: (data['p00'] as num?)?.toDouble() ?? 0.10,
      p01: (data['p01'] as num?)?.toDouble() ?? 0.001,
      p10: (data['p10'] as num?)?.toDouble() ?? 0.001,
      p11: (data['p11'] as num?)?.toDouble() ?? 0.0001,
      tdeeKcal: (data['tdee_kcal'] as num?)?.toDouble() ?? 2000.0,
      latentIntakeBias: (data['latent_intake_bias'] as num?)?.toDouble() ?? 0.88,
      integratorKcalDays: (data['integrator_kcal_days'] as num?)?.toDouble() ?? 0.0,
      resVariance: (data['res_variance'] as num?)?.toDouble() ?? 0.0050,
      biasVariance: (data['bias_variance'] as num?)?.toDouble() ?? 0.00005,
      informationGain: (data['information_gain'] as num?)?.toDouble() ?? 0.0,
      tissueEnthalpy: (data['tissue_enthalpy'] as num?)?.toDouble() ?? 7700.0,
    );
  }
}

/// Output prescription containing the daily calorie budget and exact integer macronutrients.
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
  // Kinematic & Filter Constants
  static const double sigmaQL2 = 1.0e-3;
  static const double sigmaQv2 = 2.0e-5;
  static const double rwVariance = 0.35;
  static const double deltaPos = 0.70;
  static const double deltaNeg = 0.90;

  // Forbes Thermodynamic Constants
  static const double kappaForbes = 10.4;
  static const double rhoFat = 9400.0;
  static const double rhoLean = 1800.0;

  // Latent Bias & Information Tracking Constants
  static const double alphaBias = 0.010;
  static const double lambdaRes = 0.05;
  static const double lambdaBias = 0.03;
  static const double deltaMaxTdeeDaily = 18.0;

  // PI Controller Constants
  static const double kpGain = 4200.0;
  static const double kiGain = 45.0;
  static const double iMax = 50.0;
  static const double clinicalFloorKcal = 1200.0;
  static const double clinicalCeilingKcal = 4500.0;

  /// Calculates baseline initial fat mass via Gallagher body composition regression.
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

  /// Calculates baseline demographic BMR via Mifflin-St Jeor.
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

  /// Steps the Observer forward by 1 discrete day (Δt = 1 day).
  static AdaptiveCoachState stepObserver({
    required AdaptiveCoachState prevState,
    required double? scaleWeightLogKg, // W_k (null if unmeasured)
    required double validMeanCalories14d, // C̄_k
    required int validIntakeDaysCount, // N_c
    required double initialFatMassKg,
    required double heightCm,
    required int ageYears,
    required String gender,
    required int studyDayIndex, // k
    double activityMultiplier = 1.38,
  }) {
    // -------------------------------------------------------------
    // 1. Kinematic A Priori Prediction
    // -------------------------------------------------------------
    final xPredL = prevState.estimatedMassKg + prevState.tissueVelocityKgPerDay;
    final xPredV = prevState.tissueVelocityKgPerDay;

    final pPred00 = prevState.p00 + (2.0 * prevState.p01) + prevState.p11 + sigmaQL2;
    final pPred01 = prevState.p01 + prevState.p11;
    final pPred10 = pPred01;
    final pPred11 = prevState.p11 + sigmaQv2;

    // -------------------------------------------------------------
    // 2. Innovation & Asymmetric Huber Attenuation
    // -------------------------------------------------------------
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

      final k0Star = k0 * psi;
      final k1Star = k1 * psi;

      updatedL = xPredL + (k0Star * yk);
      updatedV = xPredV + (k1Star * yk);

      updatedP00 = (1.0 - k0Star) * pPred00;
      updatedP01 = (1.0 - k0Star) * pPred01;
      updatedP10 = pPred10 - (k1Star * pPred00);
      updatedP11 = pPred11 - (k1Star * pPred01);
    }

    // -------------------------------------------------------------
    // 3. Dynamic Forbes Enthalpy Evaluation
    // -------------------------------------------------------------
    final pFat = initialFatMassKg / (initialFatMassKg + kappaForbes);
    final rhoW = (pFat * rhoFat) + ((1.0 - pFat) * rhoLean);
    final energyStoredFlux = updatedV * rhoW;

    // -------------------------------------------------------------
    // 4. Dual-Information Quality Assessment
    // -------------------------------------------------------------
    final qCoverage = ((validIntakeDaysCount - 3.0) / 8.0).clamp(0.0, 1.0);

    final cImplied = prevState.tdeeKcal + energyStoredFlux;
    final cImpliedSafe = math.max(1000.0, cImplied);
    final rk = (validMeanCalories14d - (prevState.latentIntakeBias * cImpliedSafe)) / cImpliedSafe;

    final updatedResVariance = ((1.0 - lambdaRes) * prevState.resVariance) + (lambdaRes * (rk * rk));

    // Latent Bias Evolution
    double updatedBias = prevState.latentIntakeBias;
    if (validIntakeDaysCount >= 7 && studyDayIndex >= 21) {
      final impliedIntake = math.max(1000.0, prevState.tdeeKcal + energyStoredFlux);
      final observedRatio = validMeanCalories14d / impliedIntake;
      updatedBias = ((1.0 - alphaBias) * prevState.latentIntakeBias) + (alphaBias * observedRatio);
      updatedBias = updatedBias.clamp(0.60, 1.10);
    }

    final biasDelta = updatedBias - prevState.latentIntakeBias;
    final updatedBiasVariance = ((1.0 - lambdaBias) * prevState.biasVariance) + (lambdaBias * (biasDelta * biasDelta));

    final rReliability = math.exp(-updatedResVariance / (2.0 * 0.12 * 0.12)) *
        math.exp(-updatedBiasVariance / (2.0 * 0.015 * 0.015));

    final omegaK = qCoverage * rReliability;

    // -------------------------------------------------------------
    // 5. TDEE Posterior State Synthesis
    // -------------------------------------------------------------
    final bmr = calculateBmr(
      weightKg: updatedL,
      heightCm: heightCm,
      ageYears: ageYears,
      gender: gender,
    );
    final tdeePrior = bmr * activityMultiplier;

    final safeBias = updatedBias.clamp(0.60, 1.10);
    final tdeeThermo = (validMeanCalories14d / safeBias) - energyStoredFlux;

    final tdeeTarget = ((1.0 - omegaK) * tdeePrior) + (omegaK * tdeeThermo);
    final tdeeBounded = tdeeTarget.clamp(1.05 * bmr, 2.10 * bmr);

    final tdeeDelta = (tdeeBounded - prevState.tdeeKcal).clamp(-deltaMaxTdeeDaily, deltaMaxTdeeDaily);
    final updatedTdee = prevState.tdeeKcal + ((0.05 + (0.03 * omegaK)) * tdeeDelta);

    return AdaptiveCoachState(
      estimatedMassKg: updatedL,
      tissueVelocityKgPerDay: updatedV,
      p00: updatedP00,
      p01: updatedP01,
      p10: updatedP10,
      p11: updatedP11,
      tdeeKcal: updatedTdee,
      latentIntakeBias: updatedBias,
      integratorKcalDays: prevState.integratorKcalDays,
      resVariance: updatedResVariance,
      biasVariance: updatedBiasVariance,
      informationGain: omegaK,
      tissueEnthalpy: rhoW,
    );
  }

  /// Synthesizes the Closed-Loop PI Target and Integer Macronutrient Vector.
  static PrescriptionVector synthesizePrescription({
    required AdaptiveCoachState currentState,
    required double initialPhaseMassKg, // L_0
    required double targetWeeklyWeightDeltaKg, // e.g. -0.50 kg/week
    required int phaseDayIndex, // k (days elapsed in current phase)
    required double proteinMultiplierGPerKg, // e.g. 2.0 g/kg
    double lipidFloorMultiplierGPerKg = 0.60,
  }) {
    final vTarget = targetWeeklyWeightDeltaKg / 7.0;
    final lIdeal = initialPhaseMassKg + (vTarget * phaseDayIndex);

    final ePos = currentState.estimatedMassKg - lIdeal;
    final eV = currentState.tissueVelocityKgPerDay - vTarget;

    final updatedIntegrator = (currentState.integratorKcalDays + (ePos * 1.0)).clamp(-iMax, iMax);

    final deltaPI = (kpGain * eV) + (kiGain * updatedIntegrator);

    final eNominal = currentState.tdeeKcal + (vTarget * currentState.tissueEnthalpy);
    final eTargetContinuous = (eNominal - deltaPI).clamp(clinicalFloorKcal, clinicalCeilingKcal);
    final int eTarget = eTargetContinuous.round();

    // -------------------------------------------------------------
    // Macronutrient Allocation
    // -------------------------------------------------------------
    final int proteinG = (currentState.estimatedMassKg * proteinMultiplierGPerKg).round();
    final int energyProtein = proteinG * 4;

    final double lipidFloorG = currentState.estimatedMassKg * lipidFloorMultiplierGPerKg;
    final double lipidNominalG = (0.25 * eTargetContinuous) / 9.0;
    int fatG = math.max(lipidFloorG, lipidNominalG).round();
    int energyFat = fatG * 9;

    double energyCarbs = eTargetContinuous - (energyProtein + energyFat);

    // Feasibility Slack Check
    if (energyCarbs < (0.10 * eTargetContinuous)) {
      fatG = lipidFloorG.round();
      energyFat = fatG * 9;
      energyCarbs = eTargetContinuous - (energyProtein + energyFat);
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
      piAdjustmentKcal: deltaPI,
    );
  }
}