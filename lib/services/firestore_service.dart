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
import 'adaptive_coach_service.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Observable ValueNotifiers for Flutter UI (0ms instant reactivity)
  final ValueNotifier<List<DailyLog>> logsNotifier = ValueNotifier([]);
  final ValueNotifier<List<FoodItem>> foodsNotifier = ValueNotifier([]);
  final ValueNotifier<List<WeightLog>> weightLogsNotifier = ValueNotifier([]);
  final ValueNotifier<UserProfile> profileNotifier = ValueNotifier(UserProfile());

  // In-memory bucket stores
  final Map<String, Map<String, dynamic>> _monthCache = {}; // "YYYY-MM" -> raw month doc data
  final Map<String, double> _weightCache = {};              // "YYYY-MM-DD" -> weight_kg
  final Map<String, FoodItem> _foodCache = {};              // food_id -> FoodItem

  final Map<String, StreamSubscription> _subscriptions = {};

  String? get currentUid => _auth.currentUser?.uid;

  String get _uid {
    final uid = currentUid;
    if (uid == null) throw Exception('No authenticated user found');
    return uid;
  }

  static int compareLogsChronologically(DailyLog a, DailyLog b) {
    DateTime dtA;
    DateTime dtB;
    try {
      dtA = DateTime.parse(a.loggedAt).toLocal();
    } catch (_) {
      dtA = DateTime(1970);
    }
    try {
      dtB = DateTime.parse(b.loggedAt).toLocal();
    } catch (_) {
      dtB = DateTime(1970);
    }
    final cmp = dtA.compareTo(dtB);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  }

  // --- Flattening Helpers for UI Streams ---
  void _rebuildFlatLogs() {
    final List<DailyLog> allLogs = [];

    for (final monthData in _monthCache.values) {
      final rawItems = monthData['items'];
      if (rawItems is Map) {
        rawItems.forEach((key, val) {
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            final id = key.toString();
            final log = DailyLog.fromFirestore(id, map);
            if (log.id.isNotEmpty && log.date.isNotEmpty) {
              allLogs.add(log);
            }
          }
        });
      }
    }

    allLogs.sort(compareLogsChronologically);
    logsNotifier.value = allLogs;
    AdaptiveCoachService().recomputeAndEvaluate();
  }

  void _rebuildFlatWeights() {
    final List<WeightLog> allWeights = _weightCache.entries.map((e) {
      return WeightLog(date: e.key, weightKg: e.value);
    }).toList();
    allWeights.sort((a, b) => a.date.compareTo(b.date));
    weightLogsNotifier.value = allWeights;
    AdaptiveCoachService().recomputeAndEvaluate();
  }

  void _rebuildFlatFoods() {
    foodsNotifier.value = _foodCache.values.toList();
  }

  // --- Dynamic On-Demand Subscriptions ---
  void ensureMonthSubscribed(String monthKey) {
    if (currentUid == null || monthKey.isEmpty) return;
    final listenerKey = 'month_$monthKey';
    if (_subscriptions.containsKey(listenerKey)) return;

    final docRef = _db.collection('users').doc(_uid).collection('logs').doc(monthKey);
    final sub = docRef.snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        _monthCache[monthKey] = snap.data()!;
        _rebuildFlatLogs();
      }
    });

    _subscriptions[listenerKey] = sub;
  }

  Future<void> ensureAllMonthsLoaded() async {
    if (currentUid == null) return;
    try {
      final snap = await _db.collection('users').doc(_uid).collection('logs').get();
      for (final doc in snap.docs) {
        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(doc.id)) {
          _monthCache[doc.id] = doc.data();
          ensureMonthSubscribed(doc.id);
        }
      }
      _rebuildFlatLogs();
    } catch (_) {}
  }

  // --- Initial Device Hydration ---
  Future<void> _hydrateNewDevice(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final hydrationKey = 'hydrated_v6_$uid';
    final alreadyHydrated = prefs.getBool(hydrationKey) ?? false;

    if (!alreadyHydrated) {
      try {
        final logsSnap = await _db.collection('users').doc(uid).collection('logs').get();
        final weightSnap = await _db.collection('users').doc(uid).collection('weight_logs').doc('all').get();
        final foodSnap = await _db.collection('users').doc(uid).collection('foods').doc('library').get();

        for (final doc in logsSnap.docs) {
          if (RegExp(r'^\d{4}-\d{2}$').hasMatch(doc.id)) {
            _monthCache[doc.id] = doc.data();
          }
        }

        if (weightSnap.exists && weightSnap.data() != null) {
          final entries = weightSnap.data()!['entries'] as Map<String, dynamic>? ?? {};
          entries.forEach((date, weight) {
            final w = (weight as num?)?.toDouble();
            if (w != null) _weightCache[date] = w;
          });
        }

        if (foodSnap.exists && foodSnap.data() != null) {
          final items = foodSnap.data()!['items'] as Map<String, dynamic>? ?? {};
          items.forEach((id, rawFood) {
            if (rawFood is Map) {
              _foodCache[id] = FoodItem.fromFirestore(id, Map<String, dynamic>.from(rawFood));
            }
          });
        }

        await prefs.setBool(hydrationKey, true);
        _rebuildFlatLogs();
        _rebuildFlatWeights();
        _rebuildFlatFoods();
      } catch (_) {}
    }
  }

  // --- Realtime Listeners Initialization (Total: 7 Listeners) ---
  void initializeListeners(String uid) {
    cancelListeners();

    _hydrateNewDevice(uid);

    // 1. User Account Stream
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
    _subscriptions['user'] = userSub;

    // 2 & 3. Active 2-Month Stream (Current + Previous Month)
    final now = DateTime.now();
    final currentMonthKey = DateFormat('yyyy-MM').format(now);
    final prevMonthDate = DateTime(now.year, now.month - 1, 1);
    final prevMonthKey = DateFormat('yyyy-MM').format(prevMonthDate);

    ensureMonthSubscribed(currentMonthKey);
    ensureMonthSubscribed(prevMonthKey);

    // 4. Lifetime Weight Stream
    final weightSub = _db.collection('users').doc(uid).collection('weight_logs').doc('all').snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final entries = snap.data()!['entries'] as Map<String, dynamic>? ?? {};
        _weightCache.clear();
        entries.forEach((date, weight) {
          final w = (weight as num?)?.toDouble();
          if (w != null) _weightCache[date] = w;
        });
        _rebuildFlatWeights();
      }
    });
    _subscriptions['weights'] = weightSub;

    // 5. Food & Recipe Library Stream
    final foodSub = _db.collection('users').doc(uid).collection('foods').doc('library').snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final items = snap.data()!['items'] as Map<String, dynamic>? ?? {};
        _foodCache.clear();
        items.forEach((id, rawFood) {
          if (rawFood is Map) {
            _foodCache[id] = FoodItem.fromFirestore(id, Map<String, dynamic>.from(rawFood));
          }
        });
        _rebuildFlatFoods();
      }
    });
    _subscriptions['foods'] = foodSub;

    // 6. User Profile Stream
    final profileSub = _db.collection('users').doc(uid).collection('profile').doc('1').snapshots().listen((doc) {
      if (doc.exists && doc.data() != null) {
        profileNotifier.value = UserProfile.fromFirestore(doc.data());
        AdaptiveCoachService().recomputeAndEvaluate();
      }
    });
    _subscriptions['profile'] = profileSub;

    // 7. Settings & Config Stream (Syncs cross-device dismissal & API keys in real time)
    final settingsSub = _db.collection('users').doc(uid).collection('settings').doc('config').snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final remoteDismissedDate = data['dismissed_checkin_date']?.toString();
        
        SharedPreferences.getInstance().then((prefs) {
          if (remoteDismissedDate != null && remoteDismissedDate.isNotEmpty) {
            prefs.setString('dismissed_checkin_date_$uid', remoteDismissedDate);
          } else {
            prefs.remove('dismissed_checkin_date_$uid');
          }
          AdaptiveCoachService().recomputeAndEvaluate();
        });
      }
    });
    _subscriptions['settings'] = settingsSub;
  }

  void cancelListeners() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();

    _monthCache.clear();
    _weightCache.clear();
    _foodCache.clear();

    logsNotifier.value = [];
    foodsNotifier.value = [];
    weightLogsNotifier.value = [];
    profileNotifier.value = UserProfile();
  }

  List<DailyLog> getLogsForDate(String date) {
    final monthKey = date.length >= 7 ? date.substring(0, 7) : '';
    if (monthKey.isNotEmpty) ensureMonthSubscribed(monthKey);
    final list = logsNotifier.value.where((log) => log.date == date).toList();
    list.sort(compareLogsChronologically);
    return list;
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

  // --- CRUD: Food Logs (Conflict-Free Map Entries under items.<logId>) ---
  Future<String> addLog(DailyLog log) async {
    final String id = log.id.isNotEmpty
        ? log.id
        : 'log_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';

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

    final monthKey = log.date.substring(0, 7);

    if (!_monthCache.containsKey(monthKey)) {
      _monthCache[monthKey] = {'month': monthKey, 'items': <String, dynamic>{}};
    }
    if (_monthCache[monthKey]!['items'] is! Map) {
      _monthCache[monthKey]!['items'] = <String, dynamic>{};
    }
    final itemsMap = _monthCache[monthKey]!['items'] as Map<String, dynamic>;
    itemsMap[id] = resolvedLog.toMap();

    _rebuildFlatLogs();

    _db.collection('users').doc(_uid).collection('logs').doc(monthKey).set({
      'month': monthKey,
      'items': {
        id: resolvedLog.toMap(),
      },
    }, SetOptions(merge: true));

    return id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    String? foundMonthKey;
    Map<String, dynamic>? updatedMap;

    for (final entry in _monthCache.entries) {
      final itemsMap = entry.value['items'];
      if (itemsMap is Map && itemsMap.containsKey(id)) {
        foundMonthKey = entry.key;
        final existing = Map<String, dynamic>.from(itemsMap[id] as Map);
        existing.addAll(changes);
        existing['id'] = id;
        itemsMap[id] = existing;
        updatedMap = existing;
        break;
      }
    }

    if (foundMonthKey != null && updatedMap != null) {
      _rebuildFlatLogs();

      _db.collection('users').doc(_uid).collection('logs').doc(foundMonthKey).set({
        'items': {
          id: updatedMap,
        },
      }, SetOptions(merge: true));
    }
  }

  Future<void> deleteLog(String id, {String? date}) async {
    String? foundMonthKey;
    String targetKey = id;

    if (date != null && date.length >= 7) {
      foundMonthKey = date.substring(0, 7);
      final monthData = _monthCache[foundMonthKey];
      final itemsMap = monthData?['items'];
      if (itemsMap is Map) {
        if (itemsMap.containsKey(id)) {
          targetKey = id;
          itemsMap.remove(id);
        } else {
          final matchedKey = itemsMap.keys.firstWhere(
            (k) => itemsMap[k] is Map && itemsMap[k]['id'] == id,
            orElse: () => null,
          );
          if (matchedKey != null) {
            targetKey = matchedKey.toString();
            itemsMap.remove(matchedKey);
          }
        }
      }
    }

    if (foundMonthKey == null || !_monthCache.containsKey(foundMonthKey)) {
      for (final entry in _monthCache.entries) {
        final itemsMap = entry.value['items'];
        if (itemsMap is Map) {
          if (itemsMap.containsKey(id)) {
            foundMonthKey = entry.key;
            targetKey = id;
            itemsMap.remove(id);
            break;
          } else {
            final matchedKey = itemsMap.keys.firstWhere(
              (k) => itemsMap[k] is Map && itemsMap[k]['id'] == id,
              orElse: () => null,
            );
            if (matchedKey != null) {
              foundMonthKey = entry.key;
              targetKey = matchedKey.toString();
              itemsMap.remove(matchedKey);
              break;
            }
          }
        }
      }
    }

    _rebuildFlatLogs();

    if (foundMonthKey != null) {
      final docRef = _db.collection('users').doc(_uid).collection('logs').doc(foundMonthKey);

      try {
        await docRef.update({
          FieldPath(['items', targetKey]): FieldValue.delete(),
        });
      } catch (_) {
        try {
          final snap = await docRef.get();
          if (snap.exists && snap.data() != null) {
            final items = Map<String, dynamic>.from(snap.data()!['items'] as Map? ?? {});
            items.remove(targetKey);
            items.remove(id);
            await docRef.set({'items': items}, SetOptions(merge: true));
          }
        } catch (e) {
          debugPrint('[FirestoreService] Delete failed: $e');
        }
      }
    }
  }

  // --- CRUD: Weight Tracker ---
  Future<void> setWeightLog(WeightLog log) async {
    _weightCache[log.date] = log.weightKg;
    _rebuildFlatWeights();

    _db.collection('users').doc(_uid).collection('weight_logs').doc('all').set({
      'entries': {
        log.date: log.weightKg,
      }
    }, SetOptions(merge: true));

    _db.collection('users').doc(_uid).collection('profile').doc('1').set({
      'weight': log.weightKg,
    }, SetOptions(merge: true));
  }

  Future<void> deleteWeightLog(String date) async {
    _weightCache.remove(date);
    _rebuildFlatWeights();

    _db.collection('users').doc(_uid).collection('weight_logs').doc('all').update({
      'entries.$date': FieldValue.delete(),
    });
  }

  // --- CRUD: Food Library ---
  Future<String> addFood(FoodItem food) async {
    final String id = food.id.isNotEmpty ? food.id : 'food_${DateTime.now().millisecondsSinceEpoch}';
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

    _foodCache[id] = resolvedFood;
    _rebuildFlatFoods();

    _db.collection('users').doc(_uid).collection('foods').doc('library').set({
      'items': {
        id: resolvedFood.toMap(),
      }
    }, SetOptions(merge: true));

    return id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    final existing = _foodCache[id];
    if (existing != null) {
      final map = existing.toMap()..addAll(changes);
      final updated = FoodItem.fromFirestore(id, map);
      _foodCache[id] = updated;
      _rebuildFlatFoods();

      _db.collection('users').doc(_uid).collection('foods').doc('library').set({
        'items': {
          id: updated.toMap(),
        }
      }, SetOptions(merge: true));
    }
  }

  Future<void> deleteFood(String id) async {
    _foodCache.remove(id);
    _rebuildFlatFoods();

    _db.collection('users').doc(_uid).collection('foods').doc('library').update({
      'items.$id': FieldValue.delete(),
    });
  }

  // --- User Profile ---
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

    _db.collection('users').doc(_uid).collection('profile').doc('1').set(
      updatedProfile.toMap(),
      SetOptions(merge: true),
    );
  }
}