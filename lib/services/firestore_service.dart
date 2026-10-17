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

  bool _allMonthsLoadedThisSession = false;
  String? _listeningUid;
  int _listenerGeneration = 0;

  bool _isActiveSession(String uid, int generation) =>
      _listeningUid == uid && _listenerGeneration == generation && currentUid == uid;

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
    final uid = _uid;
    final generation = _listenerGeneration;
    final listenerKey = 'month_$monthKey';
    if (_subscriptions.containsKey(listenerKey)) return;

    final docRef = _db.collection('users').doc(uid).collection('logs').doc(monthKey);
    final sub = docRef.snapshots().listen((snap) {
      if (!_isActiveSession(uid, generation)) return;
      if (snap.exists && snap.data() != null) {
        _monthCache[monthKey] = snap.data()!;
        _rebuildFlatLogs();
      }
    });

    _subscriptions[listenerKey] = sub;
  }

  Future<void> ensureAllMonthsLoaded() async {
    if (currentUid == null) return;
    if (_allMonthsLoadedThisSession) return;
    final uid = _uid;
    final generation = _listenerGeneration;
    try {
      final snap = await _db.collection('users').doc(uid).collection('logs').get();
      if (!_isActiveSession(uid, generation)) return;
      for (final doc in snap.docs) {
        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(doc.id)) {
          _monthCache[doc.id] = doc.data();
          ensureMonthSubscribed(doc.id);
        }
      }
      _allMonthsLoadedThisSession = true;
      _rebuildFlatLogs();
    } catch (_) {}
  }

  // --- Initial Device Hydration ---
  Future<void> _hydrateNewDevice(String uid) async {
    final generation = _listenerGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!_isActiveSession(uid, generation)) return;
    final hydrationKey = 'hydrated_v6_$uid';
    final alreadyHydrated = prefs.getBool(hydrationKey) ?? false;

    if (!alreadyHydrated) {
      try {
        final logsSnap = await _db.collection('users').doc(uid).collection('logs').get();
        final weightSnap = await _db.collection('users').doc(uid).collection('weight_logs').doc('all').get();
        final foodSnap = await _db.collection('users').doc(uid).collection('foods').doc('library').get();
        if (!_isActiveSession(uid, generation)) return;

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
        if (!_isActiveSession(uid, generation)) return;
        _rebuildFlatLogs();
        _rebuildFlatWeights();
        _rebuildFlatFoods();
      } catch (_) {}
    }
  }

  // --- Realtime Listeners Initialization (Total: 7 Listeners) ---
  void initializeListeners(String uid) {
    cancelListeners();
    _listeningUid = uid;
    final generation = _listenerGeneration;

    _hydrateNewDevice(uid);

    // 1. User Account Stream
    final userSub = _db.collection('users').doc(uid).snapshots().listen((doc) async {
      if (!_isActiveSession(uid, generation)) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final remoteName = data['displayName']?.toString() ?? '';
        final remoteCompleted = data['onboarding_completed'] == true;

        final prefs = await SharedPreferences.getInstance();
        if (!_isActiveSession(uid, generation)) return;
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
      if (!_isActiveSession(uid, generation)) return;
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
      if (!_isActiveSession(uid, generation)) return;
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
      if (!_isActiveSession(uid, generation)) return;
      if (doc.exists && doc.data() != null) {
        profileNotifier.value = UserProfile.fromFirestore(doc.data());
        AdaptiveCoachService().recomputeAndEvaluate();
      }
    });
    _subscriptions['profile'] = profileSub;

    // 7. Settings & Config Stream (Syncs cross-device dismissal & API keys in real time)
    final settingsSub = _db.collection('users').doc(uid).collection('settings').doc('config').snapshots().listen((snap) {
      if (!_isActiveSession(uid, generation)) return;
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final remoteDismissedDate = data['dismissed_checkin_date']?.toString();

        SharedPreferences.getInstance().then((prefs) {
          if (!_isActiveSession(uid, generation)) return;
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
    _listenerGeneration++;
    _listeningUid = null;
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();

    _monthCache.clear();
    _weightCache.clear();
    _foodCache.clear();
    _allMonthsLoadedThisSession = false;

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
    final uid = _uid;
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

    await _db.collection('users').doc(uid).collection('logs').doc(monthKey).set({
      'month': monthKey,
      'items': {id: resolvedLog.toMap()},
    }, SetOptions(merge: true));
    if (currentUid != uid) return id;

    if (!_monthCache.containsKey(monthKey)) {
      _monthCache[monthKey] = {'month': monthKey, 'items': <String, dynamic>{}};
    }
    if (_monthCache[monthKey]!['items'] is! Map) {
      _monthCache[monthKey]!['items'] = <String, dynamic>{};
    }
    final itemsMap = _monthCache[monthKey]!['items'] as Map<String, dynamic>;
    itemsMap[id] = resolvedLog.toMap();

    _rebuildFlatLogs();

    return id;
  }

  Future<void> updateLog(String id, Map<String, dynamic> changes) async {
    final uid = _uid;
    String? foundMonthKey;
    Map<String, dynamic>? updatedMap;

    for (final entry in _monthCache.entries) {
      final itemsMap = entry.value['items'];
      if (itemsMap is Map && itemsMap.containsKey(id)) {
        foundMonthKey = entry.key;
        final existing = Map<String, dynamic>.from(itemsMap[id] as Map);
        existing.addAll(changes);
        existing['id'] = id;
        updatedMap = existing;
        break;
      }
    }

    if (foundMonthKey != null && updatedMap != null) {
      final newDate = updatedMap['date']?.toString() ?? '';
      final newMonthKey = newDate.length >= 7 ? newDate.substring(0, 7) : foundMonthKey;

      if (newMonthKey != foundMonthKey) {
        final batch = _db.batch();
        final oldRef = _db.collection('users').doc(uid).collection('logs').doc(foundMonthKey);
        final newRef = _db.collection('users').doc(uid).collection('logs').doc(newMonthKey);
        batch.update(oldRef, {FieldPath(['items', id]): FieldValue.delete()});
        batch.set(newRef, {'month': newMonthKey, 'items': {id: updatedMap}}, SetOptions(merge: true));
        await batch.commit();
        if (currentUid != uid) return;
        (_monthCache[foundMonthKey]?['items'] as Map?)?.remove(id);

        if (!_monthCache.containsKey(newMonthKey)) {
          _monthCache[newMonthKey] = {'month': newMonthKey, 'items': <String, dynamic>{}};
        }
        (_monthCache[newMonthKey]!['items'] as Map<String, dynamic>)[id] = updatedMap;

        _rebuildFlatLogs();

      } else {
        await _db.collection('users').doc(uid).collection('logs').doc(foundMonthKey).set({
          'items': {id: updatedMap},
        }, SetOptions(merge: true));
        if (currentUid != uid) return;
        (_monthCache[foundMonthKey]?['items'] as Map)[id] = updatedMap;
        _rebuildFlatLogs();
      }
    } else {
      throw StateError('Log $id was not found in the loaded months.');
    }
  }

  Future<void> deleteLog(String id, {String? date}) async {
    final uid = _uid;
    String? foundMonthKey;
    String targetKey = id;

    if (date != null && date.length >= 7) {
      foundMonthKey = date.substring(0, 7);
      final monthData = _monthCache[foundMonthKey];
      final itemsMap = monthData?['items'];
      if (itemsMap is Map) {
        if (itemsMap.containsKey(id)) {
          targetKey = id;
        } else {
          final matchedKey = itemsMap.keys.firstWhere(
            (k) => itemsMap[k] is Map && itemsMap[k]['id'] == id,
            orElse: () => null,
          );
          if (matchedKey != null) {
            targetKey = matchedKey.toString();
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
            break;
          } else {
            final matchedKey = itemsMap.keys.firstWhere(
              (k) => itemsMap[k] is Map && itemsMap[k]['id'] == id,
              orElse: () => null,
            );
            if (matchedKey != null) {
              foundMonthKey = entry.key;
              targetKey = matchedKey.toString();
              break;
            }
          }
        }
      }
    }

    if (foundMonthKey != null) {
      final docRef = _db.collection('users').doc(uid).collection('logs').doc(foundMonthKey);
      await docRef.update({FieldPath(['items', targetKey]): FieldValue.delete()});
      if (currentUid == uid) {
        (_monthCache[foundMonthKey]?['items'] as Map?)?.remove(targetKey);
        _rebuildFlatLogs();
      }
    } else {
      throw StateError('Log $id was not found in the loaded months.');
    }
  }

  // --- CRUD: Weight Tracker ---
  Future<void> setWeightLog(WeightLog log) async {
    final uid = _uid;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid).collection('weight_logs').doc('all'),
        {'entries': {log.date: log.weightKg}}, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(uid).collection('profile').doc('1'),
        {'weight': log.weightKg}, SetOptions(merge: true));
    await batch.commit();
    if (currentUid != uid) return;
    _weightCache[log.date] = log.weightKg;
    _rebuildFlatWeights();
  }

  Future<void> deleteWeightLog(String date) async {
    final uid = _uid;
    await _db.collection('users').doc(uid).collection('weight_logs').doc('all').update({
      FieldPath(['entries', date]): FieldValue.delete(),
    });
    if (currentUid != uid) return;
    _weightCache.remove(date);
    _rebuildFlatWeights();
  }

  // --- CRUD: Food Library ---
  Future<String> addFood(FoodItem food) async {
    final uid = _uid;
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

    await _db.collection('users').doc(uid).collection('foods').doc('library').set({
      'items': {
        id: resolvedFood.toMap(),
      }
    }, SetOptions(merge: true));
    if (currentUid == uid) {
      _foodCache[id] = resolvedFood;
      _rebuildFlatFoods();
    }

    return id;
  }

  Future<void> updateFood(String id, Map<String, dynamic> changes) async {
    final uid = _uid;
    final existing = _foodCache[id];
    if (existing != null) {
      final map = existing.toMap()..addAll(changes);
      final updated = FoodItem.fromFirestore(id, map);
      await _db.collection('users').doc(uid).collection('foods').doc('library').set({
        'items': {
          id: updated.toMap(),
        }
      }, SetOptions(merge: true));
      if (currentUid == uid) {
        _foodCache[id] = updated;
        _rebuildFlatFoods();
      }
    } else {
      throw StateError('Food $id was not found in the library.');
    }
  }

  Future<void> deleteFood(String id) async {
    final uid = _uid;
    await _db.collection('users').doc(uid).collection('foods').doc('library').update({
      FieldPath(['items', id]): FieldValue.delete(),
    });
    if (currentUid == uid) {
      _foodCache.remove(id);
      _rebuildFlatFoods();
    }
  }

  // --- User Profile ---
  Future<void> saveProfile(UserProfile profile) async {
    final uid = _uid;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentProfile = profileNotifier.value;

    final currentPhases = buildGoalPhasesForSave(currentProfile, profile, todayStr);

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

    await _db.collection('users').doc(uid).collection('profile').doc('1').set(
      updatedProfile.toMap(),
      SetOptions(merge: true),
    );
    if (currentUid == uid) profileNotifier.value = updatedProfile;
  }
}
