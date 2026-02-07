import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;

const _mapboxAccessToken = String.fromEnvironment("MAPBOX_ACCESS_TOKEN");

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mapboxAccessToken.isNotEmpty) {
    mbx.MapboxOptions.setAccessToken(_mapboxAccessToken);
  }
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Tracker',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: MapScreen(tokenMissing: _mapboxAccessToken.isEmpty),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.tokenMissing});

  final bool tokenMissing;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const GeoPoint _fallbackCenter = GeoPoint(11.2588, 75.7804);

  final List<Bus> _buses = [];
  final Random _random = Random();
  final List<BusStop> _stops = [];

  mbx.MapboxMap? _mapboxMap;
  mbx.PointAnnotationManager? _busAnnotationManager;
  mbx.PointAnnotationManager? _stopAnnotationManager;
  final Map<String, Bus> _busByAnnotationId = {};

  GeoPoint? _userLocation;
  Timer? _movementTimer;
  bool _locationDenied = false;
  bool _mapReady = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bus Tracker"),
        actions: [
          IconButton(
            tooltip: "Recenter",
            onPressed: _userLocation == null
                ? null
                : () {
                    _mapboxMap?.setCamera(
                      mbx.CameraOptions(
                        center: _toPoint(_userLocation!),
                        zoom: 14,
                      ),
                    );
                  },
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          mbx.MapWidget(
            key: const ValueKey("mapWidget"),
            styleUri: mbx.MapboxStyles.STANDARD,
            textureView: true,
            cameraOptions: mbx.CameraOptions(
              center: _toPoint(_fallbackCenter),
              zoom: 13,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleLoaded(),
          ),
          if (_locationDenied)
            const Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _LocationBanner(),
            ),
          if (widget.tokenMissing)
            const Positioned(
              left: 16,
              right: 16,
              top: 72,
              child: _TokenBanner(),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    _busAnnotationManager?.deleteAll();
    _stopAnnotationManager?.deleteAll();
    super.dispose();
  }

  void _onMapCreated(mbx.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    if (_mapboxMap == null) return;
    _busAnnotationManager = await _mapboxMap!.annotations.createPointAnnotationManager();
    _stopAnnotationManager = await _mapboxMap!.annotations.createPointAnnotationManager();
    _busAnnotationManager?.tapEvents(onTap: (annotation) {
      final bus = _busByAnnotationId[annotation.id];
      if (bus != null) {
        _openBusDetails(bus);
      }
    });
    _mapReady = true;
    await _updateLocationComponent();
    if (_userLocation != null) {
      await _mapboxMap!.setCamera(
        mbx.CameraOptions(center: _toPoint(_userLocation!), zoom: 14),
      );
    }
    await _rebuildAnnotations();
  }

  Future<void> _onStyleLoaded() async {
    if (_mapReady) {
      await _rebuildAnnotations();
    }
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    LocationPermission granted = permission;
    if (permission == LocationPermission.denied) {
      granted = await Geolocator.requestPermission();
    }

    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      setState(() {
        _locationDenied = true;
      });
      _seedMockData(_fallbackCenter);
      return;
    }

    final position = await Geolocator.getCurrentPosition(
    );
    _userLocation = GeoPoint(position.latitude, position.longitude);
    if (mounted) {
      _seedMockData(_userLocation!);
      await _updateLocationComponent();
      if (_mapboxMap != null) {
        await _mapboxMap!.setCamera(
          mbx.CameraOptions(center: _toPoint(_userLocation!), zoom: 14),
        );
      }
      setState(() {});
    }
  }

  void _seedMockData(GeoPoint center) {
    _stops
      ..clear()
      ..addAll(_generateMockStops(center));
    _buses
      ..clear()
      ..addAll(_generateMockBuses(center));
    _rebuildAnnotations();
    _movementTimer?.cancel();
    _movementTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _moveBuses(center);
      _rebuildAnnotations();
    });
  }

  List<BusStop> _generateMockStops(GeoPoint center) {
    return [
      BusStop(name: "Central Stop", location: _offset(center, 0.004, 0.002)),
      BusStop(name: "Market Stop", location: _offset(center, -0.003, 0.004)),
      BusStop(name: "River Stop", location: _offset(center, 0.002, -0.0035)),
      BusStop(name: "Tech Park Stop", location: _offset(center, -0.004, -0.002)),
    ];
  }

  List<Bus> _generateMockBuses(GeoPoint center) {
    return List.generate(6, (index) {
      final jitter = _randomPointWithinKm(center, 1);
      return Bus(
        id: "B${index + 1}",
        name: "Bus ${index + 1}",
        route: "Route ${index + 3}",
        position: jitter,
        speedKmh: 20 + _random.nextInt(25),
        headingDegrees: _random.nextDouble() * 360,
      );
    });
  }

  void _moveBuses(GeoPoint center) {
    for (final bus in _buses) {
      final distanceMeters = bus.speedKmh * 1000 / 3600 * 3;
      bus.headingDegrees = (bus.headingDegrees + _random.nextDouble() * 20 - 10) % 360;
      bus.position = _movePoint(bus.position, bus.headingDegrees, distanceMeters);

      final distanceToCenter = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        bus.position.latitude,
        bus.position.longitude,
      );
      if (distanceToCenter > 1000) {
        bus.headingDegrees = (_bearing(bus.position, center) + 180) % 360;
        bus.position = _movePoint(bus.position, bus.headingDegrees, 120);
      }
    }
  }

  Future<void> _rebuildAnnotations() async {
    if (!_mapReady || _busAnnotationManager == null || _stopAnnotationManager == null) {
      return;
    }

    await _busAnnotationManager!.deleteAll();
    await _stopAnnotationManager!.deleteAll();
    _busByAnnotationId.clear();

    for (final stop in _stops) {
      await _stopAnnotationManager!.create(
        mbx.PointAnnotationOptions(
          geometry: _toPoint(stop.location),
          iconImage: "marker-15",
          iconColor: Colors.green.value,
          textField: stop.name,
          textSize: 12.0,
          textOffset: [0.0, 1.4],
        ),
      );
    }

    for (final bus in _buses) {
      final annotation = await _busAnnotationManager!.create(
        mbx.PointAnnotationOptions(
          geometry: _toPoint(bus.position),
          iconImage: "car-15",
          iconColor: Colors.orange.value,
          textField: bus.name,
          textSize: 12.0,
          textOffset: [0.0, 1.6],
        ),
      );
      _busByAnnotationId[annotation.id] = bus;
    }
  }

  void _openBusDetails(Bus bus) {
    if (!mounted) return;
    final userLocation = _userLocation;
    final nearestStop = _nearestStop(bus.position);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BusDetailsScreen(
          bus: bus,
          userLocation: userLocation,
          nearestStop: nearestStop,
        ),
      ),
    );
  }

  BusStop _nearestStop(GeoPoint from) {
    return _stops.reduce((a, b) {
      final distanceA = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        a.location.latitude,
        a.location.longitude,
      );
      final distanceB = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        b.location.latitude,
        b.location.longitude,
      );
      return distanceA <= distanceB ? a : b;
    });
  }

  GeoPoint _offset(GeoPoint origin, double latOffset, double lngOffset) {
    return GeoPoint(origin.latitude + latOffset, origin.longitude + lngOffset);
  }

  GeoPoint _randomPointWithinKm(GeoPoint center, double km) {
    final radius = km * 1000;
    final distance = _random.nextDouble() * radius;
    final angle = _random.nextDouble() * 2 * pi;
    return _movePoint(center, angle * 180 / pi, distance);
  }

  GeoPoint _movePoint(GeoPoint from, double bearingDegrees, double distanceMeters) {
    const earthRadius = 6371000.0;
    final bearing = bearingDegrees * pi / 180;
    final lat1 = from.latitude * pi / 180;
    final lon1 = from.longitude * pi / 180;
    final lat2 = asin(
      sin(lat1) * cos(distanceMeters / earthRadius) +
          cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearing),
    );
    final lon2 = lon1 + atan2(
      sin(bearing) * sin(distanceMeters / earthRadius) * cos(lat1),
      cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2),
    );
    return GeoPoint(lat2 * 180 / pi, lon2 * 180 / pi);
  }

  double _bearing(GeoPoint from, GeoPoint to) {
    final lat1 = from.latitude * pi / 180;
    final lon1 = from.longitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final lon2 = to.longitude * pi / 180;
    final dLon = lon2 - lon1;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  mbx.Point _toPoint(GeoPoint point) {
    return mbx.Point(coordinates: mbx.Position(point.longitude, point.latitude));
  }

  Future<void> _updateLocationComponent() async {
    if (_mapboxMap == null) return;
    await _mapboxMap!.location.updateSettings(
      mbx.LocationComponentSettings(
        enabled: _userLocation != null,
        pulsingEnabled: true,
        pulsingColor: Colors.indigo.value,
      ),
    );
  }
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class Bus {
  Bus({
    required this.id,
    required this.name,
    required this.route,
    required this.position,
    required this.speedKmh,
    required this.headingDegrees,
  });

  final String id;
  final String name;
  final String route;
  GeoPoint position;
  int speedKmh;
  double headingDegrees;
}

class BusStop {
  const BusStop({required this.name, required this.location});

  final String name;
  final GeoPoint location;
}

class BusDetailsScreen extends StatelessWidget {
  const BusDetailsScreen({
    super.key,
    required this.bus,
    required this.userLocation,
    required this.nearestStop,
  });

  final Bus bus;
  final GeoPoint? userLocation;
  final BusStop nearestStop;

  @override
  Widget build(BuildContext context) {
    final distanceToStop = Geolocator.distanceBetween(
      bus.position.latitude,
      bus.position.longitude,
      nearestStop.location.latitude,
      nearestStop.location.longitude,
    );
    final etaMinutes = (distanceToStop / (bus.speedKmh * 1000 / 60)).ceil();
    final distanceToUser = userLocation == null
        ? null
        : Geolocator.distanceBetween(
            bus.position.latitude,
            bus.position.longitude,
            userLocation!.latitude,
            userLocation!.longitude,
          );

    return Scaffold(
      appBar: AppBar(title: Text(bus.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _InfoTile(title: "Route", value: bus.route),
          _InfoTile(
            title: "Current location",
            value:
                "${bus.position.latitude.toStringAsFixed(5)}, ${bus.position.longitude.toStringAsFixed(5)}",
          ),
          if (distanceToUser != null)
            _InfoTile(
              title: "Distance to you",
              value: "${(distanceToUser / 1000).toStringAsFixed(2)} km",
            ),
          const SizedBox(height: 12),
          _InfoTile(title: "Nearest stop", value: nearestStop.name),
          _InfoTile(
            title: "Stop location",
            value:
                "${nearestStop.location.latitude.toStringAsFixed(5)}, ${nearestStop.location.longitude.toStringAsFixed(5)}",
          ),
          _InfoTile(
            title: "Expected arrival",
            value: "$etaMinutes min",
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "This bus is moving inside a 1 km radius near you. Arrival time is estimated based on its current speed.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.location_off,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Location permission denied. Using mock location.",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenBanner extends StatelessWidget {
  const _TokenBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Missing Mapbox access token. Run with --dart-define MAPBOX_ACCESS_TOKEN=...",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
