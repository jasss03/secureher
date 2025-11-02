import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'dart:async';
import '../../widgets/branding.dart';
import '../contacts/trusted_contacts_screen.dart';
import '../fake_call/fake_call_screen.dart';
import '../route_guard/route_guard_screen.dart';
import '../sos/sos_screen.dart';
import '../../services/siren_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/motion_service.dart';
import '../safe_zones/safe_zones_screen.dart';
import '../sos/battery_saver_screen.dart';
import '../checkin/check_in_screen.dart';
import '../../services/location_service.dart';
import '../../services/alert_service.dart';
import '../../services/emergency_messenger.dart';
import '../tips/tips_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _siren = SirenService();
  MotionService? _motion;
  bool _sirenOn = false;
  bool _batteryMode = false;
  bool _isSOSActive = false;
  int _powerButtonPresses = 0;
  DateTime? _lastPowerPress;
  double _motionSensitivity = 1.5;

  // Live location sharing
  bool _shareLocation = false;
  Timer? _locTimer;
  final _locationSvc = LocationService();
  final _alerts = AlertService();

  // Status snapshot
  int _trustedContacts = 0;
  String _lastCheckIn = '—';
  String _currentLocation = '—';
  bool _routeActive = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _initStatus();
    _startMotion();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion?.stop();
    _stopLocationSharing();
    super.dispose();
  }
  
  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _batteryMode = prefs.getBool('battery_mode') ?? false;
      _motionSensitivity = prefs.getDouble('motion_sensitivity') ?? 1.5;
      _shareLocation = prefs.getBool('share_location') ?? false;
    });
    if (_shareLocation) _startLocationSharing();
  }
  
  Future<void> _initStatus() async {
    // TODO: Pull real data: contacts count, last check-in, current location, route status
    User? u;
    try {
      u = FirebaseAuth.instance.currentUser;
    } catch (_) {
      u = null;
    }
    final name = u?.displayName?.trim();
    final email = u?.email;
    final phone = u?.phoneNumber;
    setState(() {
      _trustedContacts = 0;
      _lastCheckIn = 'No timer';
      _currentLocation = 'Unknown';
      _routeActive = false;
      _userName = (name != null && name.isNotEmpty)
          ? name
          : (phone != null && phone.isNotEmpty)
              ? phone
              : (email != null && email.isNotEmpty)
                  ? email.split('@').first
                  : 'Friend';
    });
  }

  void _startMotion() {
    _motion?.stop();
    final sens = _batteryMode ? (_motionSensitivity + 0.8) : _motionSensitivity;
    _motion = MotionService(
      sensitivity: sens,
      onShakePanic: () => _triggerSOS('Shake'),
      onImpactDetected: () => _triggerSOS('Impact'),
    )..start();
  }

  void _startLocationSharing() {
    _locTimer?.cancel();
    final interval = _batteryMode ? const Duration(minutes: 2) : const Duration(seconds: 30);
    _locTimer = Timer.periodic(interval, (_) async {
      final pos = await _locationSvc.getCurrentPosition();
      if (pos != null) {
        await _alerts.shareLocationHeartbeat(pos);
        setState(() {
          _currentLocation = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
      }
    });
  }

  void _stopLocationSharing() {
    _locTimer?.cancel();
    _locTimer = null;
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Approximate power button multi-press (limited on Android without native).
      _handlePowerButtonPress();
    }
  }
  
  void _handlePowerButtonPress() {
    final now = DateTime.now();
    if (_lastPowerPress != null && now.difference(_lastPowerPress!).inSeconds < 2) {
      _powerButtonPresses++;
      if (_powerButtonPresses >= 3) {
        _triggerSOS('Power Button');
        _powerButtonPresses = 0;
      }
    } else {
      _powerButtonPresses = 1;
    }
    _lastPowerPress = now;
  }
  
  Future<void> _triggerSOS(String method) async {
    if (_isSOSActive) return;
    
    setState(() => _isSOSActive = true);
    
    // Haptic feedback
    HapticFeedback.heavyImpact();
    
    // Navigate to SOS screen
      Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SosScreen())
    );
    
    // Reset after delay
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isSOSActive = false);
    });
  }

  void _openSafeZones() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafeZonesScreen()));
  }

  void _openCheckIn() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckInScreen()));
  }

  void _openBatterySaver() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BatterySaverScreen()));
  }

  Future<void> _toggleSiren() async {
    if (_sirenOn) {
      await _siren.stop();
    } else {
      await _siren.play();
    }
    setState(() => _sirenOn = !_sirenOn);
  }
  
  Future<void> _toggleBatteryMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _batteryMode = !_batteryMode);
    await prefs.setBool('battery_mode', _batteryMode);
    // Restart motion with new sensitivity and adjust location interval
    _startMotion();
    if (_shareLocation) {
      _startLocationSharing();
    }
  }

  Future<void> _toggleShareLocation() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _shareLocation = !_shareLocation);
    await prefs.setBool('share_location', _shareLocation);
    if (_shareLocation) {
      // Start periodic sharing and send an initial SMS to contacts with current location
      _startLocationSharing();
      final pos = await _locationSvc.getCurrentPosition();
      // Notify via Android SMS if possible, otherwise via backend
      await EmergencyMessenger.pingTrusted(
        announceShare: true,
        backendBaseUrl: const String.fromEnvironment('SECUREHER_API', defaultValue: ''),
      );
      // Keep legacy composer path as secondary UX option
      await _alerts.notifyLocationShareStart(position: pos);
    } else {
      _stopLocationSharing();
    }
  }

  Future<void> _checkInNow() async {
    final pos = await _locationSvc.getCurrentPosition();
    try {
      // Use silent Android SMS or backend
      await EmergencyMessenger.pingTrusted(
        announceShare: true,
        backendBaseUrl: const String.fromEnvironment('SECUREHER_API', defaultValue: ''),
      );
      // Keep existing composer-based safe message as a fallback
      await _alerts.sendSafeMessage(position: pos);
    } catch (_) {}
    setState(() {
      _lastCheckIn = 'Just now';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in sent to trusted contacts')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Her'),
        centerTitle: true,
      ),
      body: PastelBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome back, ${_userName ?? ''}!', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Your safety is our priority.', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 12),
