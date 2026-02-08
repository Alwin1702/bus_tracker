import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/bus.dart';

class BusTrackerController extends ChangeNotifier {
  BusTrackerController() {
    _seedStops();
    _seedRoutes();
    _seedBuses();
    _startTicker();
    unawaited(_loadRoutes());
  }

  static const GeoPoint defaultCenter = GeoPoint(11.2720014, 75.8375713);

  static const String _mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static const double _segmentStep = 0.1;

  final List<Bus> _buses = [];
  final List<BusStop> _stops = [];
  final List<BusRoute> _routes = [];
  final Map<String, List<GeoPoint>> _routeWaypointsById = {};
  final Map<String, BusRoute> _routeByBusId = {};
  final Map<String, int> _segmentIndexByBusId = {};
  final Map<String, int> _segmentDirectionByBusId = {};
  final Map<String, double> _segmentProgressByBusId = {};
  int _routesRevision = 0;
  Timer? _ticker;
  List<Bus> get buses => List.unmodifiable(_buses);
  List<BusStop> get stops => List.unmodifiable(_stops);
  List<BusRoute> get routes => List.unmodifiable(_routes);
  int get routesRevision => _routesRevision;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _seedRoutes() {
    _routes
      ..clear()
      ..addAll([
        BusRoute(
          id: 'R1',
          name: 'Thondayad ↔ Medical College',
          colorArgb: 0xFF2E7D32,
          isLoop: false,
          points: const [
            GeoPoint(11.270675191264132, 75.83756766558567),
            GeoPoint(11.264671798011175, 75.81140515142316),
          ],
        ),
      ]);

    _routeWaypointsById
      ..clear()
      ..addAll({
        'R1': const [
          GeoPoint(11.270675191264132, 75.83756766558567),
          GeoPoint(11.264671798011175, 75.81140515142316),
        ],
      });
  }

  void _seedStops() {
    _stops
      ..clear()
      ..addAll([
        const BusStop(
          id: 'S1',
          name: 'Medical College Bus stop',
          location: GeoPoint(11.270675191264132, 75.83756766558567),
        ),
        const BusStop(
          id: 'S2',
          name: 'Kovur',
          location: GeoPoint(11.270255459446936, 75.83089949056058),
        ),
        const BusStop(
          id: 'S3',
          name: 'Chevayur',
          location: GeoPoint(11.269533073702855, 75.825892367432),
        ),
        const BusStop(
          id: 'S4',
          name: 'Thondayad Junction bus stop',
          location: GeoPoint(11.264671798011175, 75.81140515142316),
        ),
      ]);
  }

  void _seedBuses() {
    _buses
      ..clear()
      ..addAll([
        Bus(
          id: 'B1',
          name: 'KRS',
          route: 'Thondayad ↔ Medical College',
          boarding: 'Thondayad Junction bus stop',
          destination: 'Medical College Bus stop',
          position: const GeoPoint(11.264671798011175, 75.81140515142316),
          heading: 0,
          speedKmh: 28,
        ),
        Bus(
          id: 'B2',
          name: 'Challenger',
          route: 'Thondayad ↔ Medical College',
          boarding: 'Medical College Bus stop',
          destination: 'Thondayad Junction bus stop',
          position: const GeoPoint(11.270675191264132, 75.83756766558567),
          heading: 0,
          speedKmh: 24,
        ),
      ]);

    _routeByBusId
      ..clear()
      ..addAll({
        'B1': _routes[0],
        'B2': _routes[0],
      });

    _segmentIndexByBusId
      ..clear()
      ..addAll({
        'B1': _routes[0].points.length - 1,
        'B2': 0,
      });

    _segmentDirectionByBusId
      ..clear()
      ..addAll({
        'B1': -1,
        'B2': 1,
      });

    _segmentProgressByBusId
      ..clear()
      ..addAll({
        'B1': 0.0,
        'B2': 0.0,
      });
  }

  Future<void> _loadRoutes() async {
    if (_mapboxAccessToken.isEmpty) return;
    if (_routeWaypointsById.isEmpty) return;
    final List<BusRoute> updated = [];
    for (final route in _routes) {
      final waypoints = _routeWaypointsById[route.id] ?? route.points;
      final points = await _fetchRoutePoints(route, waypoints);
      if (points != null && points.length >= 2) {
        updated.add(
          BusRoute(
            id: route.id,
            name: route.name,
            colorArgb: route.colorArgb,
            isLoop: route.isLoop,
            points: points,
          ),
        );
      } else {
        updated.add(route);
      }
    }

    _routes
      ..clear()
      ..addAll(updated);
    _refreshRouteLookup();
    _routesRevision++;
    notifyListeners();
  }

