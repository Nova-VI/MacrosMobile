// lib/services/firestore_service.dart
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
  int _lastSyncTimestamp = 0;
  bool _isReady = false;

  String? get currentUid => _auth.currentUser?.uid;

  String get _uid {
    final uid = currentUid;
    if (uid == null) throw Exception('No authenticated user found');
    return uid;
  }

  Future<void> _touchSyncMeta(String uid) async {
    try {
      await _db.collection('users').doc(uid).collection('meta').doc('sync').set({
        'last_modified': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<bool> _hydrateFromLocalDiskCache(String uid) async {
    try {
      final foodsSnap = await _db.collection('users').doc(uid).collection('foods').get(const GetOptions(source: Source.cache));
      final logsSnap = await _db.collection('users').doc(uid).collection('logs').get(const GetOptions(source: Source.cache));
      final weightSnap = await _db.collection('users').doc(uid).collection('weight_logs').get(const GetOptions(source: Source.cache));
      final profileSnap = await _db.collection('users').doc(uid).collection('profile').doc('1').get(const GetOptions(source: Source.cache));

      if (foodsSnap.docs.isNotEmpty || logsSnap.docs.isNotEmpty || weightSnap.docs.isNotEmpty) {
        foodsNotifier.value = foodsSnap.docs
            .where((d) => d.data()['_deleted'] != true)
            .map((doc) => FoodItem.fromFirestore(doc.id, doc.data()))
            .toList();

        final logs = logsSnap.docs
            .where((d) => d.data()['_deleted'] != true)
            .map((doc) => DailyLog.fromFirestore(doc.id, doc.data()))
            .toList();
        logs.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
        logsNotifier.value = logs;

        final weights = weightSnap.docs
            .where((d) => d.data()['_deleted'] != true)
            .map((doc) => WeightLog.fromFirestore(doc.data()))
            .toList();
        weights.sort((a, b) => a.date.compareTo(b.date));
        weightLogsNotifier.value = weights;

        if (profileSnap.exists && profileSnap.data() != null) {
          profileNotifier.value = UserProfile.fromFirestore(profileSnap.data());
        }

        _isReady = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _performInitialColdLoad(String uid) async {
    try {
      final foodsSnap = await _db.collection('users').doc(uid).collection('foods').get();
      final logsSnap = await _db.collection('users').doc(uid).collection('logs').get();
      final weightSnap = await _db.collection('users').doc(uid).collection('weight_logs').get();
      final profileSnap = await _db.collection('users').doc(uid).collection('profile').doc('1').get();

      foodsNotifier.value = foodsSnap.docs
          .where((d) => d.data()['_deleted'] != true)
          .map((doc) => FoodItem.fromFirestore(doc.id, doc.data()))
          .toList();

      final logs = logsSnap.docs
          .where((d) => d.data()['_deleted'] != true)
          .map((doc) => DailyLog.fromFirestore(doc.id, doc.data()))
          .toList();
      logs.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      logsNotifier.value = logs;

      final weights = weightSnap.docs
          .where((d) => d.data()['_deleted'] != true)
          .map((doc) => WeightLog.fromFirestore(doc.data()))
          .toList();
      weights.sort((a, b) => a.date.compareTo(b.date));
      weightLogsNotifier.value = weights;

      if (profileSnap.exists && profileSnap.data() != null) {
        profileNotifier.value = UserProfile.fromFirestore(profileSnap.data());
      }

      _lastSyncTimestamp = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_timestamp_$uid', _lastSyncTimestamp);
      _isReady = true;
    } catch (_) {}
  }

  Future<void> _syncDeltaChanges(String uid, int remoteLastModified) async {
    try {
      // 1. Foods Delta
      final foodsDelta = await _db
          .collection('users')
          .doc(uid)
          .collection('foods')
          .where('updated_at', isGreaterThan: _lastSyncTimestamp)
          .get();

      if (foodsDelta.docs.isNotEmpty) {
        final current = Map<String, FoodItem>.fromEntries(foodsNotifier.value.map((f) => MapEntry(f.id, f)));
        for (final doc in foodsDelta.docs) {
          final data = doc.data();
          if (data['_deleted'] == true) {
            current.remove(doc.id);
          } else {
            current[doc.id] = FoodItem.fromFirestore(doc.id, data);
          }
        }
        foodsNotifier.value = current.values.toList();
      }

      // 2. Logs Delta
      final logsDelta = await _db
          .collection('users')
          .doc(uid)
          .collection('logs')
          .where('updated_at', isGreaterThan: _lastSyncTimestamp)
          .get();

      if (logsDelta.docs.isNotEmpty) {
        final current = Map<String, DailyLog>.fromEntries(logsNotifier.value.map((l) => MapEntry(l.id, l)));
        for (final doc in logsDelta.docs) {
          final data = doc.data();
          if (data['_deleted'] == true) {
            current.remove(doc.id);
          } else {
            current[doc.id] = DailyLog.fromFirestore(doc.id, data);
          }
        }
        final list = current.values.toList()..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
        logsNotifier.value = list;
      }

      // 3. Weight Logs Delta
      final weightDelta = await _db
          .collection('users')
          .doc(uid)
          .collection('weight_logs')
          .where('updated_at', isGreaterThan: _lastSyncTimestamp)
          .get();

      if (weightDelta.docs.isNotEmpty) {
        final current = Map<String, WeightLog>.fromEntries(weightLogsNotifier.value.map((w) => MapEntry(w.date, w)));
        for (final doc in weightDelta.docs) {
          final data = doc.data();
          if (data['_deleted'] == true) {
            current.remove(doc.id);
          } else {
            current[doc.id] = WeightLog.fromFirestore(data);
          }
        }
        final list = current.values.toList()..sort((a, b) => a.date.compareTo(b.date));
        weightLogsNotifier.value = list;
      }

      // 4. Profile Delta
      final profileSnap = await _db.collection('users').doc(uid).collection('profile').doc('1').get();
      if (profileSnap.exists && profileSnap.data() != null) {
        final data = profileSnap.data()!;
        final updated = (data['updated_at'] as num?)?.toInt() ?? 0;
        if (updated > _lastSyncTimestamp) {
          profileNotifier.value = UserProfile.fromFirestore(data);
        }
      }

      _lastSyncTimestamp = remoteLastModified;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_timestamp_$uid', _lastSyncTimestamp);
    } catch (_) {}
  }

  void initializeListeners(String uid) async {
    cancelListeners();

    final prefs = await SharedPreferences.getInstance();
    _lastSyncTimestamp = prefs.getInt('last_sync_timestamp_$uid') ?? 0;

    // 1. User document stream
    final userSub = _db.collection('users').doc(uid).snapshots().listen((doc) async {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final remoteName = data['displayName']?.toString() ?? '';
        final remoteCompleted = data['onboarding_completed'] == true;

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

    // 2. Single Watchdog Pointer Stream
    final syncSub = _db.collection('users').doc(uid).collection('meta').doc('sync').snapshots().listen((snap) async {
      if (!snap.exists) {
        await _touchSyncMeta(uid);
        if (!_isReady) {
          final hydrated = await _hydrateFromLocalDiskCache(uid);
          if (!hydrated) await _performInitialColdLoad(uid);
        }
        return;
      }

      final remoteLastModified = (snap.data()?['last_modified'] as num?)?.toInt() ?? 0;

      if (!_isReady || _lastSyncTimestamp == 0) {
        final hydrated = await _hydrateFromLocalDiskCache(uid);
        if (!hydrated || _lastSyncTimestamp == 0) {
          await _performInitialColdLoad(uid);
          return;
        }
      }

      if (remoteLastModified > _lastSyncTimestamp) {
        await _syncDeltaChanges(uid, remoteLastModified);
      }
    });
    _subscriptions.add(syncSub);
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
    _isReady = false;
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

  // --- CRUD Operations ---

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

    final current = List<DailyLog>.from(logsNotifier.value)
      ..removeWhere((l) => l.id == id)
      ..add(resolvedLog);
    current.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    logsNotifier.value = current;

    final map = resolvedLog.toMap()..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('logs').doc(id).set(map);
    _touchSyncMeta(_uid);
    return id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    final current = List<DailyLog>.from(logsNotifier.value);
    final idx = current.indexWhere((l) => l.id == id);
    if (idx != -1) {
      final old = current[idx];
      final map = old.toMap()..addAll(changes);
      current[idx] = DailyLog.fromFirestore(id, map);
      current.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      logsNotifier.value = current;
    }

    final map = Map<String, dynamic>.from(changes)..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('logs').doc(id).update(map);
    _touchSyncMeta(_uid);
  }

  Future<void> deleteLog(String id) async {
    final current = List<DailyLog>.from(logsNotifier.value)..removeWhere((l) => l.id == id);
    logsNotifier.value = current;

    _db.collection('users').doc(_uid).collection('logs').doc(id).set({
      '_deleted': true,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    _touchSyncMeta(_uid);
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

    final current = List<FoodItem>.from(foodsNotifier.value)
      ..removeWhere((f) => f.id == id)
      ..add(resolvedFood);
    foodsNotifier.value = current;

    final map = resolvedFood.toMap()..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('foods').doc(id).set(map);
    _touchSyncMeta(_uid);
    return id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    final current = List<FoodItem>.from(foodsNotifier.value);
    final idx = current.indexWhere((f) => f.id == id);
    if (idx != -1) {
      final old = current[idx];
      final map = old.toMap()..addAll(changes);
      current[idx] = FoodItem.fromFirestore(id, map);
      foodsNotifier.value = current;
    }

    final map = Map<String, dynamic>.from(changes)..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('foods').doc(id).update(map);
    _touchSyncMeta(_uid);
  }

  Future<void> deleteFood(String id) async {
    final current = List<FoodItem>.from(foodsNotifier.value)..removeWhere((f) => f.id == id);
    foodsNotifier.value = current;

    _db.collection('users').doc(_uid).collection('foods').doc(id).set({
      '_deleted': true,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    _touchSyncMeta(_uid);
  }

  Future<void> setWeightLog(WeightLog log) async {
    final current = List<WeightLog>.from(weightLogsNotifier.value)
      ..removeWhere((w) => w.date == log.date)
      ..add(log);
    current.sort((a, b) => a.date.compareTo(b.date));
    weightLogsNotifier.value = current;

    final map = log.toMap()..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('weight_logs').doc(log.date).set(map, SetOptions(merge: true));

    _db.collection('users').doc(_uid).collection('profile').doc('1').set({
      'weight': log.weightKg,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));

    _touchSyncMeta(_uid);
  }

  Future<void> deleteWeightLog(String date) async {
    final current = List<WeightLog>.from(weightLogsNotifier.value)..removeWhere((w) => w.date == date);
    weightLogsNotifier.value = current;

    _db.collection('users').doc(_uid).collection('weight_logs').doc(date).set({
      '_deleted': true,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    _touchSyncMeta(_uid);
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
          final yesterdayStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
          currentPhases.add(GoalPhase(
            id: lastPhase.id,
            startDate: lastPhase.startDate,
            endDate: yesterdayStr,
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

    final map = updatedProfile.toMap()..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    _db.collection('users').doc(_uid).collection('profile').doc('1').set(map, SetOptions(merge: true));
    _touchSyncMeta(_uid);
  }
}