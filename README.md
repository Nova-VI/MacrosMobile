# Macro mobile app

Macro is a Flutter food, recipe, weight, and nutrition tracker. It uses Firebase Authentication and Cloud Firestore. The companion web client lives in the separate `Macro` repository and reads the same account data.

## Local setup

1. Install a Flutter SDK compatible with the Dart constraint in `pubspec.yaml`, plus Android SDK tooling for Android builds.
2. Run `flutter pub get` from this directory.
3. Configure Firebase for your own project. The Android application ID is set in `android/app/build.gradle.kts`; its `google-services.json` must match that ID and project. Enable the authentication providers used by the app and deploy Firestore rules that restrict each user's data to that user.
4. Run `flutter devices`, then `flutter run -d <device-id>`. Start with a test account and complete onboarding.

The app calls `Firebase.initializeApp()` at startup. It expects native Firebase configuration on the target platform; Android is the configured build path in this repository. API keys for USDA and Gemini are entered through onboarding or profile settings by the signed-in user. Do not add personal keys or service-account credentials to the repository.

## Main flows and data

- Authentication and onboarding lead to dashboard, food logging, recipe library, weight tracker, statistics, and profile settings tabs.
- Firestore documents hold profiles, foods, dated logs, recipes, weights, and settings. `lib/services/firestore_service.dart` is the main app data layer; model `toFirestore` and `fromFirestore` methods define the stored fields.
- USDA search uses the user's USDA key. Barcode scanning first looks up an exact product in Open Food Facts. Gemini features use the user's Gemini key.
- Firestore persistence is enabled for offline reads and queued writes. A successful local UI update alone does not prove that a pending write has reached the server; test reconnection when changing sync behavior.
- Some account preferences and API keys are cached in `SharedPreferences` under user-specific names. Review this storage choice before using sensitive production credentials on an untrusted device.

## Checks

Run `flutter analyze --no-pub` and `flutter test` after changes. Before releasing, exercise sign-in and account switching, a food and recipe save, a backdated weight, offline/reconnect behavior, and the same account on the web client and an Android device. The private audit in the local `reports/` directory is intentionally ignored by Git and is not a release artifact.

## Android release

The current `release` build type uses the local Android debug signing key, matching the project's previous build behavior. `flutter build apk --release` works without `android/key.properties`, but the resulting APK is intended for personal testing. If you distribute the app, configure a private release key first. If an APK is already installed or distributed, preserve its signing certificate so the next APK can update it.
