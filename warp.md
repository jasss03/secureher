# Warp runbook for SecureHer auth setup

This file helps you set up and verify authentication end-to-end: Email/Password, Google Sign-In, and Phone (OTP). It assumes macOS + Flutter + Firebase.

Prerequisites
- Flutter SDK installed
- Xcode (iOS) and/or Android Studio (Android)
- Firebase project created

1) Dependencies
- We added google_sign_in and wired Firebase Auth. Install packages:

```bash
flutter pub get
```

2) Firebase platform config
- Recommended: use FlutterFire CLI to generate lib/firebase_options.dart and apply platform configs.

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

- Alternatively, place platform config files manually:
  - Android: google-services.json -> android/app/google-services.json
  - iOS: GoogleService-Info.plist -> add to ios/Runner in Xcode

3) Gradle plugins & SDKs (Android)
- Already configured by code updates:
  - Project: android/build.gradle.kts includes Google Services plugin (apply false)
  - App: android/app/build.gradle.kts applies plugin and includes Firebase BoM + firebase-auth

4) Enable providers in Firebase Console
- Authentication > Sign-in method:
  - Enable Email/Password
  - Enable Phone
  - Enable Google
- For Android Phone Auth, add SHA-1 and SHA-256 in Project settings > Your apps > Android

Get debug SHA keys:
```bash
keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
```

5) Initialize Firebase in code
- If you used flutterfire configure, ensure main.dart initializes with DefaultFirebaseOptions.

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

6) Build & run
```bash
flutter clean
flutter pub get
flutter run
```

7) Verify flows
- Email/Password
  - On Auth screen, enter email + password, tap Login (or Create Account in Sign Up tab).
- Google Sign-In
  - Tap "Continue with Google". Select account, you should land on Home.
- Phone OTP
  - Enter phone in E.164 format, e.g., +15551234567.
  - Tap "Use OTP" to go to OTP screen, receive code, then verify.

Troubleshooting
- Missing config
  - If Firebase fails to init, ensure google-services.json/GoogleService-Info.plist and/or firebase_options.dart exist and match app IDs.
- Phone OTP fails
  - Confirm SHA-1/SHA-256 added in Firebase Console. Use a real device. Ensure E.164 phone format.
- Google Sign-In errors on iOS
  - Make sure the reversed client ID URL scheme from GoogleService-Info.plist is present in Info tab (Xcode) under URL Types.

Security notes
- Never commit secrets. The Firebase config files contain non-secret identifiers and are safe to commit, but API keys should still be treated with care.

Next steps
- Optionally store user profile documents in Firestore on first sign-in.
- Add account linking (link Google to Email/Phone) if needed.
