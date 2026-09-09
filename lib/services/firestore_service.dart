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

      // Automatically backfill goal history for older accounts using the earliest log
      _checkAndBackfillGoalHistory(uid, profileNotifier.value, logs);
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

        // Check if backfill is needed when profile updates
        _checkAndBackfillGoalHistory(uid, profile, logsNotifier.value);
      }
    });
    _subscriptions.add(profileSub);
  }

  /// Automatically backfills goal history for older accounts starting at their earliest log date
 void _checkAndBackfillGoalHistory(String uid, UserProfile profile, List<DailyLog> logs) async {
    if (profile.goalHistory.isEmpty && logs.isNotEmpty) {
      final validDates = logs.map((l) => l.date).where((d) => d.isNotEmpty).toList()..sort();
      if (validDates.isNotEmpty) {
        final earliestDate = validDates.first;

        // Uses your account's exact configured goals without any assumptions
        final initialEntry = GoalHistoryEntry(
          date: earliestDate,
          targetCalories: profile.targetCalories,
          targetProteinG: profile.targetProteinG,
          targetCarbsG: profile.targetCarbsG,
          targetFatG: profile.targetFatG,
          goal: profile.goal,
        );

        final updatedProfile = UserProfile(
          id: profile.id,
          goalMode: profile.goalMode,
          targetCalories: profile.targetCalories,
          targetProteinG: profile.targetProteinG,
          targetCarbsG: profile.targetCarbsG,
          targetFatG: profile.targetFatG,
          age: profile.age,
          gender: profile.gender,
          height: profile.height,
          weight: profile.weight,
          activity: profile.activity,
          goal: profile.goal,
          proteinMultiplier: profile.proteinMultiplier,
          goalHistory: [initialEntry],
        );

        profileNotifier.value = updatedProfile;

        // Persist to Firestore
        _db.collection('users').doc(uid).collection('profile').doc('1').set(
          updatedProfile.toMap(),
          SetOptions(merge: true),
        );
      }
    }
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

  Future<String> addLog(DailyLog log) async {
    final ref = _db.collection('users').doc(_uid).collection('logs').doc();
    ref.set(log.toMap());
    return ref.id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    _db.collection('users').doc(_uid).collection('logs').doc(id).update(changes);
  }

  Future<void> deleteLog(String id) async {
    _db.collection('users').doc(_uid).collection('logs').doc(id).delete();
  }

  Future<String> addFood(FoodItem food) async {
    final ref = _db.collection('users').doc(_uid).collection('foods').doc();
    ref.set(food.toMap());
    return ref.id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    _db.collection('users').doc(_uid).collection('foods').doc(id).update(changes);
  }

  Future<void> deleteFood(String id) async {
    _db.collection('users').doc(_uid).collection('foods').doc(id).delete();
  }

  Future<void> setWeightLog(WeightLog log) async {
    _db.collection('users').doc(_uid).collection('weight_logs').doc(log.date).set(
      log.toMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWeightLog(String date) async {
    _db.collection('users').doc(_uid).collection('weight_logs').doc(date).delete();
  }

  Future<void> saveProfile(UserProfile profile) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentHistory = List<GoalHistoryEntry>.from(profileNotifier.value.goalHistory);

    currentHistory.removeWhere((e) => e.date == todayStr);
    currentHistory.add(
      GoalHistoryEntry(
        date: todayStr,
        targetCalories: profile.targetCalories,
        targetProteinG: profile.targetProteinG,
        targetCarbsG: profile.targetCarbsG,
        targetFatG: profile.targetFatG,
        goal: profile.goal,
      ),
    );

    final updatedProfile = UserProfile(
      id: profile.id,
      goalMode: profile.goalMode,
      targetCalories: profile.targetCalories,
      targetProteinG: profile.targetProteinG,
      targetCarbsG: profile.targetCarbsG,
      targetFatG: profile.targetFatG,
      age: profile.age,
      gender: profile.gender,
      height: profile.height,
      weight: profile.weight,
      activity: profile.activity,
      goal: profile.goal,
      proteinMultiplier: profile.proteinMultiplier,
      goalHistory: currentHistory,
    );

    _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      updatedProfile.toMap(),
      SetOptions(merge: true),
    );
  }
}