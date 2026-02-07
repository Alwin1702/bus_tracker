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

  static const double _segmentStep = 0.001;

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
          name: 'Medical College Loop',
          colorArgb: 0xFF2E7D32,
          isLoop: true,
          points: const [
            GeoPoint(11.2720014, 75.8375713),
            GeoPoint(11.2705706, 75.8312627),
            GeoPoint(11.2698683, 75.8259294),
            GeoPoint(11.2669500, 75.8204000),
            GeoPoint(11.2713000, 75.8289000),
          ],
        ),
        BusRoute(
          id: 'R2',
          name: 'Kovur ↔ Kunnamangalam',
          colorArgb: 0xFF1565C0,
          points: const [
            GeoPoint(11.2705706, 75.8312627),
            GeoPoint(11.2720014, 75.8375713),
            GeoPoint(11.2812000, 75.8509000),
            GeoPoint(11.2928000, 75.8658000),
            GeoPoint(11.3035000, 75.8735000),
          ],
        ),
        BusRoute(
          id: 'R3',
          name: 'Chevayur ↔ Kuthiravattom',
          colorArgb: 0xFFF57C00,
          points: const [
            GeoPoint(11.2698683, 75.8259294),
            GeoPoint(11.2669500, 75.8204000),
            GeoPoint(11.2632000, 75.8134000),
            GeoPoint(11.2589000, 75.8039000),
          ],
        ),
      ]);

    _routeWaypointsById
      ..clear()
      ..addAll({
        'R1': const [
          GeoPoint(11.2720014, 75.8375713),
          GeoPoint(11.2705706, 75.8312627),
          GeoPoint(11.2698683, 75.8259294),
          GeoPoint(11.2669500, 75.8204000),
          GeoPoint(11.2713000, 75.8289000),
        ],
        'R2': const [
          GeoPoint(11.2705706, 75.8312627),
          GeoPoint(11.2720014, 75.8375713),
          GeoPoint(11.2812000, 75.8509000),
          GeoPoint(11.2928000, 75.8658000),
          GeoPoint(11.3035000, 75.8735000),
        ],
        'R3': const [
          GeoPoint(11.2698683, 75.8259294),
          GeoPoint(11.2669500, 75.8204000),
          GeoPoint(11.2632000, 75.8134000),
          GeoPoint(11.2589000, 75.8039000),
        ],
      });
  }

  void _seedStops() {
    _stops
      ..clear()
      ..addAll([
        const BusStop(
          id: 'S1',
          name: 'Kovur',
          location: GeoPoint(11.2705706, 75.8312627),
        ),
        const BusStop(
          id: 'S2',
          name: 'Medical College',
          location: GeoPoint(11.2720014, 75.8375713),
        ),
        const BusStop(
          id: 'S3',
          name: 'Chevayur',
          location: GeoPoint(11.2698683, 75.8259294),
        ),
        const BusStop(
          id: 'S4',
          name: 'Nellikode',
          location: GeoPoint(11.2669500, 75.8204000),
        ),
        const BusStop(
          id: 'S5',
          name: 'Kunnamangalam',
          location: GeoPoint(11.3035000, 75.8735000),
        ),
        const BusStop(
          id: 'S6',
          name: 'Kuthiravattom',
          location: GeoPoint(11.2589000, 75.8039000),
        ),
      ]);
  }

  void _seedBuses() {
    _buses
      ..clear()
      ..addAll([
        Bus(
          id: 'B1',
          name: 'Kozhikode Loop',
          route: 'Medical College Loop',
          position: _routes[0].points.first,
          heading: 0,
          speedKmh: 28,
          crowdLevel: CrowdLevel.medium,
        ),
        Bus(
          id: 'B2',
          name: 'Kovur Line',
          route: 'Kovur ↔ Kunnamangalam',
          position: _routes[1].points.first,
          heading: 0,
          speedKmh: 24,
          crowdLevel: CrowdLevel.low,
        ),
        
      ]);

    _routeByBusId
      ..clear()
      ..addAll({
        'B1': _routes[0],
        'B2': _routes[1],
        'B3': _routes[2],
        'B4': _routes[0],
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
      if (route != null && !_segmentIndexByBusId.containsKey(bus.id)) {
        bus.position = route.points.first;
      }
    }
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
