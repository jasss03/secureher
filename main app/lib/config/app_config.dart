class AppConfig {
  // Toggle Firestore features at build time
  // Enable by building with: --dart-define=USE_FIRESTORE=true
  static const bool useFirestore = bool.fromEnvironment('USE_FIRESTORE', defaultValue: false);
}