  void _refreshRouteLookup() {
    final byId = {for (final route in _routes) route.id: route};
    _routeByBusId.updateAll((_, existing) => byId[existing.id] ?? existing);
    for (final bus in _buses) {
      final route = _routeByBusId[bus.id];
      if (route == null || route.points.isEmpty) continue;
      final boarding = _stopLocationByName(bus.boarding);
      final destination = _stopLocationByName(bus.destination);
      if (boarding != null && destination != null) {
        final startIndex = _nearestPointIndex(route.points, boarding);
        final endIndex = _nearestPointIndex(route.points, destination);
        _segmentIndexByBusId[bus.id] = startIndex;
        _segmentDirectionByBusId[bus.id] =
            startIndex <= endIndex ? 1 : -1;
        _segmentProgressByBusId[bus.id] = 0.0;
        bus.position = route.points[startIndex];
        continue;
      }
      final index = _segmentIndexByBusId[bus.id];
      if (index == null) {
        bus.position = route.points.first;
      } else {
        final safeIndex = index.clamp(0, route.points.length - 1);
        bus.position = route.points[safeIndex];
      }
    }
  }

  GeoPoint? _stopLocationByName(String name) {
    for (final stop in _stops) {
      if (stop.name == name) return stop.location;
    }
    return null;
  }

  int _nearestPointIndex(List<GeoPoint> points, GeoPoint target) {
    var bestIndex = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final dLat = point.latitude - target.latitude;
      final dLon = point.longitude - target.longitude;
      final score = dLat * dLat + dLon * dLon;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<List<GeoPoint>?> _fetchRoutePoints(
    BusRoute route,
    List<GeoPoint> waypoints,
  ) async {
    if (waypoints.length < 2) return null;
    final coordinates = <GeoPoint>[...waypoints];
    if (route.isLoop) {
      final first = coordinates.first;
      final last = coordinates.last;
      if (first.latitude != last.latitude || first.longitude != last.longitude) {
        coordinates.add(first);
      }
    }
    final coordString = coordinates
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coordString'
      '?geometries=polyline6&overview=full&steps=false'
      '&access_token=$_mapboxAccessToken',
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final geometry = routes.first['geometry'] as String?;
      if (geometry == null || geometry.isEmpty) return null;
      final points = _decodePolyline6(geometry);
      if (route.isLoop && points.isNotEmpty) {
        final first = points.first;
        final last = points.last;
        if (first.latitude != last.latitude || first.longitude != last.longitude) {
          points.add(first);
        }
      }
      return points;
    } catch (_) {
      return null;
    }
  }

  List<GeoPoint> _decodePolyline6(String encoded) {
    const double factor = 1e-6;
    final List<GeoPoint> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(GeoPoint(lat * factor, lng * factor));
    }
    return points;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _advanceBuses();
    });
  }

  void _advanceBuses() {
    for (final bus in _buses) {
      final route = _routeByBusId[bus.id];
      if (route == null || route.points.length < 2) continue;
      if (route.isLoop) {
        _advanceLoop(bus, route);
      } else {
        _advanceBackAndForth(bus, route);
      }
    }
    notifyListeners();
  }

  void _advanceLoop(Bus bus, BusRoute route) {
    final points = route.points;
    var index = _segmentIndexByBusId[bus.id] ?? 0;
    var t = _segmentProgressByBusId[bus.id] ?? 0.0;
    final nextIndex = (index + 1) % points.length;
    final start = points[index];
    final end = points[nextIndex];
    t = _stepForBus(bus, t);
    if (t >= 1.0) {
      t -= 1.0;
      index = nextIndex;
    }
    bus.position = _interpolate(start, end, t);
    bus.heading = _bearing(start, end);
    _segmentIndexByBusId[bus.id] = index;
    _segmentProgressByBusId[bus.id] = t;
  }

  void _advanceBackAndForth(Bus bus, BusRoute route) {
    final points = route.points;
    var index = _segmentIndexByBusId[bus.id] ?? 0;
    var direction = _segmentDirectionByBusId[bus.id] ?? 1;
    var t = _segmentProgressByBusId[bus.id] ?? 0.0;

    var nextIndex = index + direction;
    if (nextIndex < 0 || nextIndex >= points.length) {
      direction = -direction;
      nextIndex = index + direction;
    }

    final start = points[index];
    final end = points[nextIndex];
    t = _stepForBus(bus, t);
    if (t >= 1.0) {
      t -= 1.0;
      index = nextIndex;
      if (index == 0 || index == points.length - 1) {
        direction = -direction;
      }
    }

    bus.position = _interpolate(start, end, t);
    bus.heading = _bearing(start, end);
    _segmentIndexByBusId[bus.id] = index;
    _segmentDirectionByBusId[bus.id] = direction;
    _segmentProgressByBusId[bus.id] = t;
  }

  double _stepForBus(Bus bus, double progress) {
    final speedFactor = bus.speedKmh.clamp(12, 40) / 28.0;
    return progress + (_segmentStep * speedFactor);
  }

  GeoPoint _interpolate(GeoPoint start, GeoPoint end, double t) {
    return GeoPoint(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
  }

  double _bearing(GeoPoint start, GeoPoint end) {
    final lat1 = _degToRad(start.latitude);
    final lat2 = _degToRad(end.latitude);
    final dLon = _degToRad(end.longitude - start.longitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final brng = atan2(y, x);
    return (_radToDeg(brng) + 360) % 360;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  double _radToDeg(double rad) => rad * (180.0 / pi);

}
