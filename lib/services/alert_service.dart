import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import '../config/app_config.dart';
import 'contacts_service.dart';
import '../utils/phone_utils.dart';

class AlertSessionResult {
  final int recipients;
  final String? alertId;
  AlertSessionResult({required this.recipients, required this.alertId});
}

class AlertService {
  final _contacts = ContactsService();

  // Simple heartbeat location share (optional Firestore only). Safe to call without Firebase configured.
  bool get _firestoreEnabled => AppConfig.useFirestore && Firebase.apps.isNotEmpty;

  Future<void> shareLocationHeartbeat(Position position) async {
    if (!_firestoreEnabled) return;
    try {
      await FirebaseFirestore.instance.collection('location_shares').add({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Ignore if Firestore not configured.
    }
  }

  Future<void> _openSmsToContacts(String body, {int maxRecipients = 3}) async {
    final contacts = await _contacts.getContacts();
    final numbers = contacts.map((c) => c.phone).where((p) => p.trim().isNotEmpty).take(maxRecipients).toList();
    if (numbers.isEmpty) return;
    final uri = Uri(scheme: 'sms', path: numbers.join(','), queryParameters: {'body': body});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> notifyLocationShareStart({Position? position}) async {
    final msg = _composeLocationShareMessage(position: position);
    await _openSmsToContacts(msg);
  }

  // Starts an SOS session: creates Firestore doc (if available) and opens SMS composer.
  Future<AlertSessionResult> startSosSession({Position? position, String? customMessage}) async {
    final contacts = await _contacts.getContacts();
    if (contacts.isEmpty) return AlertSessionResult(recipients: 0, alertId: null);

    final msg = customMessage ?? _composeMessage(position: position);
    String? alertId;

    // Try Firestore (optional)
    if (_firestoreEnabled) {
      try {
        final ref = await FirebaseFirestore.instance.collection('alerts').add({
        'type': 'sos',
        'message': msg,
        'active': true,
        'position': position == null
            ? null
            : {
                'lat': position.latitude,
                'lng': position.longitude,
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              },
        'recipients': contacts.map((e) => {'name': e.name, 'phone': e.phone, 'email': e.email}).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
        alertId = ref.id;
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('Firestore write skipped: $e');
        }
      }
    }

    // Attempt to open SMS composer with prefilled content to first 3 contacts
    final numbers = contacts
        .map((c) => PhoneUtils.normalizeIndianNumber(c.phone))
        .where((p) => p.trim().isNotEmpty)
        .take(3)
        .toList();
    if (numbers.isNotEmpty) {
      await _openSmsToContacts(msg);
    }
    return AlertSessionResult(recipients: numbers.length, alertId: alertId);
  }

  Future<void> updateLiveLocation(String alertId, Position position) async {
    if (!_firestoreEnabled) return;
    try {
      await FirebaseFirestore.instance.collection('alerts').doc(alertId).collection('locations').add({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('alerts').doc(alertId).update({
        'last': {'lat': position.latitude, 'lng': position.longitude, 'timestamp': FieldValue.serverTimestamp()},
      });
    } catch (_) {}
  }

  Future<void> closeSosSession(String alertId, {Position? position}) async {
    if (!_firestoreEnabled) return;
    try {
      await FirebaseFirestore.instance.collection('alerts').doc(alertId).update({
        'active': false,
        'endedAt': FieldValue.serverTimestamp(),
        if (position != null)
          'end': {'lat': position.latitude, 'lng': position.longitude, 'timestamp': FieldValue.serverTimestamp()},
      });
    } catch (_) {}
  }

  Future<void> sendSafeMessage({Position? position}) async {
    final contacts = await _contacts.getContacts();
    if (contacts.isEmpty) return;
    final msg = _composeSafeMessage(position: position);
    if (_firestoreEnabled) {
      try {
        await FirebaseFirestore.instance.collection('alerts').add({
        'type': 'safe',
        'message': msg,
        'position': position == null
            ? null
            : {
                'lat': position.latitude,
                'lng': position.longitude,
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              },
        'recipients': contacts.map((e) => {'name': e.name, 'phone': e.phone, 'email': e.email}).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      } catch (_) {}
    }

    final numbers = contacts
        .map((c) => PhoneUtils.normalizeIndianNumber(c.phone))
        .where((p) => p.trim().isNotEmpty)
        .take(3)
        .toList();
    if (numbers.isEmpty) return;
    await _openSmsToContacts(msg);
  }

  String _composeMessage({Position? position}) {
    final base = 'SOS! I need help. Please contact me immediately.';
    if (position == null) return base;
    final maps = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    return '$base\nMy live location: $maps';
  }

  String _composeSafeMessage({Position? position}) {
    final base = "I'm safe now. Thank you for checking in.";
    if (position == null) return base;
    final maps = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    return '$base\nCurrent location: $maps';
  }

  String _composeLocationShareMessage({Position? position}) {
    final base = 'I\'ve started sharing my live location with you.';
    if (position == null) return base;
    final maps = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    return '$base\nMy current location: $maps';
  }
}
