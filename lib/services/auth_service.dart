import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _syncUserRecord(credential.user);
    if (credential.user != null) {
      FirestoreService().initializeListeners(credential.user!.uid);
    }
    return credential;
  }

  Future<UserCredential> registerWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _syncUserRecord(credential.user);
    if (credential.user != null) {
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
    await _syncUserRecord(userCredential.user);
    if (userCredential.user != null) {
      FirestoreService().initializeListeners(userCredential.user!.uid);
    }
    return userCredential;
  }

  Future<void> signOut() async {
    FirestoreService().cancelListeners();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<void> _syncUserRecord(User? user) async {
    if (user == null) return;
    final userRef = _db.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    String photo = user.photoURL ?? '';
    if (userDoc.exists &&
        userDoc.data()?['photoURL'] != null &&
        userDoc.data()!['photoURL'].toString().isNotEmpty) {
      photo = userDoc.data()!['photoURL'];
    }

    await userRef.set({
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': user.displayName ?? (user.email?.split('@').first ?? 'User'),
      'photoURL': photo,
      'last_login': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    // Synchronize API Keys from Cloud
    try {
      final settingsDoc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('config')
          .get();

      if (settingsDoc.exists && settingsDoc.data() != null) {
        final data = settingsDoc.data()!;
        final prefs = await SharedPreferences.getInstance();
        if (data['usda_api_key'] != null) {
          await prefs.setString('usda_api_key', data['usda_api_key'].toString());
        }
        if (data['gemini_api_key'] != null) {
          await prefs.setString('gemini_api_key', data['gemini_api_key'].toString());
        }
        if (data['usda_include_branded'] != null) {
          await prefs.setBool('usda_include_branded', data['usda_include_branded'] == true);
        }
      }
    } catch (_) {}
  }
}