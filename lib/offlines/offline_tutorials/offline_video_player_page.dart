// Enhanced: Chewie 컨트롤 적용(전체화면, 배속, 시크 등)
// Location: lib/offlines/tutorial/offline_video_player_page.dart
import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'offline_tutorial_items.dart';

class OfflineVideoPlayerPage extends StatefulWidget {
  final TutorialVideoItem item;
  const OfflineVideoPlayerPage({super.key, required this.item});

  @override
  State<OfflineVideoPlayerPage> createState() => _OfflineVideoPlayerPageState();
}

class _OfflineVideoPlayerPageState extends State<OfflineVideoPlayerPage> {
  late final VideoPlayerController _videoCtrl;
  ChewieController? _chewieCtrl;
  late Future<void> _initF;

  // 타이틀 → 실제 asset 경로 매핑 (bottom_sheet와 동일)
  static const Map<String, String> _assetByTitle = {
    "00 · 완료": "assets/tutorials/00completed.mp4",
    "00 · 출차 완료": "assets/tutorials/00departurecompleted.mp4",
    "00 · 출차 요청": "assets/tutorials/00departurerequest.mp4",
    "00 · 주차 완료": "assets/tutorials/00parkingcompleted.mp4",
    "00 · 요청": "assets/tutorials/00request.mp4",
    "00 · 로그 보기": "assets/tutorials/00showlog.mp4",
    "01 · 요청": "assets/tutorials/01request.mp4",
    "02 · 요청": "assets/tutorials/02request.mp4",
    "03 · 요청": "assets/tutorials/03request.mp4",
  };

  String _assetOf(TutorialVideoItem item) {
    return _assetByTitle[item.title] ?? "assets/tutorials/00request.mp4";
  }

  @override
  void initState() {
    super.initState();
    _videoCtrl = VideoPlayerController.asset(_assetOf(widget.item));
    _initF = _init();
  }

  Future<void> _init() async {
    await _videoCtrl.initialize();
    _chewieCtrl = ChewieController(
      videoPlayerController: _videoCtrl,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      allowMuting: true,
      showControls: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Colors.blueAccent,
        handleColor: Colors.white,
        backgroundColor: Colors.black26,
        bufferedColor: Colors.white38,
      ),
    );
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<void>(
        future: _initF,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done || _chewieCtrl == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final aspect = _videoCtrl.value.aspectRatio == 0
              ? (16 / 9)
              : _videoCtrl.value.aspectRatio;
          return Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: Chewie(controller: _chewieCtrl!),
            ),
          );
        },
      ),
    );
  }
}
