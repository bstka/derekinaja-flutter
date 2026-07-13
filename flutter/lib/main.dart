import 'dart:async';
import 'dart:math';

import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'CHANGE_THIS',
    anonKey: 'CHANGE_THIS',
  );
  runApp(const MainApp());
}

final supabase = Supabase.instance.client;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: UberCloneMainScreen(),
      ),
    );
  }
}

enum AppState {
  choosingLocation,
  confirmingFare,
  waitingForPickup,
  riding,
  postRide,
}

enum TruckType {
  premiumLowBed,
  hookTow,
}

extension TruckTypeLabel on TruckType {
  String get label {
    switch (this) {
      case TruckType.premiumLowBed:
        return 'Premium Low Bed';
      case TruckType.hookTow:
        return 'Hook Tow';
    }
  }

  String get description {
    switch (this) {
      case TruckType.premiumLowBed:
        return 'Flatbed transport for cars, sedans & SUVs';
      case TruckType.hookTow:
        return 'Standard hook & chain tow for quick jobs';
    }
  }

  IconData get icon {
    switch (this) {
      case TruckType.premiumLowBed:
        return Icons.local_shipping;
      case TruckType.hookTow:
        return Icons.build;
    }
  }
}

enum RideStatus {
  picking_up,
  riding,
  completed,
}

class Ride {
  final String id;
  final String driverId;
  final String passengerId;
  final int fare;
  final RideStatus status;

  Ride({
    required this.id,
    required this.driverId,
    required this.passengerId,
    required this.fare,
    required this.status,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'],
      driverId: json['driver_id'],
      passengerId: json['passenger_id'],
      fare: json['fare'],
      status: RideStatus.values
          .firstWhere((e) => e.toString().split('.').last == json['status']),
    );
  }
}

class Driver {
  final String id;
  final String model;
  final String number;
  final bool isAvailable;
  final LatLng location;

  Driver({
    required this.id,
    required this.model,
    required this.number,
    required this.isAvailable,
    required this.location,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'],
      model: json['model'],
      number: json['number'],
      isAvailable: json['is_available'],
      location: LatLng(json['latitude'], json['longitude']),
    );
  }
}

class UberCloneMainScreen extends StatefulWidget {
  const UberCloneMainScreen({super.key});

  @override
  UberCloneMainScreenState createState() => UberCloneMainScreenState();
}

