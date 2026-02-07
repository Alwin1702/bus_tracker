enum CrowdLevel { low, medium, high }

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class BusStop {
  const BusStop({required this.id, required this.name, required this.location});

  final String id;
  final String name;
  final GeoPoint location;
}

class BusRoute {
  const BusRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.colorArgb,
    this.isLoop = false,
  });

  final String id;
  final String name;
  final List<GeoPoint> points;
  final int colorArgb;
  final bool isLoop;
}

class Bus {
  Bus({
    required this.id,
    required this.name,
    required this.route,
    required this.position,
    required this.heading,
    required this.speedKmh,
    required this.crowdLevel,
  });

  final String id;
  final String name;
  final String route;
  GeoPoint position;
  double heading;
  int speedKmh;
  CrowdLevel crowdLevel;
}
