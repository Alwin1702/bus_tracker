import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../live_feed/presentation/camera_view.dart';

import '../../../core/constants/app_colors.dart';
import '../../map/models/bus.dart';

class BusDetailsArgs {
  BusDetailsArgs({
    required this.bus,
    required this.stops,
    required this.userLocation,
  });

  final Bus bus;
  final List<BusStop> stops;
  final GeoPoint? userLocation;
}

class BusDetailsScreen extends StatelessWidget {
  const BusDetailsScreen({super.key, required this.args});

  final BusDetailsArgs args;

  @override
  Widget build(BuildContext context) {
    final bus = args.bus;
    final nearestStop = _nearestStop(args.userLocation, args.stops);
    final etaMinutes = nearestStop == null ? null : _estimateEta(bus, nearestStop);
    final rating = _ratingForBus(bus);

    return Scaffold(
      appBar: AppBar(title: Text(bus.name)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_bus, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bus.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          bus.route,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _RatingChip(rating: rating),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _InfoTile(
              label: 'Nearest stop to you',
              value: nearestStop?.name ?? 'Location unavailable',
            ),
            _InfoTile(
              label: 'Boarding',
              value: bus.boarding,
            ),
            _InfoTile(
              label: 'Destination',
              value: bus.destination,
            ),
            _InfoTile(
              label: 'ETA to nearest stop',
              value: etaMinutes == null ? '--' : '$etaMinutes min',
            ),
            _InfoTile(
              label: 'Current crowd',
              value: bus.crowdLevel.name.toUpperCase(),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => showCctvModal(context, bus: bus),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Open Live Camera Feed'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BusStop? _nearestStop(GeoPoint? userLocation, List<BusStop> stops) {
    if (userLocation == null || stops.isEmpty) return null;
    return stops.reduce((a, b) {
      final distanceA = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        a.location.latitude,
        a.location.longitude,
      );
      final distanceB = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        b.location.latitude,
        b.location.longitude,
      );
      return distanceA <= distanceB ? a : b;
    });
  }

  int _estimateEta(Bus bus, BusStop stop) {
    final distance = Geolocator.distanceBetween(
      bus.position.latitude,
      bus.position.longitude,
      stop.location.latitude,
      stop.location.longitude,
    );
    final speedMetersPerMinute = max(bus.speedKmh, 10) * 1000 / 60;
    return (distance / speedMetersPerMinute).ceil();
  }

  double _ratingForBus(Bus bus) {
    final seed = bus.id.hashCode.abs() % 15;
    return 4.0 + seed / 30;
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.neutral,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
