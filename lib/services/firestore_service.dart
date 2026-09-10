import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_item.dart';
import '../models/daily_log.dart';
import '../models/weight_log.dart';
import '../models/user_profile.dart';
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

    // 1. Stream user document
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
      }
    });
    _subscriptions.add(profileSub);
  }

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

  // --- Optimistic In-Memory Mutations + Non-Blocking Firestore Background Sync ---

  Future<String> addLog(DailyLog log) async {
    final String id = log.id.isNotEmpty ? log.id : _db.collection('users').doc(_uid).collection('logs').doc().id;
    final resolvedLog = DailyLog(
      id: id,
      date: log.date,
      loggedAt: log.loggedAt,
      foodId: log.foodId,
      foodName: log.foodName,
      servingName: log.servingName,
      baseUnit: log.baseUnit,
      emoji: log.emoji,
      servings: log.servings,
      servingSizeG: log.servingSizeG,
      macros: log.macros,
      micros: log.micros,
    );

    // 1. Instant optimistic local state update
    final current = List<DailyLog>.from(logsNotifier.value)
      ..removeWhere((l) => l.id == id)
      ..add(resolvedLog);
    current.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    logsNotifier.value = current;

    // 2. Background Firestore write
    _db.collection('users').doc(_uid).collection('logs').doc(id).set(resolvedLog.toMap());
    return id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    // 1. Instant optimistic local state update
    final current = List<DailyLog>.from(logsNotifier.value);
    final idx = current.indexWhere((l) => l.id == id);
    if (idx != -1) {
      final old = current[idx];
      final map = old.toMap()..addAll(changes);
      current[idx] = DailyLog.fromFirestore(id, map);
      current.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      logsNotifier.value = current;
    }

    // 2. Background Firestore update
    _db.collection('users').doc(_uid).collection('logs').doc(id).update(changes);
  }

  Future<void> deleteLog(String id) async {
    // 1. Instant optimistic local state update
    final current = List<DailyLog>.from(logsNotifier.value)..removeWhere((l) => l.id == id);
    logsNotifier.value = current;

    // 2. Background Firestore delete
    _db.collection('users').doc(_uid).collection('logs').doc(id).delete();
  }

  Future<String> addFood(FoodItem food) async {
    final String id = food.id.isNotEmpty ? food.id : _db.collection('users').doc(_uid).collection('foods').doc().id;
    final resolvedFood = FoodItem(
      id: id,
      name: food.name,
      source: food.source,
      usdaFdcId: food.usdaFdcId,
      servingSizeG: food.servingSizeG,
      baseUnit: food.baseUnit,
      density: food.density,
      servingName: food.servingName,
      emoji: food.emoji,
      isFavorite: food.isFavorite,
      macros: food.macros,
      micros: food.micros,
      ingredients: food.ingredients,
    );

    // 1. Instant optimistic local state update
    final current = List<FoodItem>.from(foodsNotifier.value)
      ..removeWhere((f) => f.id == id)
      ..add(resolvedFood);
    foodsNotifier.value = current;

    // 2. Background Firestore write
    _db.collection('users').doc(_uid).collection('foods').doc(id).set(resolvedFood.toMap());
    return id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    // 1. Instant optimistic local state update
    final current = List<FoodItem>.from(foodsNotifier.value);
    final idx = current.indexWhere((f) => f.id == id);
    if (idx != -1) {
      final old = current[idx];
      final map = old.toMap()..addAll(changes);
      current[idx] = FoodItem.fromFirestore(id, map);
      foodsNotifier.value = current;
    }

    // 2. Background Firestore update
    _db.collection('users').doc(_uid).collection('foods').doc(id).update(changes);
  }

  Future<void> deleteFood(String id) async {
    // 1. Instant optimistic local state update
    final current = List<FoodItem>.from(foodsNotifier.value)..removeWhere((f) => f.id == id);
    foodsNotifier.value = current;

    // 2. Background Firestore delete
    _db.collection('users').doc(_uid).collection('foods').doc(id).delete();
  }

  Future<void> setWeightLog(WeightLog log) async {
    // 1. Instant optimistic local state update
    final current = List<WeightLog>.from(weightLogsNotifier.value)
      ..removeWhere((w) => w.date == log.date)
      ..add(log);
    current.sort((a, b) => a.date.compareTo(b.date));
    weightLogsNotifier.value = current;

    // 2. Background Firestore writes
    _db.collection('users').doc(_uid).collection('weight_logs').doc(log.date).set(
      log.toMap(),
      SetOptions(merge: true),
    );

    final Map<String, dynamic> profileUpdates = {
      'weight': log.weightKg,
    };
    _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      profileUpdates,
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWeightLog(String date) async {
    // 1. Instant optimistic local state update
    final current = List<WeightLog>.from(weightLogsNotifier.value)..removeWhere((w) => w.date == date);
    weightLogsNotifier.value = current;

    // 2. Background Firestore delete
    _db.collection('users').doc(_uid).collection('weight_logs').doc(date).delete();
  }

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

    _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      updatedProfile.toMap(),
      SetOptions(merge: true),
    );
  }
}