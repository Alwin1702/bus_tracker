import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
              CameraFeed(),

            ],
          ),
          
        ],
      ),
    );
  }
}

class CameraFeed extends StatefulWidget {
  const CameraFeed({super.key});

  @override
  State<CameraFeed> createState() => _CameraFeedState();
}

class _CameraFeedState extends State<CameraFeed> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/videos/bus_camera_footage.mp4',
    )..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

