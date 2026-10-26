# MacroTracker for Android

MacroTracker is a Flutter client for tracking food, recipes, body weight, and nutrition goals. It shares a Firebase Authentication account and Cloud Firestore data with the companion JavaScript web client in the separate `Macro` repository. Android is the configured native build target in this repository; the generated Flutter directories for other platforms do not imply released builds.

## Features

- Email/password and Google sign-in, followed by profile and goal onboarding.
- Daily food logging from a personal library, manual entry, or USDA FoodData Central search. Logs can be edited, copied, deleted, and assigned to earlier dates.
- Camera barcode scanning with Open Food Facts lookup. Incomplete product nutrition is flagged for review.
- Recipe composition from saved or searched foods, with macro and micronutrient totals.
- Weight history, trend and goal-path charts, and nutrition statistics with date-specific targets.
- Optional Gemini-assisted food emojis and meal-description estimates. The user reviews estimates before saving them.
- Weekly adaptive target proposals based on logged intake, weight history, and the active goal phase. Proposed targets take effect only when accepted.
- Firestore-backed account sync and persistent local caching for available data and queued writes. Network-dependent searches and AI features still require connectivity.

## How it is organized

`lib/main.dart` initializes Firebase, local theme state, Firestore persistence, and the authentication gate. Screens are in `lib/screens/`; reusable sheets and charts are in `lib/widgets/`. `lib/services/firestore_service.dart` maintains local caches, Firestore listeners, and writes. `lib/models/` defines the stored food, log, weight, nutrition, and profile fields. The coach is split between `adaptive_coach_engine.dart` (calculations), `coach_pipeline.dart` (history replay and weekly eligibility), and `adaptive_coach_service.dart` (loading, recomputation, and accept/dismiss actions).

Both clients use the same account-scoped Firestore layout:

```text
users/{uid}
  profile/1            Profile, goals, dated goal phases and adjustments
  settings/config      Appearance, API preferences and user-supplied keys
  foods/library        Reusable foods and recipes in an items map
  weight_logs/all      Weights keyed by date
  logs/YYYY-MM         Dated food logs grouped by month
```

The Flutter client updates its local state when the user edits data and queues Firestore writes. A local update can appear before the server acknowledges it. The UI reports a later sync failure through `syncErrorNotifier`; reconnect and check the second client when testing offline behavior.

## Run locally

1. Install a Flutter SDK compatible with the Dart constraint in `pubspec.yaml` and an Android SDK. Run `flutter pub get`.
2. Configure Firebase for your own project before using the app with personal data. The Android application ID is in `android/app/build.gradle.kts`; `android/app/google-services.json` must match it and the intended Firebase project. Enable the sign-in providers you use and deploy Firestore rules that restrict each user's documents to that account. Google sign-in also needs the correct Android signing fingerprints in Firebase.
3. Run `flutter devices`, then `flutter run -d <device-id>`. Sign in with a test account and finish onboarding.

The app calls `Firebase.initializeApp()` with native configuration at startup. USDA and Gemini are optional, user-supplied keys entered through onboarding or settings. They are synced in the user's Firestore settings document and cached on Android through `flutter_secure_storage`; ordinary appearance and onboarding preferences use account-scoped `SharedPreferences`. Do not commit personal provider keys or service-account credentials. Firebase rules, rather than the client-side `users/{uid}` path alone, must enforce account isolation.

## Verify changes

```powershell
flutter analyze --no-pub
flutter test
```

The `test/` directory covers models, serving units, nutrition rounding, goal dates, offline behavior, coach logic, and widget regressions. For an end-to-end check, test sign-in and account switching, food and recipe saves, a backdated log and weight, offline edits followed by reconnection, and the same account on Android and web. Unit tests do not verify deployed Firebase rules, external API responses, or release-device behavior.

## Android release

The `release` build reads signing properties from the private `android/key.properties` file. Configure a release keystore and matching properties before running `flutter build apk --release`; do not commit the keystore or passwords. Preserve the signing certificate used for an installed APK so later builds can update it. A successful APK build is separate from store publication and device acceptance testing.
