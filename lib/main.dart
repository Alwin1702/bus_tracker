import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/bus_details/presentation/bus_details_screen.dart';
import 'features/live_feed/presentation/camera_view.dart';
import 'features/map/models/bus.dart';
import 'features/map/presentation/controllers/bus_tracker_controller.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/stops/presentation/stop_timeline_screen.dart';
import 'features/timeline/presentation/timeline_screen.dart';

const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
GeoPoint? _initialGeoPoint;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mapboxAccessToken.isNotEmpty) {
    mbx.MapboxOptions.setAccessToken(_mapboxAccessToken);
  }
  _initialGeoPoint = await _resolveCurrentLocation();
  runApp(const PoyoApp());
}

Future<GeoPoint?> _resolveCurrentLocation() async {
  try {
    final permission = await Geolocator.checkPermission();
    LocationPermission granted = permission;
    if (permission == LocationPermission.denied) {
      granted = await Geolocator.requestPermission();
    }
    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition();
    log('Current location: ${position.latitude}, ${position.longitude}');
    return GeoPoint(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}

class PoyoApp extends StatelessWidget {
  const PoyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BusTrackerController()),
      ],
      child: MaterialApp.router(
        title: AppStrings.appName,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MapScreen(),
      routes: [
        GoRoute(
          path: 'bus',
          builder: (context, state) => BusDetailsScreen(
            args: state.extra is BusDetailsArgs
                ? state.extra as BusDetailsArgs
                : BusDetailsArgs(
                    bus: Bus(
                      id: 'B1',
                      name: 'Bus 1',
                      route: 'Route 1',
                      position:
                          _initialGeoPoint ?? BusTrackerController.defaultCenter,
                      heading: 0,
                      speedKmh: 24,
                      crowdLevel: CrowdLevel.medium,
                    ),
                    stops: const [],
                    userLocation: null,
                  ),
          ),
        ),
        GoRoute(
          path: 'stop',
          builder: (context, state) => StopTimelineScreen(
            args: state.extra is StopTimelineArgs
                ? state.extra as StopTimelineArgs
                : StopTimelineArgs(
                    stop: BusStop(
                      id: 'S1',
                      name: 'Central Stop',
                      location:
                          _initialGeoPoint ?? BusTrackerController.defaultCenter,
                    ),
                    buses: const [],
                    userLocation: _initialGeoPoint, stops: [],
                  ),
          ),
        ),
        GoRoute(
          path: 'timeline',
          builder: (context, state) => TimelineScreen(
            bus: state.extra is Bus ? state.extra as Bus : null,
          ),
        ),
        GoRoute(
          path: 'camera',
          builder: (context, state) => LiveCameraView(
            bus: state.extra is Bus ? state.extra as Bus : null,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
  ],
  errorBuilder: (context, state) => const Scaffold(
    body: Center(child: Text('Route not found')),
  ),
);
