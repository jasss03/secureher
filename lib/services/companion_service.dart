import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompanionService {
  static final CompanionService _instance = CompanionService._internal();
  factory CompanionService() => _instance;
  CompanionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Collection references
  final String _connectionsCollection = 'companion_connections';
  
  // Generate a random 6-digit code for linking
  String generateLinkCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
  
  // Store the link code in Firestore with expiration
  Future<String> createLinkCode() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    final linkCode = generateLinkCode();
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    
    await _firestore.collection('companion_link_codes').doc(linkCode).set({
      'mainAppUserId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
    });
    
    return linkCode;
  }
  
  // Check if user has any linked companion apps
  Future<List<Map<String, dynamic>>> getLinkedCompanions() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    final connections = await _firestore
        .collection(_connectionsCollection)
        .where('mainAppUserId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .get();
    
    return connections.docs.map((doc) => {
      'id': doc.id,
      'companionUserId': doc.data()['companionUserId'],
      'companionName': doc.data()['companionName'] ?? 'Companion App',
      'lastActive': doc.data()['lastActive'],
      'fcmToken': doc.data()['companionFcmToken'],
    }).toList();
  }
  
  // Remove a linked companion
  Future<void> removeCompanion(String connectionId) async {
    await _firestore
        .collection(_connectionsCollection)
        .doc(connectionId)
        .update({'active': false});
  }
  
  // Send notification to all linked companions
  Future<void> notifyCompanions({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final companions = await getLinkedCompanions();
    if (companions.isEmpty) return;
    
    // Create notification document in Firestore to trigger Cloud Function
    for (final companion in companions) {
      if (companion['fcmToken'] != null) {
        await _firestore.collection('notifications').add({
          'to': companion['fcmToken'],
          'title': title,
          'body': body,
          'data': {
            'type': 'sos_alert',
            'mainAppUserId': user.uid,
            ...?data,
          },
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }
  
  // Send SOS alert to all linked companions
  Future<void> sendSosAlert({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await notifyCompanions(
      title: 'SOS ALERT',
      body: '${user.displayName ?? 'Your friend'} needs help!',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
    
    // Also store the alert in Firestore for companion app to retrieve
    await _firestore.collection('sos_alerts').add({
      'userId': user.uid,
      'userName': user.displayName,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'timestamp': FieldValue.serverTimestamp(),
      'resolved': false,
    });
  }
  
  // Send check-in notification to companions
  Future<void> sendCheckInNotification({
    required DateTime scheduledTime,
    required String message,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await notifyCompanions(
      title: 'New Check-in Scheduled',
      body: '${user.displayName ?? 'Your friend'} scheduled a check-in',
      data: {
        'type': 'check_in',
        'scheduledTime': scheduledTime.millisecondsSinceEpoch,
        'message': message,
      },
    );
    
    // Store check-in in Firestore
    await _firestore.collection('check_ins').add({
      'userId': user.uid,
      'userName': user.displayName,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'message': message,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  
  // Mark a check-in as completed
  Future<void> completeCheckIn(String checkInId) async {
    await _firestore.collection('check_ins').doc(checkInId).update({
      'completed': true,
      'completedAt': FieldValue.serverTimestamp(),
    });
    
    final user = _auth.currentUser;
    if (user == null) return;
    
    await notifyCompanions(
      title: 'Check-in Completed',
      body: '${user.displayName ?? 'Your friend'} has completed their check-in',
      data: {
        'type': 'check_in_completed',
        'checkInId': checkInId,
      },
    );
  }
}