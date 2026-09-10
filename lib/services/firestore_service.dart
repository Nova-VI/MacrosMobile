import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_item.dart';
import '../models/daily_log.dart';
import '../models/weight_log.dart';
import '../models/user_profile.dart';
import 'adaptive_coach_engine.dart';
import 'adaptive_coach_service.dart';
import 'auth_service.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final ValueNotifier<List<DailyLog>> logsNotifier = ValueNotifier([]);
  final ValueNotifier<List<FoodItem>> foodsNotifier = ValueNotifier([]);
  final ValueNotifier<List<WeightLog>> weightLogsNotifier = ValueNotifier([]);
  final ValueNotifier<UserProfile> profileNotifier = ValueNotifier(UserProfile());

  final List<StreamSubscription> _subscriptions = [];

  String? get currentUid => _auth.currentUser?.uid;

  String get _uid {
    final uid = currentUid;
    if (uid == null) throw Exception('No authenticated user found');
    return uid;
  }

  void initializeListeners(String uid) {
    cancelListeners();

    // 1. Stream user document for remote profile & name synchronization
    final userSub = _db.collection('users').doc(uid).snapshots().listen((doc) async {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final remoteName = data['displayName']?.toString() ?? '';
        final remoteCompleted = data['onboarding_completed'] == true;

        final prefs = await SharedPreferences.getInstance();
        final cachedName = prefs.getString('cached_user_name_$uid') ?? '';
        final cachedCompleted = prefs.getBool('onboarding_completed_$uid');

        if (remoteName.isNotEmpty && remoteName != cachedName) {
          await prefs.setString('cached_user_name_$uid', remoteName);
          AuthService.userNameNotifier.value = remoteName;
        }

        if (cachedCompleted != remoteCompleted) {
          await prefs.setBool('onboarding_completed_$uid', remoteCompleted);
          AuthService.onboardingCompletedNotifier.value = remoteCompleted;
        }
      }
    });
    _subscriptions.add(userSub);

    // 2. Stream all foods
    final foodSub = _db
        .collection('users')
        .doc(uid)
        .collection('foods')
        .snapshots()
        .listen((snapshot) {
      foodsNotifier.value = snapshot.docs
          .map((doc) => FoodItem.fromFirestore(doc.id, doc.data()))
          .toList();
    });
    _subscriptions.add(foodSub);

    // 3. Stream all logs
    final logSub = _db
        .collection('users')
        .doc(uid)
        .collection('logs')
        .snapshots()
        .listen((snapshot) {
      final logs = snapshot.docs
          .map((doc) => DailyLog.fromFirestore(doc.id, doc.data()))
          .toList();
      logs.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      logsNotifier.value = logs;

      _runLegacyAccountMigrationOnce(uid, profileNotifier.value, logs, weightLogsNotifier.value);
      _backfillHistoricalTrendWeightsIfMissing(uid, profileNotifier.value, logs, weightLogsNotifier.value);
    });
    _subscriptions.add(logSub);

    // 4. Stream weight logs
    final weightSub = _db
        .collection('users')
        .doc(uid)
        .collection('weight_logs')
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs
          .map((doc) => WeightLog.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => a.date.compareTo(b.date));
      weightLogsNotifier.value = list;

      _runLegacyAccountMigrationOnce(uid, profileNotifier.value, logsNotifier.value, list);
      _backfillHistoricalTrendWeightsIfMissing(uid, profileNotifier.value, logsNotifier.value, list);
    });
    _subscriptions.add(weightSub);

    // 5. Stream profile
    final profileSub = _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('1')
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        final profile = UserProfile.fromFirestore(doc.data());
        profileNotifier.value = profile;

        _runLegacyAccountMigrationOnce(uid, profile, logsNotifier.value, weightLogsNotifier.value);
        _backfillHistoricalTrendWeightsIfMissing(uid, profile, logsNotifier.value, weightLogsNotifier.value);
      }
    });
    _subscriptions.add(profileSub);
  }

  // ============================================================================
  // TODO: TEMPORARY MIGRATION SCRIPT - REMOVE ONCE OLD ACCOUNTS HAVE TRANSITIONED
  // Runs only once per user. Starts current GoalPhase from the very first log,
  // adds an initial adjustment from 8 days ago, and deletes legacy goal_history.
  // ============================================================================
  void _runLegacyAccountMigrationOnce(
    String uid,
    UserProfile profile,
    List<DailyLog> logs,
    List<WeightLog> weights,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final migrationKey = 'migrated_to_goal_phases_v2_$uid';
    if (prefs.getBool(migrationKey) == true) return;

    if (profile.goalPhases.isEmpty && (logs.isNotEmpty || weights.isNotEmpty)) {
      final allDates = [
        ...logs.map((l) => l.date),
        ...weights.map((w) => w.date),
      ].where((d) => d.isNotEmpty).toList()..sort();

      if (allDates.isEmpty) return;
      final earliestDate = allDates.first;

      final eightDaysAgo = DateFormat('yyyy-MM-dd').format(
        DateTime.now().subtract(const Duration(days: 8)),
      );

      final initialAdjustment = TargetAdjustment(
        id: 'legacy_transition_adjustment',
        date: eightDaysAgo,
        targetCalories: profile.targetCalories,
        targetProteinG: profile.targetProteinG,
        targetCarbsG: profile.targetCarbsG,
        targetFatG: profile.targetFatG,
        acceptedByUser: true,
        isManual: false,
        notes: 'Initial baseline setup from legacy profile transition',
      );

      final initialPhase = GoalPhase(
        id: 'legacy_initial_phase',
        startDate: earliestDate,
        goal: profile.goal,
        goalType: profile.goalType,
        initialCalories: profile.targetCalories,
        initialProteinG: profile.targetProteinG,
        initialCarbsG: profile.targetCarbsG,
        initialFatG: profile.targetFatG,
        adjustments: [initialAdjustment],
      );

      final updatedProfile = UserProfile(
        id: profile.id,
        goalMode: profile.goalMode,
        targetCalories: profile.targetCalories,
        targetProteinG: profile.targetProteinG,
        targetCarbsG: profile.targetCarbsG,
        targetFatG: profile.targetFatG,
        birthDate: profile.birthDate,
        gender: profile.gender,
        height: profile.height,
        weight: profile.weight,
        activity: profile.activity,
        goal: profile.goal,
        proteinMultiplier: profile.proteinMultiplier,
        estimatedTdee: profile.estimatedTdee,
        goalPhases: [initialPhase],
      );

      profileNotifier.value = updatedProfile;
      await prefs.setBool(migrationKey, true);

      // Persist to Firestore and delete legacy goal_history field
      await _db.collection('users').doc(uid).collection('profile').doc('1').set({
        ...updatedProfile.toMap(),
        'goal_history': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
  }

  // ============================================================================
  // TODO: TEMPORARY MIGRATION SCRIPT - REMOVE ONCE OLD ACCOUNTS HAVE TRANSITIONED
  // Idempotently backfills trend_weight_kg for all past historical weight logs.
  // ============================================================================
  void _backfillHistoricalTrendWeightsIfMissing(
    String uid,
    UserProfile profile,
    List<DailyLog> logs,
    List<WeightLog> weights,
  ) async {
    if (weights.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final migrationKey = 'trend_weights_migrated_v1_$uid';
    final alreadyMigrated = prefs.getBool(migrationKey) ?? false;
    final needsBackfill = weights.any((w) => w.trendWeightKg == null);

    // If already marked as migrated and no document lacks a trend weight, exit immediately
    if (alreadyMigrated && !needsBackfill) return;

    // 1. Build chronological timeline
    final weightDates = weights.map((w) => w.date).where((d) => d.isNotEmpty);
    final logDates = logs.map((l) => l.date).where((d) => d.isNotEmpty);
    final allDates = {...weightDates, ...logDates}.toList()..sort();
    if (allDates.isEmpty) return;

    final startDateStr = allDates.first;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime cursor = DateFormat('yyyy-MM-dd').parse(startDateStr);

    final Map<String, double> dailyWeightsMap = {};
    for (final w in weights) {
      dailyWeightsMap[w.date] = w.weightKg;
    }

    final Map<String, double> dailyCaloriesMap = {};
    for (final l in logs) {
      dailyCaloriesMap[l.date] = (dailyCaloriesMap[l.date] ?? 0.0) + l.macros.calories;
    }

    final initialWeight = weights.first.weightKg;
    final initialFat = AdaptiveCoachEngine.estimateInitialFatMass(
      weightKg: initialWeight,
      heightCm: profile.height,
      ageYears: profile.age,
      gender: profile.gender,
    );
    final initialBmr = AdaptiveCoachEngine.calculateBmr(
      weightKg: initialWeight,
      heightCm: profile.height,
      ageYears: profile.age,
      gender: profile.gender,
    );
    final activityMultiplier = double.tryParse(profile.activity) ?? 1.38;
    final initialTdee = initialBmr * activityMultiplier;

    AdaptiveCoachState currentState = AdaptiveCoachState.initial(
      initialWeightKg: initialWeight,
      initialTdeeKcal: initialTdee,
      initialFatMassKg: initialFat,
    );

    int studyDay = 0;
    final List<double> recent14dCalories = [];
    final Map<String, double> computedTrendWeights = {};

    // 2. Replay Kalman filter step-by-step
    while (!cursor.isAfter(today)) {
      final dateKey = DateFormat('yyyy-MM-dd').format(cursor);
      final isToday = cursor.year == today.year && cursor.month == today.month && cursor.day == today.day;
      final weightReading = dailyWeightsMap[dateKey];
      final calorieTotal = dailyCaloriesMap[dateKey] ?? 0.0;

      if (!isToday && calorieTotal >= 450.0) {
        recent14dCalories.add(calorieTotal);
        if (recent14dCalories.length > 14) {
          recent14dCalories.removeAt(0);
        }
      }

      final validCount = recent14dCalories.length;
      final validMean = validCount > 0
          ? (recent14dCalories.reduce((a, b) => a + b) / validCount)
          : initialTdee;

      currentState = AdaptiveCoachEngine.stepObserver(
        prevState: currentState,
        scaleWeightLogKg: weightReading,
        validMeanCalories14d: validMean,
        validIntakeDaysCount: validCount,
        initialFatMassKg: initialFat,
        heightCm: profile.height,
        ageYears: profile.age,
        gender: profile.gender,
        studyDayIndex: studyDay,
        activityMultiplier: activityMultiplier,
      );

      if (dailyWeightsMap.containsKey(dateKey)) {
        computedTrendWeights[dateKey] = double.parse(currentState.estimatedMassKg.toStringAsFixed(2));
      }

      studyDay++;
      cursor = cursor.add(const Duration(days: 1));
    }

    // 3. Collect only the documents that actually need to be backfilled
    final Map<String, double> updatesNeeded = {};
    for (final w in weights) {
      final calculatedTrend = computedTrendWeights[w.date];
      if (calculatedTrend != null && (w.trendWeightKg == null || (w.trendWeightKg! - calculatedTrend).abs() > 0.05)) {
        updatesNeeded[w.date] = calculatedTrend;
      }
    }

    if (updatesNeeded.isEmpty) {
      await prefs.setBool(migrationKey, true);
      return;
    }

    // 4. Batch write in safe chunks of 400 (Firestore max limit is 500 per batch)
    final entries = updatesNeeded.entries.toList();
    const chunkSize = 400;
    for (int i = 0; i < entries.length; i += chunkSize) {
      final chunk = entries.sublist(i, math.min(i + chunkSize, entries.length));
      final batch = _db.batch();
      for (final entry in chunk) {
        final docRef = _db.collection('users').doc(uid).collection('weight_logs').doc(entry.key);
        batch.set(docRef, {'trend_weight_kg': entry.value}, SetOptions(merge: true));
      }
      await batch.commit();
    }

    await prefs.setBool(migrationKey, true);
  }
  // ============================================================================

  void cancelListeners() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    logsNotifier.value = [];
    foodsNotifier.value = [];
    weightLogsNotifier.value = [];
    profileNotifier.value = UserProfile();
  }

  List<DailyLog> getLogsForDate(String date) {
    return logsNotifier.value.where((log) => log.date == date).toList();
  }

  List<FoodItem> getFavoriteFoods() {
    return foodsNotifier.value.where((food) => food.isFavorite).toList();
  }

  List<FoodItem> getFrequentFoods({int limit = 8}) {
    final logs = logsNotifier.value;
    final counts = <String, int>{};
    for (final log in logs) {
      if (log.foodId != null && log.foodId!.isNotEmpty) {
        counts[log.foodId!] = (counts[log.foodId!] ?? 0) + 1;
      }
    }

    final nonFavorites = foodsNotifier.value.where((f) => !f.isFavorite).toList();
    nonFavorites.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    return nonFavorites.where((f) => (counts[f.id] ?? 0) > 0).take(limit).toList();
  }

  Future<String> addLog(DailyLog log) async {
    final ref = _db.collection('users').doc(_uid).collection('logs').doc();
    await ref.set(log.toMap());
    return ref.id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    await _db.collection('users').doc(_uid).collection('logs').doc(id).update(changes);
  }

  Future<void> deleteLog(String id) async {
    await _db.collection('users').doc(_uid).collection('logs').doc(id).delete();
  }

  Future<String> addFood(FoodItem food) async {
    final ref = _db.collection('users').doc(_uid).collection('foods').doc();
    await ref.set(food.toMap());
    return ref.id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    await _db.collection('users').doc(_uid).collection('foods').doc(id).update(changes);
  }

  Future<void> deleteFood(String id) async {
    await _db.collection('users').doc(_uid).collection('foods').doc(id).delete();
  }

  /// Sets weight log, calculates and attaches trend weight, and syncs estimated TDEE to profile.
  Future<void> setWeightLog(WeightLog log) async {
    final liveState = AdaptiveCoachService().liveObserverStateNotifier.value;
    final double trendWeight = log.trendWeightKg ?? (liveState?.estimatedMassKg ?? log.weightKg);
    final double? liveTdee = liveState?.tdeeKcal;

    final resolvedLog = WeightLog(
      date: log.date,
      weightKg: log.weightKg,
      trendWeightKg: trendWeight,
    );

    // 1. Write weight log with trend weight
    await _db.collection('users').doc(_uid).collection('weight_logs').doc(log.date).set(
      resolvedLog.toMap(),
      SetOptions(merge: true),
    );

    // 2. Sync in-memory estimated TDEE & latest weight to profile document
    final Map<String, dynamic> profileUpdates = {
      'weight': log.weightKg,
      if (liveTdee != null) 'estimated_tdee': liveTdee,
    };

    await _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      profileUpdates,
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWeightLog(String date) async {
    await _db.collection('users').doc(_uid).collection('weight_logs').doc(date).delete();
  }

  /// Saves the user profile with GoalPhases and TargetAdjustments.
  Future<void> saveProfile(UserProfile profile) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentProfile = profileNotifier.value;

    final currentPhases = List<GoalPhase>.from(
      profile.goalPhases.isNotEmpty ? profile.goalPhases : currentProfile.goalPhases,
    );

    final bool isGoalChanged = currentProfile.goal != profile.goal ||
        currentProfile.goalMode != profile.goalMode ||
        currentPhases.isEmpty;

    if (isGoalChanged) {
      if (currentPhases.isNotEmpty && currentPhases.last.endDate == null) {
        final lastPhase = currentPhases.removeLast();
        if (lastPhase.startDate != todayStr) {
          currentPhases.add(GoalPhase(
            id: lastPhase.id,
            startDate: lastPhase.startDate,
            endDate: todayStr,
            goal: lastPhase.goal,
            goalType: lastPhase.goalType,
            initialCalories: lastPhase.initialCalories,
            initialProteinG: lastPhase.initialProteinG,
            initialCarbsG: lastPhase.initialCarbsG,
            initialFatG: lastPhase.initialFatG,
            adjustments: lastPhase.adjustments,
          ));
        }
      }

      currentPhases.add(GoalPhase(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startDate: todayStr,
        goal: profile.goal,
        goalType: profile.goalType,
        initialCalories: profile.targetCalories,
        initialProteinG: profile.targetProteinG,
        initialCarbsG: profile.targetCarbsG,
        initialFatG: profile.targetFatG,
      ));
    }

    final updatedProfile = UserProfile(
      id: profile.id,
      goalMode: profile.goalMode,
      targetCalories: profile.targetCalories,
      targetProteinG: profile.targetProteinG,
      targetCarbsG: profile.targetCarbsG,
      targetFatG: profile.targetFatG,
      birthDate: profile.birthDate,
      gender: profile.gender,
      height: profile.height,
      weight: profile.weight,
      activity: profile.activity,
      goal: profile.goal,
      proteinMultiplier: profile.proteinMultiplier,
      estimatedTdee: profile.estimatedTdee,
      goalPhases: currentPhases,
    );

    profileNotifier.value = updatedProfile;

    await _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      updatedProfile.toMap(),
      SetOptions(merge: true),
    );
  }
}