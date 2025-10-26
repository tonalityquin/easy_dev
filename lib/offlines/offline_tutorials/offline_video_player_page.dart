import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'offline_tutorial_items.dart';

class OfflineVideoPlayerPage extends StatefulWidget {
  final TutorialVideoItem item;

  const OfflineVideoPlayerPage({super.key, required this.item});

  @override
  State<OfflineVideoPlayerPage> createState() => _OfflineVideoPlayerPageState();
}

class _OfflineVideoPlayerPageState extends State<OfflineVideoPlayerPage> {
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    final assetPath = widget.item.assetPath;

    final v = VideoPlayerController.asset(assetPath);
    await v.initialize();

    final c = ChewieController(
      videoPlayerController: v,
      autoPlay: true,
      looping: false,
      showControls: true,
      deviceOrientationsOnEnterFullScreen: const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
      allowFullScreen: true,
      allowMuting: true,
    );

    setState(() {
      _videoCtrl = v;
      _chewieCtrl = c;
    });
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.item.title,
          style: const TextStyle(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final c = _chewieCtrl;
          if (c == null) {
            return const Center(
              child: Text(
                '영상을 불러오지 못했습니다.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final v = _videoCtrl!;
          final size = v.value.size;
          final aspect = (size.width > 0 && size.height > 0) ? size.width / size.height : 16 / 9;

          return Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: Chewie(controller: c),
            ),
          );
        },
      ),
    );
  }
}
