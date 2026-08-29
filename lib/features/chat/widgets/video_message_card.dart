import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/image_request_headers.dart';
import '../../../utils/sandbox_path_resolver.dart';

/// Inline player for generated video results persisted as `[video:<source>]`.
///
/// Local files play directly; remote URLs are downloaded with progress first
/// so playback and sharing keep working after the signed URL expires.
class VideoMessageCard extends StatefulWidget {
  const VideoMessageCard({super.key, required this.source});

  final String source;

  @override
  State<VideoMessageCard> createState() => _VideoMessageCardState();
}

class _VideoMessageCardState extends State<VideoMessageCard> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _downloading = false;
  double? _downloadProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant VideoMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source == widget.source) return;
    _disposeController();
    _error = null;
    _initializing = true;
    _prepare();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    _controller = null;
  }

  void _onControllerTick() {
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    try {
      final fixed = SandboxPathResolver.fix(widget.source);
      final local = File(fixed);
      if (local.existsSync()) {
        await _initController(local);
        return;
      }
      final uri = Uri.tryParse(widget.source);
      if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'file-missing';
        });
        return;
      }
      if (mounted) {
        setState(() {
          _downloading = true;
          _downloadProgress = null;
        });
      }
      final client = http.Client();
      try {
        final request = http.Request('GET', uri)
          ..headers.addAll(browserImageRequestHeaders);
        final response = await client.send(request);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException('HTTP ${response.statusCode}', uri);
        }
        final totalBytes = response.contentLength ?? 0;
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in response.stream) {
          builder.add(chunk);
          received += chunk.length;
          if (totalBytes > 0 && mounted) {
            setState(() => _downloadProgress = received / totalBytes);
          }
        }
        final tempDir = await getTemporaryDirectory();
        final videoDir = Directory('${tempDir.path}/videos');
        if (!await videoDir.exists()) {
          await videoDir.create(recursive: true);
        }
        final file = File(
          '${videoDir.path}/video_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        await file.writeAsBytes(builder.takeBytes(), flush: true);
        if (!mounted) return;
        setState(() => _downloading = false);
        await _initController(file);
      } finally {
        client.close();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _downloading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _initController(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.toString();
      });
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _initializing = false;
    });
    controller.addListener(_onControllerTick);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    try {
      final fixed = SandboxPathResolver.fix(widget.source);
      if (File(fixed).existsSync()) {
        await Share.shareXFiles([XFile(fixed)]);
        return;
      }
      final uri = Uri.tryParse(widget.source);
      if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
        await Share.shareUri(uri);
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _openExternally() async {
    try {
      final fixed = SandboxPathResolver.fix(widget.source);
      if (File(fixed).existsSync()) {
        await OpenFilex.open(fixed);
        return;
      }
      final uri = Uri.tryParse(widget.source);
      if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
        await Share.shareUri(uri);
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String message) {
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.imageViewerPageSaveFailed(message),
      type: NotificationType.error,
    );
  }

  Widget _buildStage(ColorScheme cs) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final value = controller.value;
      return GestureDetector(
        onTap: _togglePlay,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            if (!value.isPlaying)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.play_arrow, size: 34, color: cs.onSurface),
                ),
              ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Container(
        height: 180,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.videocam_off,
            size: 26,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }
    return Container(
      height: 180,
      color: cs.surfaceContainerHighest,
      child: Center(
        child: _downloading
            ? SizedBox(
                width: 150,
                child: LinearProgressIndicator(value: _downloadProgress),
              )
            : const CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = _controller;
    final initialized = controller?.value.isInitialized == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStage(cs),
          Row(
            children: [
              IconButton(
                onPressed: initialized ? _togglePlay : null,
                icon: Icon(
                  initialized && controller!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              ),
              Expanded(
                child: initialized
                    ? VideoProgressIndicator(
                        controller!,
                        allowScrubbing: true,
                        colors: VideoProgressColors(playedColor: cs.primary),
                      )
                    : LinearProgressIndicator(
                        value: _downloading ? _downloadProgress : null,
                      ),
              ),
              IconButton(icon: const Icon(Icons.share), onPressed: _share),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: _openExternally,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
