import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import '../../services/location_service.dart';
import '../../services/alert_service.dart';

class RouteGuardScreen extends StatefulWidget {
  const RouteGuardScreen({super.key});

  @override
  State<RouteGuardScreen> createState() => _RouteGuardScreenState();
}

class RouteOption {
  final String name;
  final String description;
  final int durationMinutes;
  final double safetyScore;
  final bool isRecommended;

  RouteOption({
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.safetyScore,
    this.isRecommended = false,
  });
}

class _RouteGuardScreenState extends State<RouteGuardScreen> {
  final _destAddressController = TextEditingController();
  final _destLat = TextEditingController();
  final _destLng = TextEditingController();
  final _etaMin = TextEditingController(text: '30');
  final _loc = LocationService();
  final _alerts = AlertService();
  StreamSubscription<Position>? _sub;
  Position? _start;
  Position? _current;
  double? _minDistToDest;
  bool _active = false;
  bool _isLoading = false;
  bool _showRouteOptions = false;
  DateTime? _deadline;
  String? _status;
  String? _alertId;
  String? _currentAddress;
  String? _destinationAddress;
  List<RouteOption> _routeOptions = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocationWithAddress();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _destAddressController.dispose();
    _destLat.dispose();
    _destLng.dispose();
    _etaMin.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocationWithAddress() async {
    setState(() => _isLoading = true);
    try {
      final position = await _loc.getCurrentPosition();
      if (position != null) {
        _current = position;
        
        // Get address from coordinates
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude, 
            position.longitude
          );
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _currentAddress = '${place.street}, ${place.locality}, ${place.postalCode}';
          }
        } catch (e) {
          _currentAddress = 'Address unavailable';
        }
        
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e'))
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchDestination() async {
    final address = _destAddressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination address'))
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        _destLat.text = location.latitude.toString();
        _destLng.text = location.longitude.toString();
        _destinationAddress = address;
        
        // Generate route options
        await _generateRouteOptions(location.latitude, location.longitude);
        
        setState(() => _showRouteOptions = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find location. Please try a different address.'))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching location: $e'))
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateRouteOptions(double destLat, double destLng) async {
    if (_current == null) return;
    
    // In a real app, you would call a routing API here
    // For demo purposes, we'll generate mock route options
    
    // Calculate straight-line distance for reference
    final directDistance = Geolocator.distanceBetween(
      _current!.latitude, _current!.longitude, destLat, destLng
    );
    
    // Create mock route options with varying safety scores
    _routeOptions = [
      RouteOption(
        name: 'Safest Route',
        description: 'Well-lit streets with high pedestrian activity',
        durationMinutes: (directDistance / 50).round() + 5, // Slightly longer
        safetyScore: 9.2,
        isRecommended: true,
      ),
      RouteOption(
        name: 'Fastest Route',
        description: 'Direct path, some sections may have less visibility',
        durationMinutes: (directDistance / 60).round(),
        safetyScore: 7.5,
      ),
      RouteOption(
        name: 'Alternative Route',
        description: 'Passes through monitored areas and main streets',
        durationMinutes: (directDistance / 45).round() + 3,
        safetyScore: 8.7,
      ),
    ];
  }

  Future<void> _startTrip() async {
    final lat = double.tryParse(_destLat.text.trim());
    final lng = double.tryParse(_destLng.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid destination lat/lng')));
      return;
    }

    final eta = int.tryParse(_etaMin.text.trim()) ?? 30;
    _deadline = DateTime.now().add(Duration(minutes: eta));

    _start = await _loc.getCurrentPosition();
    if (_start == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location unavailable')));
      return;
    }

    // Send initial trip alert (non-SOS) to contacts
    try {
      final res = await _alerts.startSosSession(
        position: _start,
        customMessage: 'Starting a monitored trip to ${_destinationAddress ?? "$lat,$lng"}. I will arrive in about $eta minutes. I\'ll be auto-checked if I deviate or arrive late.'
      );
      _alertId = res.alertId;
    } catch (_) {}

    setState(() {
      _active = true;
      _showRouteOptions = false;
      _status = 'Trip started';
    });

    _sub?.cancel();
    _sub = _loc.watchPosition().listen((p) {
      _current = p;
      final dist = Geolocator.distanceBetween(p.latitude, p.longitude, lat, lng);
      _minDistToDest = _minDistToDest == null ? dist : math.min(_minDistToDest!, dist);

      final offRoute = _isOffRoute(_start!, lat, lng, p);
      String s = 'Distance to destination: ${dist.toStringAsFixed(0)} m';
      if (offRoute) s += ' • Off route';
      if (DateTime.now().isAfter(_deadline!)) s += ' • Late';
      setState(() => _status = s);

      if (offRoute || DateTime.now().isAfter(_deadline!)) {
        _sendDeviationAlert(dist, offRoute);
      }

      if (dist < 50) {
        _finishTrip(arrived: true);
      }
    });
  }