class UberCloneMainScreenState extends State<UberCloneMainScreen> {
  AppState _appState = AppState.choosingLocation;
  GoogleMapController? _mapController;
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 14.0,
  );

  LatLng? _selectedDestination;
  LatLng? _currentLocation;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  /// Fare in cents
  int? _fare;

  /// Selected towing truck type for this request
  TruckType _selectedTruckType = TruckType.premiumLowBed;
  StreamSubscription<dynamic>? _driverSubscription;
  StreamSubscription<dynamic>? _rideSubscription;
  Driver? _driver;

  LatLng? _previousDriverLocation;
  BitmapDescriptor? _pinIcon;
  BitmapDescriptor? _carIcon;

  @override
  void initState() {
    super.initState();
    _signInIfNotSignedIn();
    _checkLocationPermission();
    _loadIcons();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  Future<void> _signInIfNotSignedIn() async {
    if (supabase.auth.currentSession == null) {
      try {
        await supabase.auth.signInAnonymously();
        debugPrint('Signed in anonymously: ${supabase.auth.currentUser?.id}');
      } catch (e) {
        debugPrint('Sign-in error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _askForLocationPermission();
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _askForLocationPermission();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return _askForLocationPermission();
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    _getCurrentLocation();
  }

  /// Shows a modal to ask for location permission.
  Future<void> _askForLocationPermission() async {
    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Location Permission'),
            content: const Text(
                'This app needs location permission to work properly.'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  SystemChannels.platform.invokeMethod('SystemNavigator.pop');
                },
                child: const Text('Close App'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Geolocator.openLocationSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          );
        });
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _initialCameraPosition = CameraPosition(
          target: _currentLocation!,
          zoom: 14.0,
        );
      });
      _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(_initialCameraPosition));
    } catch (e) {
      debugPrint('Location error: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error occured while getting the current location')));
      }
    }
  }

  /// Loads the icon images used for markers.
  /// Wrapped in try/catch so a missing asset doesn't silently kill
  /// downstream marker rendering (BitmapDescriptor.asset can throw
  /// if the asset isn't declared in pubspec.yaml or the path is wrong).
  Future<void> _loadIcons() async {
    const imageConfiguration = ImageConfiguration(size: Size(48, 48));
    try {
      _pinIcon = await BitmapDescriptor.asset(
          imageConfiguration, 'assets/images/pin.png');
      _carIcon = await BitmapDescriptor.asset(
        imageConfiguration,
        'assets/images/car.png',
      );
      debugPrint(
          'Icons loaded: pin=${_pinIcon != null}, car=${_carIcon != null}');
    } catch (e) {
      debugPrint('Icon load failed, will fall back to default markers: $e');
    }
  }

  void _goToNextState() {
    debugPrint("Current State: $_appState");
    setState(() {
      // Check if we are at the last state to avoid index out of bounds
      if (_appState.index < AppState.values.length - 1) {
        _appState = AppState.values[_appState.index + 1];
      } else {
        // If we finished the last state, go back to the start
        _appState = AppState.choosingLocation;
      }
    });
    debugPrint("New State: $_appState");
  }

  void _onCameraMove(CameraPosition position) {
    if (_appState == AppState.choosingLocation) {
      _selectedDestination = position.target;
    }
  }

  Future<void> _confirmLocation() async {
    if (_selectedDestination != null && _currentLocation != null) {
      try {
        final response = await supabase.functions.invoke(
          'route',
          body: {
            'origin': {
              'latitude': _currentLocation!.latitude,
              'longitude': _currentLocation!.longitude,
            },
            'destination': {
              'latitude': _selectedDestination!.latitude,
              'longitude': _selectedDestination!.longitude,
            },
          },
        );

        final data = response.data as Map<String, dynamic>;
        final coordinates = data['legs'][0]['polyline']['geoJsonLinestring']
        ['coordinates'] as List<dynamic>;
        final duration = parseDuration(data['duration'] as String);
        _fare = ((duration.inMinutes * 40)).ceil();

        final List<LatLng> polylineCoordinates = coordinates.map((coord) {
          return LatLng(coord[1], coord[0]);
        }).toList();

        setState(() {
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: polylineCoordinates,
            color: Colors.black,
            width: 5,
          ));

          _markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: _selectedDestination!,
            icon: _pinIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ));
        });

        LatLngBounds bounds = LatLngBounds(
          southwest: LatLng(
            polylineCoordinates
                .map((e) => e.latitude)
                .reduce((a, b) => a < b ? a : b),
            polylineCoordinates
                .map((e) => e.longitude)
                .reduce((a, b) => a < b ? a : b),
          ),
          northeast: LatLng(
            polylineCoordinates
                .map((e) => e.latitude)
                .reduce((a, b) => a > b ? a : b),
            polylineCoordinates
                .map((e) => e.longitude)
                .reduce((a, b) => a > b ? a : b),
          ),
        );
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));

        _goToNextState();
      } catch (e) {
        debugPrint('Destination Error: ${e.toString()}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }

  /// Finds a nearby driver
  ///
  /// When a driver is found, it subscribes to the driver's location and ride status.
  Future<void> _findDriver() async {
    try {
      final response = await supabase.rpc('find_driver', params: {
        'origin':
        'POINT(${_currentLocation!.longitude} ${_currentLocation!.latitude})',
        'destination':
        'POINT(${_selectedDestination!.longitude} ${_selectedDestination!.latitude})',
        'fare': _fare,
      }) as List<dynamic>;

      debugPrint('find_driver raw response: $response');

      if (response.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No driver found. Please try again later.')),
          );
        }
        return;
      }

      // Defensive parsing: bail out loudly instead of throwing an
      // unhandled cast error if the RPC's return shape doesn't match
      // what we expect (e.g. different key names, null values).
      final firstResult = response.first as Map<String, dynamic>;
      final driverId = firstResult['driver_id'] as String?;
      final rideId = firstResult['ride_id'] as String?;

      if (driverId == null || rideId == null) {
        debugPrint('find_driver returned unexpected shape: $firstResult');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Driver match failed — unexpected response from server')),
          );
        }
        return;
      }

      debugPrint('Matched driverId=$driverId rideId=$rideId');

      _driverSubscription = supabase
          .from('drivers')
          .stream(primaryKey: ['id'])
          .eq('id', driverId)
          .listen((List<Map<String, dynamic>> data) {
        debugPrint('Driver stream update: $data');
        if (data.isNotEmpty) {
          setState(() {
            _driver = Driver.fromJson(data[0]);
          });
          _updateDriverMarker(_driver!);
          _adjustMapView(
              target: _appState == AppState.waitingForPickup
                  ? _currentLocation!
                  : _selectedDestination!);
        }
      }, onError: (e) {
        debugPrint('Driver stream ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Driver stream error: $e')),
          );
        }
      });

      _rideSubscription = supabase
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('id', rideId)
          .listen((List<Map<String, dynamic>> data) {
        debugPrint('Ride stream update: $data');
        if (data.isNotEmpty) {
          setState(() {
            final ride = Ride.fromJson(data[0]);
            if (ride.status == RideStatus.riding &&
                _appState != AppState.riding) {
              _appState = AppState.riding;
            } else if (ride.status == RideStatus.completed &&
                _appState != AppState.postRide) {
              _appState = AppState.postRide;
              _cancelSubscriptions();
              _showCompletionModal();
            }
          });
        }
      }, onError: (e) {
        debugPrint('Ride stream ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ride stream error: $e')),
          );
        }
      });

      _goToNextState();
    } catch (e) {
      debugPrint('_findDriver error: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _updateDriverMarker(Driver driver) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == 'driver');

      double rotation = 0;
      if (_previousDriverLocation != null) {
        rotation =
            _calculateRotation(_previousDriverLocation!, driver.location);
      }

      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driver.location,
        // Fall back to a default marker instead of force-unwrapping.
        // Previously `icon: _carIcon!` would throw silently inside this
        // stream callback if the asset failed to load, so no driver
        // marker (or anything else in this callback) would ever render.
        icon: _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        rotation: rotation,
      ));

      _previousDriverLocation = driver.location;
    });
  }

  void _adjustMapView({required LatLng target}) {
    if (_driver != null && _selectedDestination != null) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          min(_driver!.location.latitude, target.latitude),
          min(_driver!.location.longitude, target.longitude),
        ),
        northeast: LatLng(
          max(_driver!.location.latitude, target.latitude),
          max(_driver!.location.longitude, target.longitude),
        ),
      );
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }

  double _calculateRotation(LatLng start, LatLng end) {
    double latDiff = end.latitude - start.latitude;
    double lngDiff = end.longitude - start.longitude;
    double angle = atan2(lngDiff, latDiff);
    return angle * 180 / pi;
  }

  void _cancelSubscriptions() {
    _driverSubscription?.cancel();
    _rideSubscription?.cancel();
  }

  /// Shows a modal to indicate that the ride has been completed.
  void _showCompletionModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Ride Completed'),
          content: const Text(
              'Thank you for using our service! We hope you had a great ride.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetAppState();
              },
            ),
          ],
        );
      },
    );
  }

  void _resetAppState() {
    setState(() {
      _appState = AppState.choosingLocation;
      _selectedDestination = null;
      _driver = null;
      _fare = null;
      _polylines.clear();
      _markers.clear();
      _previousDriverLocation = null;
    });
    _getCurrentLocation();
  }

  String _getAppBarTitle() {
    switch (_appState) {
      case AppState.choosingLocation:
        return 'Choose Location';
      case AppState.confirmingFare:
        return 'Confirm Fare';
      case AppState.waitingForPickup:
        return 'Waiting for Pickup';
      case AppState.riding:
        return 'On the Way';
      case AppState.postRide:
        return 'Ride Completed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
      ),
      body: Stack(
        children: [
          _currentLocation == null
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            myLocationEnabled: true,
            onCameraMove: _onCameraMove,
            polylines: _polylines,
            markers: _markers,
          ),
          if (_appState == AppState.choosingLocation)
            Center(
              child: Image.asset(
                'assets/images/center-pin.png',
                width: 96,
                height: 96,
              ),
            ),
        ],
      ),
      floatingActionButton: _appState == AppState.choosingLocation
          ? FloatingActionButton.extended(
        onPressed: _confirmLocation,
        label: const Text('Confirm Destination'),
        icon: const Icon(Icons.check),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomSheet: _appState == AppState.confirmingFare ||
          _appState == AppState.waitingForPickup
          ? Container(
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.all(16)
            .copyWith(bottom: 16 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              spreadRadius: 5,
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_appState == AppState.confirmingFare) ...[
              Text('Confirm Fare',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Select Truck Type',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...TruckType.values.map((type) {
                final bool isSelected = _selectedTruckType == type;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    leading: Icon(type.icon),
                    title: Text(type.label),
                    subtitle: Text(type.description),
                    trailing: Radio<TruckType>(
                      value: type,
                      groupValue: _selectedTruckType,
                      onChanged: (value) {
                        setState(() {
                          _selectedTruckType = value!;
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        _selectedTruckType = type;
                      });
                    },
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                  'Estimated fare: ${NumberFormat.currency(
                    symbol:
                    '\$', // You can change this to your preferred currency symbol
                    decimalDigits: 2,
                  ).format(_fare! / 100)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _findDriver,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Confirm Fare'),
              ),
            ],
            if (_appState == AppState.waitingForPickup &&
                _driver != null) ...[
              Text('Your Driver',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Truck Type: ${_selectedTruckType.label}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Car: ${_driver!.model}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Plate Number: ${_driver!.number}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text(
                  'Your driver is on the way. Please wait at the pickup location.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ]
          ],
        ),
      )
          : const SizedBox.shrink(),
    );
  }
}