_RadialActions(
              onSos: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SosScreen())),
              onTrusted: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrustedContactsScreen())),
              onRouteGuard: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RouteGuardScreen())),
              onSafeZones: _openSafeZones,
              onFakeCall: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FakeCallScreen())),
              onSiren: _toggleSiren,
              sirenOn: _sirenOn,
            ),
            const SizedBox(height: 16),
Text('Status', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            // Quick actions
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Share live location with trusted contacts (periodic)'),
                      subtitle: Text(_shareLocation ? 'Active' : 'Off'),
                      value: _shareLocation,
                      onChanged: (_) => _toggleShareLocation(),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _checkInNow,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Check-in now (notify contacts)'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tips section
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.menu_book_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Safety Tips', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: const Text('Stay Safe at Night'),
                      subtitle: const Text('Essential tips for walking alone after dark'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TipsScreen())),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TipsScreen())),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('View All Tips'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // AI status / status chips
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusChip(
                  icon: Icons.my_location_rounded,
                  label: 'Location',
                  value: _shareLocation ? 'Sharing' : 'Off',
                ),
                _StatusChip(
                  icon: Icons.battery_saver_rounded,
                  label: 'Battery Saver',
                  value: _batteryMode ? 'On' : 'Off',
                  onTap: _openBatterySaver,
                ),
                _StatusChip(
                  icon: Icons.timer_rounded,
                  label: 'Last Check-in',
                  value: _lastCheckIn,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _StatusChip({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialActions extends StatelessWidget {
  final VoidCallback onSos;
  final VoidCallback onTrusted;
  final VoidCallback onRouteGuard;
  final VoidCallback onSafeZones;
  final VoidCallback onFakeCall;
  final VoidCallback onSiren;
  final bool sirenOn;
  const _RadialActions({
    required this.onSos,
    required this.onTrusted,
    required this.onRouteGuard,
    required this.onSafeZones,
    required this.onFakeCall,
    required this.onSiren,
    required this.sirenOn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double size = 320;
    const double radius = 120;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Center SOS button
            GestureDetector(
              onLongPress: onSos,
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF4D6D), Color(0xFFFF8DB1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: Color(0x66FF4D6D), blurRadius: 24, spreadRadius: 4),
                  ],
                ),
                child: const Center(
                  child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                ),
              ),
            ),

            // Orbiting actions
            _orbit(angleDeg: -90, radius: radius, child: _bubble(icon: Icons.people_alt_rounded, label: 'Trusted', onTap: onTrusted, theme: theme)),
            _orbit(angleDeg: -30, radius: radius, child: _bubble(icon: Icons.assistant_direction_rounded, label: 'Route', onTap: onRouteGuard, theme: theme)),
            _orbit(angleDeg: 30, radius: radius, child: _bubble(icon: Icons.shield_rounded, label: 'Safe Zones', onTap: onSafeZones, theme: theme)),
            _orbit(angleDeg: 90, radius: radius, child: _bubble(icon: Icons.call_rounded, label: 'Fake Call', onTap: onFakeCall, theme: theme)),
            _orbit(angleDeg: 150, radius: radius, child: _bubble(icon: sirenOn ? Icons.volume_off_rounded : Icons.volume_up_rounded, label: sirenOn ? 'Stop Siren' : 'Siren', onTap: onSiren, theme: theme)),
            _orbit(angleDeg: 210, radius: radius, child: _bubble(icon: Icons.timer_rounded, label: 'Check-In', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckInScreen())), theme: theme)),
          ],
        ),
      ),
    );
  }

  static Widget _orbit({required double angleDeg, required double radius, required Widget child}) {
    final rad = angleDeg * math.pi / 180.0;
    final dx = radius * math.cos(rad);
    final dy = radius * math.sin(rad);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: child,
    );
  }

  static Widget _bubble({required IconData icon, required String label, required VoidCallback onTap, required ThemeData theme}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surface,
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
