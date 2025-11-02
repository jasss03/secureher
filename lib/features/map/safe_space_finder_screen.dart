import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import 'dart:developer' as developer;

class SafeSpaceFinderScreen extends StatefulWidget {
  const SafeSpaceFinderScreen({super.key});

  @override
  State<SafeSpaceFinderScreen> createState() => _SafeSpaceFinderScreenState();
}

class _SafeSpaceFinderScreenState extends State<SafeSpaceFinderScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _mapInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay getting location to ensure proper initialization
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _getCurrentLocation();
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController?.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _mapController != null) {
      // Refresh map when app is resumed
      setState(() {
        _mapInitialized = false;
      });
      _mapController!.setMapStyle("[]"); // Reset map style
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    
    try {
      setState(() => _isLoading = true);
      
      // Use the location service to handle permissions and get position
      final position = await _locationService.getCurrentPosition();
      
      if (!mounted) return;
      
      if (position != null) {
        developer.log('Position obtained: ${position.latitude}, ${position.longitude}');
        setState(() {
          _currentPosition = position;
          _isLoading = false;
          _addMarker(position);
        });
        
        // Update camera position if map controller exists
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(position.latitude, position.longitude),
                zoom: 15,
              ),
            ),
          );
        }
      } else {
        developer.log('Could not get current position');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get your current location. Using default location.')),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      developer.log('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _addMarker(Position position) {
    if (!mounted) return;
    
    setState(() {
      _markers.clear(); // Clear existing markers
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Default position (San Francisco)
    const LatLng defaultPosition = LatLng(37.7749, -122.4194);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Space Finder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: 'My Location',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : defaultPosition, // Default position if location not available
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            markers: _markers,
            onMapCreated: (GoogleMapController controller) {
              setState(() {
                _mapController = controller;
                _mapInitialized = true;
              });
              
              // Refresh map when created
              if (_currentPosition != null) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted && _mapController != null) {
                    _mapController!.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          zoom: 15,
                        ),
                      ),
                    );
                  }
                });
              }
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_mapController != null) {
            final target = _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : defaultPosition;
                
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: target,
                  zoom: 15,
                ),
              ),
            );
          }
        },
        child: const Icon(Icons.center_focus_strong),
      ),
    );
  }
}
