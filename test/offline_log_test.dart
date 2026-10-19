// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/food_item.dart';
import 'package:macro_tracker_mobile/models/nutrition.dart';
import 'package:macro_tracker_mobile/screens/log_food_screen.dart';
import 'package:macro_tracker_mobile/screens/main_navigation_screen.dart';
import 'package:macro_tracker_mobile/screens/weight_tracker_screen.dart';
import 'package:macro_tracker_mobile/services/firestore_service.dart';
import 'package:macro_tracker_mobile/services/auth_service.dart';
import 'package:macro_tracker_mobile/services/api_key_store.dart';
import 'package:macro_tracker_mobile/models/weight_log.dart';
import 'package:macro_tracker_mobile/models/user_profile.dart';
import 'package:macro_tracker_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends FirebaseAuthPlatform {
  String uid = 'offline-test';
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({InternalUserDetails? currentUser, String? languageCode}) => this;
  @override
  UserPlatform get currentUser => _User(this);
  @override
  Stream<UserPlatform?> authStateChanges() => const Stream.empty();
}

class _Factors extends MultiFactorPlatform {
  _Factors(super.auth);
}

class _User extends UserPlatform {
  _User(_Auth auth) : super(auth, _Factors(auth), InternalUserDetails(
    userInfo: InternalUserInfo(uid: auth.uid, isAnonymous: false, isEmailVerified: false),
    providerData: [],
  ));
}

class _Firestore extends FirebaseFirestorePlatform {
  final writes = <Completer<void>>[];
  final batches = <_Batch>[];
  @override
  WriteBatchPlatform batch() {
    final batch = _Batch(this);
    batches.add(batch);
    return batch;
  }
  @override
  FirebaseFirestorePlatform delegateFor({required FirebaseApp app, required String databaseId}) => this;
  @override
  DocumentReferencePlatform doc(String path) => _Document(this, path);
  @override
  CollectionReferencePlatform collection(String path) => _Collection(this, path);
}

class _Batch extends WriteBatchPlatform {
  _Batch(this.firestore);
  final _Firestore firestore;
  final sets = <String, Map<String, dynamic>>{};
  final updates = <String, Map<FieldPath, dynamic>>{};
  @override
  void set(String documentPath, Map<String, dynamic> data, [SetOptions? options]) {
    expect(options?.merge, isTrue, reason: 'Offline batches must merge individual dates');
    sets[documentPath] = data;
  }
  @override
  void update(String documentPath, Map<FieldPath, dynamic> data) => updates[documentPath] = data;
  @override
  Future<void> commit() {
    final write = Completer<void>();
    firestore.writes.add(write);
    return write.future;
  }
}

class _Collection extends CollectionReferencePlatform {
  _Collection(super.firestore, super.path);
  @override
  DocumentReferencePlatform doc([String? path]) => _Document(firestore as _Firestore, '${this.path}/$path');
  // A server read can also stay pending offline. It must not block saving.
  @override
  Future<QuerySnapshotPlatform> get([GetOptions options = const GetOptions()]) {
    if (options.source == Source.cache) {
      return Future.value(QuerySnapshotPlatform([], [], SnapshotMetadataPlatform(false, true)));
    }
    return Completer<QuerySnapshotPlatform>().future;
  }
  @override
  Stream<QuerySnapshotPlatform> snapshots({bool includeMetadataChanges = false, required ListenSource listenSource}) => const Stream.empty();
}

