import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/alert_service.dart';
import '../services/companion_service.dart';

class CheckInService {
  static const _deadlineKey = 'checkin_deadline_epoch';
  Timer? _timer;

  Future<void> startCheckIn(Duration duration, {String message = 'Check-in reminder'}) async {
    final prefs = await SharedPreferences.getInstance();
    final deadline = DateTime.now().add(duration);
    final deadlineMs = deadline.millisecondsSinceEpoch;
    await prefs.setInt(_deadlineKey, deadlineMs);
    
    // Notify companion apps about the check-in
    try {
      await CompanionService().sendCheckInNotification(
        scheduledTime: deadline,
        message: message,
      );
    } catch (e) {
      print('Error notifying companion apps about check-in: $e');
    }
    
    _timer?.cancel();
    _timer = Timer(duration, () async {
      // When deadline passes, trigger auto alert
      await _sendMissedCheckInAlert();
    });
  }

  Future<void> cancel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deadlineKey);
    _timer?.cancel();
  }

  Future<int?> getRemainingSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final deadline = prefs.getInt(_deadlineKey);
    if (deadline == null) return null;
    final remaining = deadline - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? (remaining / 1000).floor() : 0;
  }

  Future<void> _sendMissedCheckInAlert() async {
    final alerts = AlertService();
    await alerts.startSosSession(customMessage: 'Missed check-in. Please reach out to me now.');
    await cancel();
  }
}