import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../map/models/bus.dart';

Future<void> showCctvModal(BuildContext context, {Bus? bus}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _CctvModal(bus: bus),
  );
}

class LiveCameraView extends StatelessWidget {
  const LiveCameraView({super.key, this.bus});

  final Bus? bus;

  @override
  Widget build(BuildContext context) {
    final title = bus == null ? 'Live Camera' : '${bus!.name} Cameras';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _CctvContent(bus: bus),
      ),
    );
  }
}

class _CctvModal extends StatefulWidget {
  const _CctvModal({this.bus});

  final Bus? bus;

  @override
  State<_CctvModal> createState() => _CctvModalState();
}

class _CctvModalState extends State<_CctvModal> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.bus == null
                        ? 'Live CCTV'
                        : '${widget.bus!.name} CCTV',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  '10s to collapse',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.neutral,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CctvContent(bus: widget.bus),
          ],
        ),
      ),
    );
  }
}

class _CctvContent extends StatelessWidget {
  const _CctvContent({this.bus});

  final Bus? bus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Column(
            children: const [
              _CameraFeedPlaceholder(label: 'Front CCTV'),
              SizedBox(height: 12),
              _CameraFeedPlaceholder(label: 'Rear CCTV'),
            ],
          ),
          
        ],
      ),
    );
  }
}

class _CameraFeedPlaceholder extends StatelessWidget {
  const _CameraFeedPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, color: AppColors.primary, size: 36),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Video stream placeholder',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.neutral,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
