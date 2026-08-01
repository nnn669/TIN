import 'dart:async';
import 'package:flutter/material.dart';

/// 生成计时徽章，紧跟在模型名称右侧。
///
/// 流式输出期间每 100 ms 刷新一次，显示自 [startTime] 起的累计时长；
/// 流式结束后固定显示 [durationMs]（若为 null 则不渲染）。
class GenerationTimerBadge extends StatefulWidget {
  const GenerationTimerBadge({
    super.key,
    required this.isStreaming,
    required this.startTime,
    this.durationMs,
  });

  /// 当前消息是否仍在流式输出中。
  final bool isStreaming;

  /// 计时起点，通常使用 ChatMessage.timestamp（助手消息创建时刻）。
  final DateTime startTime;

  /// 流式结束后的最终耗时（毫秒），由流控制器写入。
  final int? durationMs;

  @override
  State<GenerationTimerBadge> createState() => _GenerationTimerBadgeState();
}

class _GenerationTimerBadgeState extends State<GenerationTimerBadge> {
  Timer? _ticker;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isStreaming) _startTicker();
  }

  @override
  void didUpdateWidget(GenerationTimerBadge old) {
    super.didUpdateWidget(old);
    if (widget.isStreaming && !old.isStreaming) {
      _startTicker();
    } else if (!widget.isStreaming && old.isStreaming) {
      _stopTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _elapsedMs = DateTime.now()
        .difference(widget.startTime)
        .inMilliseconds
        .clamp(0, 9999999);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedMs = DateTime.now()
            .difference(widget.startTime)
            .inMilliseconds
            .clamp(0, 9999999);
      });
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _formatMs(int ms) {
    if (ms < 60000) {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
    final totalSec = ms ~/ 1000;
    return '${totalSec ~/ 60}m ${totalSec % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final int? displayMs;
    if (widget.isStreaming) {
      displayMs = _elapsedMs;
    } else if (widget.durationMs != null && widget.durationMs! > 0) {
      displayMs = widget.durationMs;
    } else {
      return const SizedBox.shrink();
    }

    return Text(
      _formatMs(displayMs!),
      style: TextStyle(
        fontSize: 11,
        color: widget.isStreaming
            ? cs.primary.withValues(alpha: 0.75)
            : cs.onSurface.withValues(alpha: 0.42),
      ),
    );
  }
}
