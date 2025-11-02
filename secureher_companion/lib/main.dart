import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:secureher_companion/config/app_theme.dart';
import 'package:secureher_companion/features/auth/app_linking_screen.dart';
import 'package:secureher_companion/services/notification_service.dart';
import 'package:secureher_companion/services/connectivity_service.dart';

// Firebase background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    print('Handling a background message: ${message.messageId}');
  } catch (e) {
    print('Error initializing Firebase in background handler: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with default options
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('Error initializing Firebase: $e');
  }
  
  // Set up Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Initialize notification service
  await NotificationService.initialize();
  
  // Update FCM token when app starts
  ConnectivityService.updateFcmToken();
  
  runApp(const CompanionApp());
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureHer Companion',
      theme: AppTheme.light(),
      home: const AppLinkingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
