import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chewie/chewie.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'offline_tutorial_items.dart';
import 'offline_video_player_page.dart';

Future<void> offlineTutorialBottomSheet({
  required BuildContext context,
}) {
  final rootContext = context;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return FractionallySizedBox(
        heightFactor: 0.95,
        child: DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              top: false,
              child: _TutorialList(
                rootContext: rootContext,
                scrollController: scrollController,
              ),
            );
          },
        ),
      );
    },
  );
}

class _TutorialList extends StatefulWidget {
  final BuildContext rootContext;
  final ScrollController scrollController;

  const _TutorialList({
    required this.rootContext,
    required this.scrollController,
  });

  @override
  State<_TutorialList> createState() => _TutorialListState();
}

class _TutorialListState extends State<_TutorialList> {
  static const base = Color(0xFFF4511E);
  static const dark = Color(0xFFD84315);
  static const light = Color(0xFFFFAB91);
  static const fg = Color(0xFFFFFFFF);

  int? _expandedIndex;
  final Map<int, VideoPlayerController> _vCtrls = {};
  final Map<int, ChewieController> _cCtrls = {};
  final Map<int, Duration> _durationCache = {};
  final Map<String, Future<Uint8List?>> _thumbFutures = {}; // assetPath -> Future

  @override
  void dispose() {
    for (final c in _cCtrls.values) {
      c.dispose();
    }
    for (final v in _vCtrls.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<Uint8List?> _thumbnailForAsset(String assetPath) {
    return _thumbFutures.putIfAbsent(assetPath, () async {
      try {
        final tmpDir = await getTemporaryDirectory();
        final thumbsDir = Directory('${tmpDir.path}/tutorial_thumbs');
        if (!await thumbsDir.exists()) {
          await thumbsDir.create(recursive: true);
        }
        final key = assetPath.replaceAll('/', '_');
        final cached = File('${thumbsDir.path}/$key.jpg');
        if (await cached.exists()) {
          return await cached.readAsBytes();
        }

        final data = await rootBundle.load(assetPath);
        final tmpMp4 = File('${thumbsDir.path}/$key.source.mp4');
        await tmpMp4.writeAsBytes(data.buffer.asUint8List());

        final bytes = await VideoThumbnail.thumbnailData(
          video: tmpMp4.path,
          imageFormat: ImageFormat.JPEG,
          quality: 80,
          timeMs: 500,
        );
        if (bytes != null) {
          await cached.writeAsBytes(bytes, flush: true);
        }
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  Future<Duration?> _loadDuration(int index, String assetPath) async {
    if (_durationCache.containsKey(index)) return _durationCache[index];
    VideoPlayerController? v;
    try {
      v = VideoPlayerController.asset(assetPath);
      await v.initialize();
      final d = v.value.duration;
      _durationCache[index] = d;
      return d;
    } catch (_) {
      return null;
    } finally {
      await v?.dispose();
    }
  }

  Future<void> _togglePreview(int index, String assetPath) async {
    if (_expandedIndex == index) {
      _disposePreview(index);
      setState(() => _expandedIndex = null);
      return;
    }
    if (_expandedIndex != null) {
      _disposePreview(_expandedIndex!);
    }
    final v = VideoPlayerController.asset(assetPath);
    await v.initialize();
    await v.setLooping(true);
    await v.setVolume(0);
    final c = ChewieController(
      videoPlayerController: v,
      autoPlay: true,
      looping: true,
      showControls: false,
      allowMuting: true,
      allowFullScreen: false,
    );
    setState(() {
      _vCtrls[index] = v;
      _cCtrls[index] = c;
      _expandedIndex = index;
    });
  }

  void _disposePreview(int index) {
    _cCtrls.remove(index)?.dispose();
    _vCtrls.remove(index)?.dispose();
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final items = TutorialVideos.items;
    final Map<String, List<TutorialVideoItem>> grouped = {};
    for (final it in items) {
      grouped.putIfAbsent(it.category, () => []).add(it);
    }
    final orderedSections = [
      for (final cat in TutorialCategories.ordered)
        if (grouped.containsKey(cat)) cat,
      for (final cat in grouped.keys)
        if (!TutorialCategories.ordered.contains(cat)) cat,
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: light.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: base.withOpacity(.06),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: light.withOpacity(.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            '튜토리얼',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700).copyWith(color: dark),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: orderedSections.fold<int>(0, (sum, cat) => sum + 1 + (grouped[cat]?.length ?? 0)),
              itemBuilder: (context, i) {
                int cursor = 0;
                for (final cat in orderedSections) {
                  if (i == cursor) {
                    return _sectionHeader(cat);
                  }
                  cursor++;

                  final list = grouped[cat]!;
                  for (final item in list) {
                    if (i == cursor) {
                      final itemIndex = TutorialVideos.items.indexOf(item);
                      return _buildRow(itemIndex, item);
                    }
                    cursor++;
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: base,
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.close_rounded),
              label: const Text('닫기'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index, TutorialVideoItem item) {
    final isExpanded = _expandedIndex == index;
    final assetPath = item.assetPath;

    return Column(
      children: [
        InkWell(
          onTap: () => _togglePreview(index, assetPath),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                // 썸네일
                FutureBuilder<Uint8List?>(
                  future: _thumbnailForAsset(assetPath),
                  builder: (context, snap) {
                    final bytes = snap.data;
                    final thumb = (bytes != null && bytes.isNotEmpty)
                        ? Image.memory(bytes, width: 96, height: 54, fit: BoxFit.cover)
                        : Container(
                            width: 96,
                            height: 54,
                            color: base.withOpacity(.08),
                            child: const Icon(CupertinoIcons.play_rectangle, size: 26, color: Colors.grey),
                          );
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: thumb,
                    );
                  },
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FutureBuilder<Duration?>(
                            future: _loadDuration(index, assetPath),
                            builder: (context, snap) {
                              final d = snap.data;
                              return Text(
                                _formatDuration(d),
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                IconButton(
                  tooltip: '전체 화면',
                  icon: const Icon(CupertinoIcons.play_circle, size: 24, color: Colors.grey),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(widget.rootContext).push(
                      MaterialPageRoute(builder: (_) => OfflineVideoPlayerPage(item: item)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildPreviewPlayer(index),
          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
        Divider(height: 12, color: light.withOpacity(.25)),
      ],
    );
  }

  Widget _buildPreviewPlayer(int index) {
    final c = _cCtrls[index];
    if (c == null) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(12.0),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: Chewie(controller: c)),
          Positioned(
            right: 8,
            bottom: 8,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: base,
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.fullscreen),
              label: const Text('전체 화면'),
              onPressed: () {
                Navigator.of(context).pop();
                final item = TutorialVideos.items[index];
                Navigator.of(widget.rootContext).push(
                  MaterialPageRoute(builder: (_) => OfflineVideoPlayerPage(item: item)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
