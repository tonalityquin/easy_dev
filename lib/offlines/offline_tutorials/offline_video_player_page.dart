// Location: lib/offlines/tutorial/offline_video_player_page.dart
// Purpose : 전체화면 전용 플레이어. 오직 item.assetPath만 사용 (매핑/기본값 제거)

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'offline_tutorial_items.dart';

class OfflineVideoPlayerPage extends StatefulWidget {
  final TutorialVideoItem item; // title/description/category/assetPath 포함

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
    // 🔒 핵심: 타이틀 기반 매핑/기본값 제거. 오직 item.assetPath 사용.
    final assetPath = widget.item.assetPath;

    final v = VideoPlayerController.asset(assetPath);
    await v.initialize();

    // 기기 방향/시스템 UI 제어는 Chewie에 맡김
    final c = ChewieController(
      videoPlayerController: v,
      autoPlay: true,
      looping: false,
      showControls: true,
      // 전체화면 지원: 가로 고정 권장. 필요 시 세로 포함 가능.
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
    // assetPath는 UI에 노출하지 않음
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
          // 가로/세로 비율은 VideoPlayerController가 가진 값을 따름
          final v = _videoCtrl!;
          final size = v.value.size;
          final aspect = (size.width > 0 && size.height > 0)
              ? size.width / size.height
              : 16 / 9;

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
