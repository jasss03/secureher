import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../services/location_service.dart';
import '../../services/tts_service.dart';
import '../../services/notification_service.dart';
import '../../services/alert_service.dart';
import 'sos_service.dart';
import '../../services/ai_assist_service.dart';
import '../../services/emergency_messenger.dart';
import '../../services/evidence_service.dart';
import 'evidence_player_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background/flutter_background.dart';
import 'manage_evidence_screen.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color? color;
  const _PulsingIcon({required this.icon, this.color});
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _a = Tween<double>(begin: 0.9, end: 1.1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _a,
      child: Icon(widget.icon, color: widget.color),
    );
  }
}

class _SosScreenState extends State<SosScreen> {
  late final SosService _sos;
  late final LocationService _location;
  late final TtsService _tts;
  final _alerts = AlertService();
  bool _isRecording = false;
  bool _autoRecord = true;
  String? _lastSaved;
  int _lastAlertCount = 0;
  String? _alertId;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  // GPS
  Position? _lastPos;
  double? _accuracy;
  StreamSubscription<Position>? _posSub;

  // AI assist
  AiAssistService? _ai;
  bool _danger = false;
  String? _keyword;
  String _lastTranscript = '';

  // Recent evidence
  final EvidenceService _evidenceService = EvidenceService();
  List<EvidenceItem> _recent = [];
  bool _recentLoading = true;

  @override
  void initState() {
    super.initState();
    _sos = SosService();
    _location = LocationService();
    _tts = TtsService();
    NotificationService.init();
    _loadRecent();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _posSub?.cancel();
    _sos.dispose();
    try { FlutterBackground.disableBackgroundExecution(); } catch (_) {}
    super.dispose();
  }

  Future<void> _startSos() async {
    final acc = context.read<AccessibilityModel>();
    if (acc.voiceGuidance) await _tts.speak('Starting SOS. Recording has begun.');

    // Enable background (best effort)
    try {
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'SecureHer SOS',
        notificationText: 'Recording & monitoring active',
      );
      await FlutterBackground.initialize(androidConfig: androidConfig);
      await FlutterBackground.enableBackgroundExecution();
    } catch (_) {}

