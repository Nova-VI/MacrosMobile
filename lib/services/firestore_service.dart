import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/food_item.dart';
import '../models/daily_log.dart';
import '../models/weight_log.dart';
import '../models/user_profile.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // In-Memory Live Reactive Stores
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

  // --- Initialize Realtime Listeners on Auth ---
  void initializeListeners(String uid) {
    cancelListeners();

    // 1. Stream all foods into memory
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

    // 2. Stream all logs into memory (Single stream for zero-cost date switches)
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

    // 3. Stream weight logs
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

    // 4. Stream profile
    final profileSub = _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('1')
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        profileNotifier.value = UserProfile.fromFirestore(doc.data());
      }
    });
    _subscriptions.add(profileSub);
  }

  void cancelListeners() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  // --- Fast In-Memory Synchronous Query Helpers (0ms, 0 Network Calls) ---

  List<DailyLog> getLogsForDate(String date) {
    return logsNotifier.value.where((log) => log.date == date).toList();
  }

  List<DailyLog> getLogsForRange(String startDate, String endDate) {
    return logsNotifier.value.where((log) {
      return log.date.compareTo(startDate) >= 0 && log.date.compareTo(endDate) <= 0;
    }).toList();
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

  Future<void> setWeightLog(WeightLog log) async {
    await _db.collection('users').doc(_uid).collection('weight_logs').doc(log.date).set(
      log.toMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWeightLog(String date) async {
    await _db.collection('users').doc(_uid).collection('weight_logs').doc(date).delete();
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      profile.toMap(),
      SetOptions(merge: true),
    );
  }
}