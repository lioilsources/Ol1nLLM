import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'dart:async';

import '../core/constants/theme.dart';

/// Fullscreen looping player for an animated („Rozhýbat") clip, with save to
/// Photos and the platform share sheet. Plays the local mp4 straight from the
/// app's documents directory — no server round-trip once the node is ready.
/// Uloží [path] do Fotek. PhotoKit odmítá některé jinak platné mp4
/// („unsupported format" = pokus o konverzi, který selže), a v takovém případě
/// je share sheet jediná cesta, jak video z appky dostat — nabídne se rovnou,
/// místo aby uživatel zůstal jen s chybou.
Future<void> saveVideo(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // Kopie do tmp: Photos čte soubor mimo sandbox appky spolehlivěji než
    // z Application Support, a přípona musí sedět na obsah.
    final tmp = File(
      '${Directory.systemTemp.path}/ol1n_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await tmp.writeAsBytes(await File(path).readAsBytes(), flush: true);
    await Gal.putVideo(tmp.path);
    unawaited(tmp.delete().catchError((_) => tmp));
    messenger.showSnackBar(
      const SnackBar(content: Text('Video uloženo do Fotek')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Fotky video nepřijaly — zkus Sdílet'),
        action: SnackBarAction(
          label: 'Sdílet',
          onPressed: () => SharePlus.instance.share(
            ShareParams(files: [XFile(path, mimeType: 'video/mp4')]),
          ),
        ),
      ),
    );
    debugPrint('[video] Gal.putVideo selhalo: $e');
  }
}

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
            onPressed: () => saveVideo(context, widget.path),
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
