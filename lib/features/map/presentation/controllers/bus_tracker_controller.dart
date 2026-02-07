import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../models/bus.dart';

class BusTrackerController extends ChangeNotifier {
  BusTrackerController() {
    _seedRoutes();
    _seedStops();
    _seedBuses();
    _startTicker();
  }

  static const GeoPoint defaultCenter = GeoPoint(11.2720014, 75.8375713);

  static const double _segmentStep = 0.08;

  final List<Bus> _buses = [];
  final List<BusStop> _stops = [];
  final List<BusRoute> _routes = [];
  final Map<String, BusRoute> _routeByBusId = {};
  final Map<String, int> _segmentIndexByBusId = {};
  final Map<String, int> _segmentDirectionByBusId = {};
  final Map<String, double> _segmentProgressByBusId = {};
  Timer? _ticker;
  List<Bus> get buses => List.unmodifiable(_buses);
  List<BusStop> get stops => List.unmodifiable(_stops);
  List<BusRoute> get routes => List.unmodifiable(_routes);

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
        Bus(
          id: 'B3',
          name: 'Chevayur Line',
          route: 'Chevayur ↔ Kuthiravattom',
          position: _routes[2].points.first,
          heading: 0,
          speedKmh: 26,
          crowdLevel: CrowdLevel.high,
        ),
        Bus(
          id: 'B4',
          name: 'Campus Shuttle',
          route: 'Medical College Loop',
          position: _routes[0].points[2],
          heading: 0,
          speedKmh: 20,
          crowdLevel: CrowdLevel.medium,
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

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) {
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
