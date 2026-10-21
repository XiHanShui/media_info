/// 播放器面板：传输控制 + 「跳到解析位置」。
///
/// 播放用 `media_kit`（libmpv/FFmpeg），所以两个平台的编解码覆盖都完整——
/// 不像系统解码器那样在 Windows 上缺 MKV/VP9。
///
/// ## 为什么没有内嵌视频画面
///
/// media-kit 在 **Windows** 上的原生视频输出目前是坏的：那个原生窗口会按整窗大小
/// 盖在 Flutter 界面之上（上游 issue #1187「1.2.0 - Windows Black Screen」至今未关闭，
/// 社区里关硬件加速、改 `file:///` URI、显式 `setSize` 都绕不过去）。
/// 内嵌视频在 Flutter 界面里没法用，所以：
///
/// - **音频**：在应用内播放（已验证可用）。
/// - **视频**：在应用内播放**音轨与时间轴**（位置、跳转、播放头高亮都准），
///   **画面**交给系统默认播放器打开。
///
/// 播放头位置 → 字节偏移 → 结构树里高亮当前所在的块，这条链路与有没有画面无关。
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/position_index.dart';
import '../theme.dart';

/// 播放器条的总高度（窗口底部那条）。
const double kPlayerBarHeight = 96;

/// 播放器面板。
class PlayerPanel extends StatefulWidget {
  const PlayerPanel({
    super.key,
    required this.path,
    this.positionIndex,
    this.selectedOffset,
    this.onPositionOffset,
    this.onError,
    this.hasVideo = false,
  });

  /// 要播放的文件路径。
  final String path;

  /// 字节位置 ↔ 时间的映射（没有就退化成"只能顺序播放"）。
  final PositionIndex? positionIndex;

  /// 当前在结构树里选中的块的字节偏移。
  final int? selectedOffset;

  /// 播放位置变化时上报当前字节偏移（用于高亮当前所在的块）。
  final ValueChanged<int?>? onPositionOffset;

  /// 播放出错时上报。
  final ValueChanged<String>? onError;

  /// 这个文件里有没有视频轨。有就多给一个「用系统播放器打开」。
  final bool hasVideo;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  late final Player _player = Player();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<String>? _errorSub;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.stream.position.listen((Duration position) {
      final index = widget.positionIndex;
      if (index == null) return;
      final offset = index.offsetOf(position);
      if (offset != null) widget.onPositionOffset?.call(offset);
    });
    _errorSub = _player.stream.error.listen((String message) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onError?.call(message);
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      // media-kit 要的是 URI：Windows 上给裸路径它认不出来（上游 issue #1187）。
      // 统一转成 file:/// 形式，斜杠是正斜杠。
      final uri = 'file:///${widget.path.replaceAll('\\', '/')}';
      await _player.open(Media(uri));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onError?.call('$error');
    }
  }

  @override
  void didUpdateWidget(PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _failed = false;
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  /// 跳到当前选中的块。
  Future<void> _jumpToSelection() async {
    final index = widget.positionIndex;
    final offset = widget.selectedOffset;
    if (index == null || offset == null) return;
    final target = index.timestampOf(offset);
    if (target == null) return;
    await _player.seek(target);
  }

  /// 用系统默认播放器打开这个文件（视频画面用）。
  Future<void> _openExternally() async {
    final path = widget.path;
    try {
      if (io.Platform.isWindows) {
        await io.Process.run('cmd', <String>['/c', 'start', '', path]);
      } else if (io.Platform.isMacOS) {
        await io.Process.run('open', <String>[path]);
      } else {
        await io.Process.run('xdg-open', <String>[path]);
      }
    } on Object catch (error) {
      widget.onError?.call('无法打开系统播放器：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.positionIndex;
    final target = index == null || widget.selectedOffset == null
        ? null
        : index.timestampOf(widget.selectedOffset!);

    return Container(
      decoration: const BoxDecoration(
        color: MediaColors.panel,
        border: Border(top: BorderSide(color: MediaColors.edge)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _PlayButton(player: _player),
          const SizedBox(width: 12),
          _TimeReadout(player: _player),
          const SizedBox(width: 16),
          Expanded(child: _hintLine(target)),
          if (target != null)
            _ActionButton(
              label: '跳到选中块 ${_formatTime(target)}',
              onTap: _jumpToSelection,
            ),
          if (widget.hasVideo) ...<Widget>[
            const SizedBox(width: 8),
            _ActionButton(
              label: '用系统播放器打开',
              onTap: _openExternally,
            ),
          ],
          if (_failed) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '无法播放此文件（编码器不支持或文件损坏）',
              style: MediaType.note(MediaColors.rose),
            ),
          ],
        ],
      ),
    );
  }

  /// 位置提示：说明当前播放到哪、能不能跳。
  Widget _hintLine(Duration? target) {
    final index = widget.positionIndex;
    if (index == null) {
      return Text(
        '此格式不支持「跳到解析位置」（无法把字节位置换算成时间）',
        style: MediaType.note(MediaColors.chalkFaint),
      );
    }
    if (target == null) {
      return Text(
        '在结构树里选中一个块，就能跳到它在文件里的位置',
        style: MediaType.note(MediaColors.chalkFaint),
      );
    }
    return Text(
      index.isExact
          ? '选中块位于 ${_formatTime(target)}（精确换算）'
          : '选中块约位于 ${_formatTime(target)}（按比例估算）',
      style: MediaType.note(MediaColors.amber),
    );
  }
}

/// 播放/暂停按钮。
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        final playing = snapshot.data ?? false;
        return _FlatIconButton(
          icon: playing ? Icons.pause : Icons.play_arrow,
          tooltip: playing ? '暂停' : '播放',
          onPressed: () => player.playOrPause(),
        );
      },
    );
  }
}

/// 平面按钮（发丝描边，无阴影）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: MediaColors.edge),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(label, style: MediaType.note(MediaColors.chalkDim)),
        ),
      ),
    );
  }
}

/// 平面图标按钮。
class _FlatIconButton extends StatelessWidget {
  const _FlatIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              border: Border.all(color: MediaColors.edge),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(icon, size: 15, color: MediaColors.chalkDim),
          ),
        ),
      ),
    );
  }
}

/// 当前位置 / 总时长。
class _TimeReadout extends StatelessWidget {
  const _TimeReadout({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (BuildContext context, AsyncSnapshot<Duration> snapshot) {
        final position = snapshot.data ?? Duration.zero;
        return Row(
          children: <Widget>[
            Text(_formatTime(position), style: _timeStyle),
            Text(' / ', style: _timeStyle),
            Text(_formatTime(player.state.duration), style: _timeStyle),
          ],
        );
      },
    );
  }

  static final TextStyle _timeStyle = MediaType.coordinate(MediaColors.chalkDim);
}

/// 把时长格式化成 `mm:ss.mmm`（不足一小时）。
String _formatTime(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis = total.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds.$millis';
  }
  return '$minutes:$seconds.$millis';
}
