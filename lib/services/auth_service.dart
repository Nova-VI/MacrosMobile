import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'adaptive_coach_service.dart';
import 'api_key_store.dart';
import 'firestore_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final ValueNotifier<String> userNameNotifier = ValueNotifier('User');
  static final ValueNotifier<bool> onboardingCompletedNotifier = ValueNotifier(true);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
    final user = _auth.currentUser;
    if (user != null) {
      await loadCachedUserData(user.uid);
    }
  }

  Future<void> loadCachedUserData(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedName = prefs.getString('cached_user_name_$uid');
    final cachedOnboarding = prefs.getBool('onboarding_completed_$uid');

    if (cachedName != null && cachedName.isNotEmpty) {
      userNameNotifier.value = cachedName;
    } else if (currentUser?.displayName != null && currentUser!.displayName!.isNotEmpty) {
      userNameNotifier.value = currentUser!.displayName!;
      await prefs.setString('cached_user_name_$uid', currentUser!.displayName!);
    } else {
      userNameNotifier.value = currentUser?.email?.split('@').first ?? 'User';
    }

    if (cachedOnboarding != null) {
      onboardingCompletedNotifier.value = cachedOnboarding;
    }
  }

  Future<void> updateDisplayName(String newName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) return;

    userNameNotifier.value = trimmedName;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_user_name_${user.uid}', trimmedName);

    _syncDisplayNameToRemote(user, trimmedName);
  }

  void _syncDisplayNameToRemote(User user, String newName) async {
    try {
      _db.collection('users').doc(user.uid).set({
        'displayName': newName,
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      await user.updateDisplayName(newName).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    final user = _auth.currentUser;
    if (user == null) return;

    onboardingCompletedNotifier.value = completed;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed_${user.uid}', completed);

    _db.collection('users').doc(user.uid).set({
      'onboarding_completed': completed,
      'onboarding_completed_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<bool> checkIsOnboardingCompleted(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool('onboarding_completed_$uid');
    if (cached != null) {
      onboardingCompletedNotifier.value = cached;
      return cached;
    }

    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['onboarding_completed'] == true) {
          await prefs.setBool('onboarding_completed_$uid', true);
          onboardingCompletedNotifier.value = true;
          return true;
        }
      }

      final profileDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('1')
          .get(const GetOptions(source: Source.serverAndCache));

      if (profileDoc.exists && profileDoc.data() != null) {
        await setOnboardingCompleted(true);
        return true;
      }
    } catch (_) {}

    onboardingCompletedNotifier.value = false;
    return false;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _syncUserRecord(credential.user);
    if (credential.user != null) {
      await loadCachedUserData(credential.user!.uid);
      FirestoreService().initializeListeners(credential.user!.uid);
    }
    return credential;
  }

  Future<UserCredential> registerWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _syncUserRecord(credential.user);
    if (credential.user != null) {
      await loadCachedUserData(credential.user!.uid);
      FirestoreService().initializeListeners(credential.user!.uid);
    }
    return credential;
  }

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    _syncUserRecord(userCredential.user);
    if (userCredential.user != null) {
      await loadCachedUserData(userCredential.user!.uid);
      FirestoreService().initializeListeners(userCredential.user!.uid);
    }
    return userCredential;
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_user_photo_${user.uid}');
    }

    FirestoreService().cancelListeners();
    AdaptiveCoachService().resetState(); // Clear all coach in-memory variables

    userNameNotifier.value = 'User';
    onboardingCompletedNotifier.value = false;

    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  void _syncUserRecord(User? user) async {
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();

    final cachedName = prefs.getString('cached_user_name_${user.uid}');
    String name;
    if (cachedName != null && cachedName.isNotEmpty) {
      name = cachedName;
    } else if (user.displayName != null && user.displayName!.isNotEmpty) {
      name = user.displayName!;
      await prefs.setString('cached_user_name_${user.uid}', name);
    } else {
      name = user.email?.split('@').first ?? 'User';
    }
    userNameNotifier.value = name;

    String photo = user.photoURL ?? '';
    final cachedPhoto = prefs.getString('cached_user_photo_${user.uid}');
    if (photo.isEmpty && cachedPhoto != null) {
      photo = cachedPhoto;
    } else if (photo.isNotEmpty) {
      await prefs.setString('cached_user_photo_${user.uid}', photo);
    }

    final userRef = _db.collection('users').doc(user.uid);
    userRef.set({
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': name,
      'photoURL': photo,
      'last_login': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    // Cache API Keys scoped to UID
    try {
      final settingsDoc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('config')
          .get(const GetOptions(source: Source.serverAndCache));

      if (settingsDoc.exists && settingsDoc.data() != null) {
        final data = settingsDoc.data()!;
        if (data['usda_api_key'] != null) {
          await ApiKeyStore.write(user.uid, 'usda', data['usda_api_key'].toString());
        }
        if (data['gemini_api_key'] != null) {
          await ApiKeyStore.write(user.uid, 'gemini', data['gemini_api_key'].toString());
        }
        if (data['usda_include_branded'] != null) {
          await prefs.setBool('usda_include_branded_${user.uid}', data['usda_include_branded'] == true);
        }
      }
    } catch (_) {}
  }
}
