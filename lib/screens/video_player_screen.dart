import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/theme.dart';

/// Fullscreen looping player for an animated („Rozhýbat") clip, with save to
/// Photos and the platform share sheet. Plays the local mp4 straight from the
/// app's documents directory — no server round-trip once the node is ready.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.path, this.title});

  final String path;
  final String? title;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Gal.putVideo(widget.path);
      messenger.showSnackBar(const SnackBar(content: Text('Video uloženo do Fotek')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Uložení selhalo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Video'),
        actions: [
          IconButton(
            tooltip: 'Uložit do Fotek',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _save(context),
          ),
          IconButton(
            tooltip: 'Sdílet',
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(widget.path, mimeType: 'video/mp4')]),
            ),
          ),
        ],
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : const CircularProgressIndicator(color: AppTheme.accent),
      ),
    );
  }
}