  bool _isOffRoute(Position start, double destLat, double destLng, Position point) {
    // Equirectangular projection for small distances
    const R = 6371000.0; // meters
    final lat0 = start.latitude * math.pi / 180;
    final x1 = (destLng - start.longitude) * math.pi / 180 * math.cos(lat0) * R;
    final y1 = (destLat - start.latitude) * math.pi / 180 * R;
    final x = (point.longitude - start.longitude) * math.pi / 180 * math.cos(lat0) * R;
    final y = (point.latitude - start.latitude) * math.pi / 180 * R;

    final segLen2 = x1 * x1 + y1 * y1;
    if (segLen2 == 0) return false;
    final t = ((x * x1 + y * y1) / segLen2).clamp(0.0, 1.0);
    final projX = t * x1;
    final projY = t * y1;
    final dx = x - projX;
    final dy = y - projY;
    final crossTrack = math.sqrt(dx * dx + dy * dy); // meters from path
    return crossTrack > 300; // 300m off the straight route
  }

  Future<void> _sendDeviationAlert(double dist, bool offRoute) async {
    if (_alertId != null) {
      try {
        await _alerts.updateLiveLocation(_alertId!, _current!);
      } catch (_) {}
    }
    try {
      await _alerts.startSosSession(
        position: _current,
        customMessage: offRoute
            ? 'Alert: I appear to be off my selected route.'
            : 'Alert: I have not reached my destination in time (current distance ${dist.toStringAsFixed(0)} m).',
      );
    } catch (_) {}
  }

  Future<void> _finishTrip({bool arrived = false}) async {
    await _sub?.cancel();
    setState(() {
      _active = false;
      _status = arrived ? 'Arrived at destination.' : 'Trip ended.';
    });
    if (_alertId != null) {
      try {
        await _alerts.closeSosSession(_alertId!, position: _current);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Route Guard')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current location card
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.my_location, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Your Current Location', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_current != null) ...[
                          Text(_currentAddress ?? 'Address unavailable', 
                            style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 4),
                          Text('GPS: ${_current!.latitude.toStringAsFixed(5)}, ${_current!.longitude.toStringAsFixed(5)}',
                            style: theme.textTheme.bodySmall),
                        ] else
                          const Text('Location unavailable'),
                      ],
                    ),
                  ),
                ),
                
                // Destination input
                if (!_active) ...[
                  Text('Enter Destination', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _destAddressController,
                    decoration: InputDecoration(
                      labelText: 'Destination Address',
                      hintText: 'Enter street, city, etc.',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _searchDestination,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Advanced options (collapsed by default)
                  ExpansionTile(
                    title: const Text('Advanced Options'),
                    initiallyExpanded: false,
                    children: [
                      Row(
                        children: [
                          Expanded(child: TextField(
                            controller: _destLat, 
                            keyboardType: TextInputType.number, 
                            decoration: const InputDecoration(labelText: 'Dest Latitude')
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(
                            controller: _destLng, 
                            keyboardType: TextInputType.number, 
                            decoration: const InputDecoration(labelText: 'Dest Longitude')
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 140, 
                        child: TextField(
                          controller: _etaMin, 
                          keyboardType: TextInputType.number, 
                          decoration: const InputDecoration(labelText: 'ETA (minutes)')
                        )
                      ),
                    ],
                  ),
                ],
                
                // Route options
                if (_showRouteOptions && !_active) ...[
                  const SizedBox(height: 24),
                  Text('Suggested Routes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...List.generate(_routeOptions.length, (index) {
                    final route = _routeOptions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: route.isRecommended 
                        ? theme.colorScheme.primaryContainer 
                        : null,
                      child: InkWell(
                        onTap: _startTrip,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.directions, 
                                    color: route.isRecommended 
                                      ? theme.colorScheme.primary 
                                      : null
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    route.name, 
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: route.isRecommended 
                                        ? FontWeight.bold 
                                        : null
                                    )
                                  ),
                                  if (route.isRecommended) ...[
                                    const SizedBox(width: 8),
                                    Chip(
                                      label: const Text('RECOMMENDED'),
                                      backgroundColor: theme.colorScheme.primary,
                                      labelStyle: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                        fontSize: 10,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(route.description),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.timer, size: 16, color: theme.colorScheme.secondary),
                                  const SizedBox(width: 4),
                                  Text('${route.durationMinutes} min'),
                                  const SizedBox(width: 16),
                                  Icon(Icons.shield, size: 16, color: theme.colorScheme.secondary),
                                  const SizedBox(width: 4),
                                  Text('Safety: ${route.safetyScore}/10'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                
                // Active trip status
                if (_active) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.directions_walk, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Trip in Progress', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_status ?? '—', style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 8),
                          if (_current != null)
                            Text('Current: ${_current!.latitude.toStringAsFixed(5)}, ${_current!.longitude.toStringAsFixed(5)}'),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _finishTrip(arrived: false),
                              icon: const Icon(Icons.stop_circle),
                              label: const Text('END TRIP'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                
                // Action buttons
                if (!_active && !_showRouteOptions) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _searchDestination,
                      icon: const Icon(Icons.search),
                      label: const Text('SEARCH DESTINATION'),
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
  }
}