    // Start continuous location updates
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) {
      setState(() { _lastPos = pos; _accuracy = pos.accuracy; });
    });
    _lastPos = await _location.getCurrentPosition();

    // Send initial alert to contacts and create Firestore session if available
    try {
      final res = await _alerts.startSosSession(position: _lastPos);
      _lastAlertCount = res.recipients;
      _alertId = res.alertId;
    } catch (_) {}

    // Respect auto-record toggle for including microphone audio
    final started = await _sos.startRecording(includeAudio: _autoRecord);
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start recording. Check camera/mic permissions.')),
        );
      }
      return;
    }

    // Start AI assist listening in parallel; on danger trigger, notify again
    _ai = AiAssistService();
    try {
      final ok = await _ai!.startListening();
      if (ok) {
        _ai!.transcripts.listen((t) async {
          final prev = _danger;
          setState(() { _lastTranscript = t; _danger = _ai!.dangerDetected; _keyword = _ai!.matchedKeyword; });
          if (!prev && _danger) {
            await EmergencyMessenger.pingTrusted(
              announceShare: false,
              backendBaseUrl: const String.fromEnvironment('SECUREHER_API', defaultValue: ''),
            );
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mic access denied or speech engine unavailable. Keyword listening disabled.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start keyword listening.')),
        );
      }
    }

    // Send emergency SMS/Backend ping immediately
    await EmergencyMessenger.pingTrusted(
      announceShare: false,
      backendBaseUrl: const String.fromEnvironment('SECUREHER_API', defaultValue: ''),
    );

    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      setState(() => _elapsed += const Duration(seconds: 1));
      // Every 5 seconds, push live location update to backend/Firestore
      if (_alertId != null && _elapsed.inSeconds % 5 == 0) {
        final pos = await _location.getCurrentPosition();
        if (pos != null) {
          await _alerts.updateLiveLocation(_alertId!, pos);
        }
      }
    });

    // Optional: show a local notification
    await NotificationService.showImmediate(
      title: 'SOS Active',
      body: 'Recording video${_lastPos != null ? ' @ ${_lastPos!.latitude.toStringAsFixed(5)}, ${_lastPos!.longitude.toStringAsFixed(5)}' : ''}',
    );
  }

  Future<void> _stopSos() async {
    final acc = context.read<AccessibilityModel>();
    // Stop AI listening
    try { await _ai?.stop(); } catch (_) {}
    await _posSub?.cancel();

    final pos = await _location.getCurrentPosition();
    final savedPath = await _sos.stopAndSaveEncrypted(metadata: {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'position': pos == null ? null : {
        'lat': pos.latitude,
        'lng': pos.longitude,
      },
      'ai': {
        'danger': _danger,
        'keyword': _keyword,
        'lastTranscript': _lastTranscript,
      }
    });
    // Optional safe message and close session
    try {
      if (_alertId != null) {
        await _alerts.closeSosSession(_alertId!, position: pos);
      }
      await _alerts.sendSafeMessage(position: pos);
    } catch (_) {}
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _lastSaved = savedPath;
    });
    // refresh recent list
    await _loadRecent();
    if (mounted) {
      final status = _danger ? 'ALERT: keyword ${_keyword ?? ''} detected' : 'No danger keywords heard';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedPath != null ? 'Encrypted evidence saved. $status' : 'Recording stopped. Nothing saved.')),
      );
    }
    if (acc.voiceGuidance) await _tts.speak('SOS stopped. Evidence saved securely.');
  }

  Future<void> _loadRecent() async {
    setState(() => _recentLoading = true);
    final items = await _evidenceService.listRecent(limit: 10);
    setState(() {
      _recent = items;
      _recentLoading = false;
    });
  }

  Future<void> _openItem(EvidenceItem item) async {
    final f = await _evidenceService.decryptForPlayback(item);
    if (f == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recording found for this entry.')),
        );
      }
      return;
    }
    if (mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EvidencePlayerScreen(file: f)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsedStr = _formatDuration(_elapsed);
    return Scaffold(
      appBar: AppBar(title: const Text('SOS')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            _isRecording
                ? GestureDetector(
                    onLongPress: _stopSos, // discreet cancel via long press
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        shape: const StadiumBorder(),
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.stop_circle_rounded, size: 28),
                      label: Text('HOLD TO CANCEL • $elapsedStr', style: const TextStyle(fontSize: 20)),
                    ),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 22), shape: const StadiumBorder()),
                    onPressed: _startSos,
                    icon: const Icon(Icons.radio_button_checked_rounded, size: 28),
                    label: const Text('ONE-TAP SOS', style: TextStyle(fontSize: 20)),
                  ),
            const SizedBox(height: 16),
            // GPS/status row
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.gps_fixed_rounded),
                title: Text(_lastPos == null
                    ? 'GPS: locating...'
                    : 'GPS: ${_lastPos!.latitude.toStringAsFixed(5)}, ${_lastPos!.longitude.toStringAsFixed(5)}'),
                subtitle: Text(_accuracy == null ? '—' : 'Accuracy: ±${_accuracy!.toStringAsFixed(0)} m'),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_shared_rounded),
                  tooltip: 'Manage evidence',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageEvidenceScreen())),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto-record video & audio'),
              value: _autoRecord,
              onChanged: (v) => setState(() => _autoRecord = v),
            ),
            const SizedBox(height: 16),
            // AI status
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: _PulsingIcon(icon: _isRecording ? Icons.mic_rounded : Icons.mic_off_rounded, color: _danger ? theme.colorScheme.error : theme.colorScheme.primary),
                title: Text(_danger ? 'Possible distress detected' : 'Listening for distress keywords'),
                subtitle: Text(_danger
                    ? 'Matched: ${_keyword ?? ''}'
                    : (_lastTranscript.isEmpty ? '—' : _lastTranscript)),
              ),
            ),
            const SizedBox(height: 16),
            if (_lastAlertCount > 0)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.sms_rounded),
                  title: Text('Alert sent to $_lastAlertCount contact${_lastAlertCount > 1 ? 's' : ''}'),
                  subtitle: const Text('Opened SMS composer with prefilled SOS message.'),
                ),
              ),
            if (_lastSaved != null)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Encrypted evidence saved'),
                  subtitle: Text(_lastSaved!),
                ),
              ),
            const SizedBox(height: 8),
            Text('Recent SOS logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _recentLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_recent.isEmpty
                      ? const Center(child: Text('No recent SOS logs.'))
                      : ListView.separated(
                          itemCount: _recent.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = _recent[i];
                            final meta = item.metadata ?? {};
                            final danger = (meta['ai'] is Map) ? ((meta['ai']['danger'] ?? false) as bool) : false;
                            final keyword = (meta['ai'] is Map) ? (meta['ai']['keyword']?.toString() ?? '') : '';
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                leading: Icon(danger ? Icons.warning_amber_rounded : Icons.event_available_rounded,
                                    color: danger ? Theme.of(context).colorScheme.error : null),
                                title: Text(item.formattedTime),
                                subtitle: Text(
                                    danger && keyword.isNotEmpty ? 'Distress keyword: $keyword' : 'Tap to open recording'),
                                trailing: const Icon(Icons.play_circle_fill_rounded),
                                onTap: () => _openItem(item),
                              ),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
