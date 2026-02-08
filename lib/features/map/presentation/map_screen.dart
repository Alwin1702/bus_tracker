import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../bus_details/presentation/bus_details_screen.dart';
import '../../stops/presentation/stop_timeline_screen.dart';
import 'controllers/bus_tracker_controller.dart';
import '../../map/models/bus.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  mbx.MapboxMap? _mapboxMap;
  mbx.PointAnnotationManager? _busAnnotationManager;
  mbx.CircleAnnotationManager? _stopAnnotationManager;
  mbx.CircleAnnotationManager? _userLocationAnnotationManager;
  mbx.PolylineAnnotationManager? _routeAnnotationManager;
  final Map<String, Bus> _busByAnnotationId = {};
  final Map<String, BusStop> _stopByAnnotationId = {};
  final Map<String, mbx.PointAnnotation> _busAnnotationByBusId = {};
  bool _routesReady = false;
  bool _stopsReady = false;
  int _routesRevision = -1;
  bool _mapReady = false;
  GeoPoint? _userLocation;
  mbx.CircleAnnotation? _userPulseAnnotation;
  mbx.CircleAnnotation? _userDotAnnotation;
  double _pulsePhase = 0.0;
  Timer? _pulseTimer;
  bool _busIconLoaded = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _busAnnotationManager?.deleteAll();
    _stopAnnotationManager?.deleteAll();
    _routeAnnotationManager?.deleteAll();
    _userLocationAnnotationManager?.deleteAll();
    _pulseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<BusTrackerController>(
        builder: (context, controller, _) {
          if (_routesRevision != controller.routesRevision) {
            _routesRevision = controller.routesRevision;
            _routesReady = false;
          }
          _scheduleAnnotationSync();
          _scheduleRouteSync(controller);
          return Stack(
            children: [
              mbx.MapWidget(
                key: const ValueKey('BUSIO'),
                styleUri: mbx.MapboxStyles.STANDARD,
                cameraOptions: mbx.CameraOptions(
                  center: _toPoint(BusTrackerController.defaultCenter),
                  zoom: 14,
                ),
                onMapCreated: (mapboxMap) {
                  _mapboxMap = mapboxMap;
                  _initializeAnnotations(controller);
                },
                onStyleLoadedListener: (_) => _onStyleLoaded(controller),
              ),
              Positioned(top: 56, left: 20, right: 20, child: _MapHeader()),
              Positioned(
                bottom: 120,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _IconPillButton(
                      icon: Icons.refresh,
                      label: 'Reload',
                      onPressed: () => _syncAnnotations(controller),
                    ),
                    const SizedBox(height: 12),
                    _IconPillButton(
                      icon: Icons.my_location,
                      label: 'Center',
                      onPressed: _recenterToUser,
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: FloatingActionButton.extended(
                    elevation: 25,
                    isExtended: true,
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    heroTag: 'nearbyBusesFab',
                    icon: const Icon(Icons.directions_bus, size: 28),
                    label: const Text('Nearby Buses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: () => _showNearbyBuses(controller),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showNearbyBuses(BusTrackerController controller) {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User location not available yet.')),
      );
      return;
    }

    const double radiusMeters = 2000;
    final origin = _userLocation!;
    final entries = controller.buses
        .map(
          (bus) => _NearbyBus(
            bus: bus,
            distanceMeters: _distanceMeters(origin, bus.position),
          ),
        )
        .where((entry) => entry.distanceMeters <= radiusMeters)
        .toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No nearby buses within 2 km.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final distanceKm = entry.distanceMeters / 1000;
            return ListTile(
              leading: const Icon(Icons.directions_bus),
              title: Text(entry.bus.name),
              subtitle: Text(
                '${entry.bus.boarding} → ${entry.bus.destination} • '
                '${distanceKm.toStringAsFixed(2)} km away',
              ),
              trailing: Text('${entry.bus.speedKmh} km/h'),
              onTap: () {
                Navigator.of(context).pop();
                _openBusDetails(entry.bus, controller);
              },
            );
          },
        );
      },
    );
  }

  double _distanceMeters(GeoPoint a, GeoPoint b) {
    const earthRadius = 6371000.0;
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final haversine =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    final c = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  void _initializeAnnotations(BusTrackerController controller) async {
    if (_mapboxMap == null) return;
    _busAnnotationManager ??=
      await _mapboxMap!.annotations.createPointAnnotationManager();
    _stopAnnotationManager ??=
      await _mapboxMap!.annotations.createCircleAnnotationManager();
    _userLocationAnnotationManager ??=
      await _mapboxMap!.annotations.createCircleAnnotationManager();
    _routeAnnotationManager ??=
      await _mapboxMap!.annotations.createPolylineAnnotationManager();
    await _loadBusIcon();
    _busAnnotationManager?.tapEvents(
      onTap: (annotation) {
        final bus = _busByAnnotationId[annotation.id];
        if (bus != null) {
          _openBusDetails(bus, controller);
        }
      },
    );
    _stopAnnotationManager?.tapEvents(
      onTap: (annotation) {
        final stop = _stopByAnnotationId[annotation.id];
        if (stop != null) {
          _openStopTimeline(stop, controller);
        }
      },
    );
    _mapReady = true;
    _syncAnnotations(controller);
    await _syncRoutes(controller);
    _ensureUserLocationAnnotation();
    if (_userLocation != null) {
      await _mapboxMap!.setCamera(
        mbx.CameraOptions(center: _toPoint(_userLocation!), zoom: 14.5),
      );
    }
  }

  void _scheduleAnnotationSync() {
    if (!_mapReady || _busAnnotationManager == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncAnnotations(context.read<BusTrackerController>());
      }
    });
  }

  void _scheduleRouteSync(BusTrackerController controller) {
    if (!_mapReady || _routeAnnotationManager == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncRoutes(controller);
      }
    });
  }

  Future<void> _syncAnnotations(BusTrackerController controller) async {
    if (!_mapReady || _busAnnotationManager == null) return;
    if (!_busIconLoaded) {
      await _loadBusIcon();
    }
    if (!_stopsReady) {
      await _stopAnnotationManager?.deleteAll();
      _stopByAnnotationId.clear();
      for (final stop in controller.stops) {
        final annotation = await _stopAnnotationManager?.create(
          mbx.CircleAnnotationOptions(
            geometry: _toPoint(stop.location),
            circleColor: Colors.green.toARGB32(),
            circleRadius: 6.0,
            circleStrokeWidth: 2.0,
            circleStrokeColor: Colors.white.toARGB32(),
          ),
        );
        if (annotation != null) {
          _stopByAnnotationId[annotation.id] = stop;
        }
      }
      _stopsReady = true;
    }

    for (final bus in controller.buses) {
      final existing = _busAnnotationByBusId[bus.id];
      if (existing == null) {
        final annotation = await _busAnnotationManager!.create(
          mbx.PointAnnotationOptions(
            geometry: _toPoint(bus.position),
            iconImage: _busIconForHeading(bus.heading),
            iconSize: 0.1,
            iconRotate: bus.heading,
            iconAnchor: mbx.IconAnchor.CENTER,
          ),
        );
        _busAnnotationByBusId[bus.id] = annotation;
        _busByAnnotationId[annotation.id] = bus;
      } else {
        existing.geometry = _toPoint(bus.position);
        existing.iconRotate = bus.heading;
        existing.iconImage = _busIconForHeading(bus.heading);
        await _busAnnotationManager!.update(existing);
        _busByAnnotationId[existing.id] = bus;
      }
    }
  }

  Future<void> _syncRoutes(BusTrackerController controller) async {
    if (_routeAnnotationManager == null || _routesReady) return;
    await _routeAnnotationManager!.deleteAll();
    for (final route in controller.routes) {
      final line = mbx.LineString(
        coordinates: route.points
            .map((point) => mbx.Position(point.longitude, point.latitude))
            .toList(),
      );
      await _routeAnnotationManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: line,
          lineColor: Colors.blue.withOpacity(0.7).toARGB32(),
          lineWidth: 7.0,
        ),
      );
    }
    _routesReady = true;
  }

  void _onStyleLoaded(BusTrackerController controller) {
    _routesReady = false;
    _userDotAnnotation = null;
    _userPulseAnnotation = null;
    _busIconLoaded = false;
    _stopsReady = false;
    _syncAnnotations(controller);
    _syncRoutes(controller);
    _ensureUserLocationAnnotation();
  }

  Future<void> _loadBusIcon() async {
    if (_mapboxMap == null || _busIconLoaded) return;
    try {
      await _addBusStyleImage('bus-left', 'assets/icons/Bus_Left_2.png');
      await _addBusStyleImage('bus-right', 'assets/icons/Bus_Right_2.png');
      _busIconLoaded = true;
    } catch (_) {
      _busIconLoaded = false;
    }
  }

  Future<void> _addBusStyleImage(String id, String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final list = bytes.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(list);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    await _mapboxMap!.style.addStyleImage(
      id,
      1.0,
      mbx.MbxImage(
        width: image.width.toInt(),
        height: image.height.toInt(),
        data: list,
      ),
      false,
      [],
      [],
      null,
    );
  }

  String _busIconForHeading(double heading) {
    final normalized = (heading % 360 + 360) % 360;
    return (normalized > 90 && normalized < 270) ? 'bus-left' : 'bus-right';
  }

  mbx.Point _toPoint(GeoPoint point) {
    return mbx.Point(
      coordinates: mbx.Position(point.longitude, point.latitude),
    );
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    LocationPermission granted = permission;
    if (permission == LocationPermission.denied) {
      granted = await Geolocator.requestPermission();
    }
    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    _userLocation = GeoPoint(position.latitude, position.longitude);
    _ensureUserLocationAnnotation();
    if (_mapboxMap != null) {
      await _mapboxMap!.setCamera(
        mbx.CameraOptions(center: _toPoint(_userLocation!), zoom: 14.5),
      );
    }
  }

  Future<void> _recenterToUser() async {
    await _initLocation();
    if (_userLocation != null && _mapboxMap != null) {
      await _mapboxMap!.setCamera(
        mbx.CameraOptions(center: _toPoint(_userLocation!), zoom: 14.5),
      );
    }
  }

  void _ensureUserLocationAnnotation() {
    if (_userLocationAnnotationManager == null || _userLocation == null) {
      return;
    }
    if (_userDotAnnotation == null) {
      _createUserLocationAnnotations();
      _startPulse();
    } else {
      _updateUserLocationAnnotations();
    }
  }

  Future<void> _createUserLocationAnnotations() async {
    if (_userLocationAnnotationManager == null || _userLocation == null) {
      return;
    }
    _userPulseAnnotation = await _userLocationAnnotationManager!.create(
      mbx.CircleAnnotationOptions(
        geometry: _toPoint(_userLocation!),
        circleColor: AppColors.primary.withOpacity(0.35).toARGB32(),
        circleRadius: 14.0,
      ),
    );
    _userDotAnnotation = await _userLocationAnnotationManager!.create(
      mbx.CircleAnnotationOptions(
        geometry: _toPoint(_userLocation!),
        circleColor: AppColors.primary.toARGB32(),
        circleRadius: 6.0,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.toARGB32(),
      ),
    );
  }

  Future<void> _updateUserLocationAnnotations() async {
    if (_userLocationAnnotationManager == null || _userLocation == null) {
      return;
    }
    if (_userPulseAnnotation != null) {
      _userPulseAnnotation!.geometry = _toPoint(_userLocation!);
      await _userLocationAnnotationManager!.update(_userPulseAnnotation!);
    }
    if (_userDotAnnotation != null) {
      _userDotAnnotation!.geometry = _toPoint(_userLocation!);
      await _userLocationAnnotationManager!.update(_userDotAnnotation!);
    }
  }

  void _startPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _userPulseAnnotation == null) return;
      _pulsePhase += 0.12;
      if (_pulsePhase > 1.0) _pulsePhase -= 1.0;
      final radius = 10.0 + (14.0 * _pulsePhase);
      final opacity = (1.0 - _pulsePhase) * 0.4;
      _userPulseAnnotation!
        ..circleRadius = radius
        ..circleColor = AppColors.primary.withOpacity(opacity).toARGB32();
      _userLocationAnnotationManager?.update(_userPulseAnnotation!);
    });
  }

  void _openBusDetails(Bus bus, BusTrackerController controller) {
    context.go(
      '/bus',
      extra: BusDetailsArgs(
        bus: bus,
        userLocation: _userLocation,
        stops: controller.stops,
      ),
    );
  }

  void _openStopTimeline(BusStop stop, BusTrackerController controller) {
    context.go(
      '/stop',
      extra: StopTimelineArgs(
        stop: stop,
        stops: controller.stops,
        buses: controller.buses,
        userLocation: _userLocation,
      ),
    );
  }
}

class _NearbyBus {
  const _NearbyBus({required this.bus, required this.distanceMeters});

  final Bus bus;
  final double distanceMeters;
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(31),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_bus, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BUSIO Live Map',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                'Tap a bus for details',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.neutral),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
