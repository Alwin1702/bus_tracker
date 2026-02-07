import 'dart:async';
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
  bool _routesReady = false;
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
          _scheduleAnnotationSync();
          return Stack(
            children: [
              mbx.MapWidget(
                key: const ValueKey('poyoMap'),
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
                bottom: 32,
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
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

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

  Future<void> _syncAnnotations(BusTrackerController controller) async {
    if (!_mapReady || _busAnnotationManager == null) return;
    if (!_busIconLoaded) {
      await _loadBusIcon();
    }
    await _busAnnotationManager!.deleteAll();
    await _stopAnnotationManager?.deleteAll();
    _busByAnnotationId.clear();
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

    for (final bus in controller.buses) {
      final annotation = await _busAnnotationManager!.create(
        mbx.PointAnnotationOptions(
          geometry: _toPoint(bus.position),
          iconImage: 'bus-icon',
          iconSize: 0.1,
          iconRotate: bus.heading,
          iconAnchor: mbx.IconAnchor.CENTER,
        ),
      );
      _busByAnnotationId[annotation.id] = bus;
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
          lineColor: Color(route.colorArgb).withOpacity(0.7).toARGB32(),
          lineWidth: 4.0,
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
    _syncAnnotations(controller);
    _syncRoutes(controller);
    _ensureUserLocationAnnotation();
  }

  Future<void> _loadBusIcon() async {
    if (_mapboxMap == null || _busIconLoaded) return;
    try {
      final bytes = await rootBundle.load('assets/icons/bus.png');
      final list = bytes.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(list);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      await _mapboxMap!.style.addStyleImage(
        'bus-icon',
        1.0,
        mbx.MbxImage(width: (image.width).toInt(), height: (image.height ).toInt(), data: list),
        false,
        [],
        [],
        null,
      );
      _busIconLoaded = true;
    } catch (_) {
      _busIconLoaded = false;
    }
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
                'POYO Live Map',
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