class _Document extends DocumentReferencePlatform {
  _Document(_Firestore super.firestore, super.path);
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) {
    final write = Completer<void>();
    (firestore as _Firestore).writes.add(write);
    return write.future;
  }
  @override
  Stream<DocumentSnapshotPlatform> snapshots({bool includeMetadataChanges = false, required ListenSource listenSource}) => const Stream.empty();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final firestore = _Firestore();
  final auth = _Auth();
  final secure = <String, String>{};
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = auth;
    FirebaseFirestorePlatform.instance = firestore;
  });
  setUp(() async {
    firestore.writes.clear();
    firestore.batches.clear();
    secure.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String;
        if (call.method == 'write') secure[key] = args['value'] as String;
        if (call.method == 'delete') secure.remove(key);
        return call.method == 'read' ? secure[key] : null;
      });
    await ThemeManager.activate(auth.uid);
    FirestoreService().cancelListeners();
  });
  tearDown(() {
    for (final write in firestore.writes) {
      if (!write.isCompleted) write.complete();
    }
  });

  testWidgets('offline food log resets the form and updates totals without server acknowledgement', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: LogFoodScreen(onLogCompleted: () {})));
    await tester.enterText(_field('Food Name'), 'Offline meal');
    await tester.enterText(_field('Calories (kcal)'), '200');
    await tester.tap(find.text('Save to food library for future logs'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log Food'));
    await tester.pump();
    await tester.pump();
    expect(firestore.writes, hasLength(2));
    expect(firestore.writes.every((write) => !write.isCompleted), isTrue);
    expect(FirestoreService().logsNotifier.value.single.macros.calories, 200);
    expect(FirestoreService().foodsNotifier.value.single.name, 'Offline meal');
    expect(tester.widget<TextField>(_field('Food Name')).controller!.text, isEmpty);
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('server rejection is reported later while unrelated account errors are ignored', () async {
    final service = FirestoreService();
    final food = FoodItem(id: 'food_test', name: 'Test', macros: const MacroNutrients(), micros: const MicroNutrients());
    await service.addFood(food).timeout(const Duration(seconds: 1));
    firestore.writes.last.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await Future<void>.delayed(Duration.zero);
    expect(service.syncErrorNotifier.value, 'Sync failed. Please retry.');
    service.syncErrorNotifier.value = null;
    await service.addFood(food);
    auth.uid = 'other-account';
    firestore.writes.last.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await Future<void>.delayed(Duration.zero);
    expect(service.syncErrorNotifier.value, isNull);
    auth.uid = 'offline-test';
  });

  test('weight saves, backdated edits and deletes finish without a server read', () async {
    final service = FirestoreService();
    await service.setWeightLog(WeightLog(date: '2026-10-18', weightKg: 70)).timeout(const Duration(seconds: 1));
    await service.setWeightLog(WeightLog(date: '2026-10-20', weightKg: 71));
    await service.setWeightLog(WeightLog(date: '2026-10-18', weightKg: 69));
    expect(service.weightLogsNotifier.value.map((weight) => weight.weightKg), [69, 71]);
    expect(service.profileNotifier.value.weight, 71);
    expect(firestore.batches.last.sets['users/offline-test/weight_logs/all'], {'entries': {'2026-10-18': 69.0}});
    await service.deleteWeightLog('2026-10-20');
    expect(service.weightLogsNotifier.value.single.weightKg, 69);
    expect(service.profileNotifier.value.weight, 69);
    expect(firestore.batches.last.updates['users/offline-test/weight_logs/all']!.keys.single, FieldPath(['entries', '2026-10-20']));
    expect(firestore.writes.every((write) => !write.isCompleted), isTrue);
  });

  testWidgets('offline weight save clears the form and shows a compact Saved toast', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: WeightTrackerScreen()));
    await tester.enterText(_field('Body Weight'), '72.5');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(FirestoreService().weightLogsNotifier.value.single.weightKg, 72.5);
    expect(tester.widget<TextField>(_field('Body Weight')).controller!.text, isEmpty);
    expect(firestore.writes.single.isCompleted, isFalse);
    final toast = tester.widget<SnackBar>(find.byType(SnackBar));
    expect((toast.content as Text).data, 'Saved');
    expect((toast.content as Text).maxLines, 1);
    expect(toast.duration, const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  test('history loads from cache without waiting for an unavailable server', () async {
    final service = FirestoreService();
    service.initializeListeners(auth.uid);
    await service.ensureAllMonthsLoaded().timeout(const Duration(seconds: 1));
    service.cancelListeners();
  });

  test('API keys, colors, profile, name and onboarding save locally while writes remain pending', () async {
    final service = FirestoreService();
    await service.saveSettings({'usda_api_key': 'test-usda', 'gemini_api_key': 'test-gemini', 'usda_include_branded': true});
    expect(await ApiKeyStore.read(auth.uid, 'usda'), 'test-usda');
    expect(await ApiKeyStore.read(auth.uid, 'gemini'), 'test-gemini');
    expect(service.settingsNotifier.value['usda_include_branded'], isTrue);
    await ThemeManager.setAccent(const Color(0xFF123456));
    expect(AppColors.primary, const Color(0xFF123456));
    await service.saveProfile(UserProfile(targetCalories: 2200));
    expect(service.profileNotifier.value.targetCalories, 2200);
    await AuthService().updateDisplayName('Offline name');
    expect(AuthService.userNameNotifier.value, 'Offline name');
    await AuthService().setOnboardingCompleted(true);
    expect(AuthService.onboardingCompletedNotifier.value, isTrue);
    expect(firestore.writes.every((write) => !write.isCompleted), isTrue);
  });

  testWidgets('navigation buttons stay above Android three-button and gesture insets', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final inset in [48.0, 24.0, 0.0]) {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: inset),
            viewPadding: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        ),
        home: const MainNavigationScreen(),
      ));
      await tester.pump();
      final bottom = tester.getBottomRight(find.byTooltip('Home')).dy;
      expect(bottom, lessThanOrEqualTo(1400 - inset - 20));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
