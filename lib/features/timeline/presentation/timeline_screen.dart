import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../map/models/bus.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key, this.bus});

  final Bus? bus;

  @override
  Widget build(BuildContext context) {
    final title = bus == null ? 'Timeline' : '${bus!.name} Timeline';
    final schedule = _mockTimeline();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemBuilder: (context, index) {
          final entry = schedule[index];
          return _TimelineTile(entry: entry, isLast: index == schedule.length - 1);
        },
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemCount: schedule.length,
      ),
    );
  }

  List<TimelineEntry> _mockTimeline() {
    return [
      TimelineEntry(
        stopName: 'Medical College Bus stop',
        scheduledTime: const TimeOfDay(hour: 8, minute: 15),
        actualTime: const TimeOfDay(hour: 8, minute: 17),
      ),
      TimelineEntry(
        stopName: 'Kovur',
        scheduledTime: const TimeOfDay(hour: 8, minute: 28),
        actualTime: const TimeOfDay(hour: 8, minute: 25),
      ),
      TimelineEntry(
        stopName: 'Chevayur',
        scheduledTime: const TimeOfDay(hour: 8, minute: 42),
        actualTime: const TimeOfDay(hour: 8, minute: 46),
      ),
      TimelineEntry(
        stopName: 'Thondayad Junction bus stop',
        scheduledTime: const TimeOfDay(hour: 8, minute: 55),
        actualTime: const TimeOfDay(hour: 8, minute: 54),
      ),
    ];
  }
}

class TimelineEntry {
  TimelineEntry({
    required this.stopName,
    required this.scheduledTime,
    required this.actualTime,
  });

  final String stopName;
  final TimeOfDay scheduledTime;
  final TimeOfDay actualTime;
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry, required this.isLast});

  final TimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheduled = _formatTime(entry.scheduledTime);
    final actual = _formatTime(entry.actualTime);
    final isDelayed = _isAfter(entry.actualTime, entry.scheduledTime);
    final actualColor = isDelayed ? AppColors.danger : AppColors.success;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          painter: _TimelinePainter(isLast: isLast),
          child: const SizedBox(width: 28, height: 80),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
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
                  entry.stopName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TimeColumn(label: 'Scheduled', value: scheduled),
                    ),
                    Expanded(
                      child: _TimeColumn(
                        label: 'Actual',
                        value: actual,
                        valueColor: actualColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isAfter(TimeOfDay a, TimeOfDay b) {
    if (a.hour != b.hour) return a.hour > b.hour;
    return a.minute > b.minute;
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.neutral,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.isLast});

  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final circlePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, 12), 6, circlePaint);
    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, 20),
        Offset(centerX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) => false;
}
