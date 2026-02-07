import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../map/models/bus.dart';

class StopTimelineArgs {
  StopTimelineArgs({
    required this.stop,
    required this.stops,
    required this.buses,
    required this.userLocation,
  });

  final BusStop stop;
  final List<BusStop> stops;
  final List<Bus> buses;
  final GeoPoint? userLocation;
}

class StopTimelineScreen extends StatelessWidget {
  const StopTimelineScreen({super.key, required this.args});

  final StopTimelineArgs args;

  @override
  Widget build(BuildContext context) {
    final inbound = _mockTimes(args.buses, seed: 1);
    final outbound = _mockTimes(args.buses, seed: 2);
    final directions = _resolveDirections(args.stops, args.stop);

    return Scaffold(
      appBar: AppBar(title: Text(args.stop.name)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upcoming buses from both sides',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _TimelineColumn(
                title: 'Towards ${directions.$1}',
                times: inbound,
              ),
            ),

            const SizedBox(height: 16),
            Expanded(
              child: _TimelineColumn(
                title: 'Towards ${directions.$2}',
                times: outbound,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _resolveDirections(
    List<BusStop> stops,
    BusStop current,
  ) {
    if (stops.isEmpty) {
      return ('Next stop', 'Previous stop');
    }
    final index = stops.indexWhere((stop) => stop.id == current.id);
    if (index == -1) {
      return ('Next stop', 'Previous stop');
    }
    final nextIndex = index < stops.length - 1 ? index + 1 : 0;
    final prevIndex = index > 0 ? index - 1 : stops.length - 1;
    return (stops[nextIndex].name, stops[prevIndex].name);
  }

  List<_Arrival> _mockTimes(List<Bus> buses, {required int seed}) {
    final random = Random(seed + buses.length);
    return List.generate(5, (index) {
      final minutes = 4 + random.nextInt(18) + index * 3;
      final bus = buses.isEmpty ? null : buses[random.nextInt(buses.length)];
      return _Arrival(
        label: bus?.name ?? 'Bus',
        minutes: minutes,
      );
    });
  }
}

class _TimelineColumn extends StatelessWidget {
  const _TimelineColumn({required this.title, required this.times});

  final String title;
  final List<_Arrival> times;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          ...times.map((arrival) => _ArrivalTile(arrival: arrival)),
        ],
      ),
    );
  }
}

class _Arrival {
  _Arrival({required this.label, required this.minutes});

  final String label;
  final int minutes;
}

class _ArrivalTile extends StatelessWidget {
  const _ArrivalTile({required this.arrival});

  final _Arrival arrival;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              arrival.label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            '${arrival.minutes} min',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.neutral,
                ),
          ),
        ],
      ),
    );
  }
}
