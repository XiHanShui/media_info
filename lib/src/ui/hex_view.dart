/// hex 视图（右栏下部）：显示选中块的十六进制内容与 ASCII 侧栏。
///
/// - 节点**不持有字节内容**，只持有 `offset` / `size`——这里按需从文件读。
/// - 大块**分页/截断**：最多读 [kDefaultHexByteLimit] 个字节，并说明还剩多少。
/// - 文件被截断时优雅降级：读得到多少显示多少，并说明文件在哪儿截断。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/byte_source.dart';
import '../core/errors.dart';
import '../core/node.dart';

/// 默认最多显示的字节数（大块不能一次读几 GB）。
const int kDefaultHexByteLimit = 4096;

/// 每行显示的字节数。
const int kHexBytesPerLine = 16;

/// 把字节格式化成「偏移 + 十六进制 + ASCII」的行。
///
/// 例：`00000010  00 41 42 FF                             |.AB.|`
///
/// [baseOffset] 是这批字节在文件里的起始偏移（显示成十六进制）。
List<String> hexDumpLines(
  Uint8List bytes, {
  required int baseOffset,
  int bytesPerLine = kHexBytesPerLine,
}) {
  final lines = <String>[];
  if (bytesPerLine <= 0) return lines;
  for (var start = 0; start < bytes.length; start += bytesPerLine) {
    final end = start + bytesPerLine;
    final chunk = end > bytes.length ? bytes.length : end;
    final hex = <String>[];
    final ascii = StringBuffer();
    for (var index = start; index < chunk; index++) {
      final byte = bytes[index];
      hex.add(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      ascii.write(_isPrintable(byte) ? String.fromCharCode(byte) : '.');
    }
    // 不足一行时补空格，让 ASCII 列对齐。
    while (hex.length < bytesPerLine) {
      hex.add('  ');
    }
    lines.add(
      '${(baseOffset + start).toRadixString(16).toUpperCase().padLeft(8, '0')}'
      '  ${hex.join(' ')}  |${ascii.toString()}|',
    );
  }
  return lines;
}

/// 是不是可以直接显示的 ASCII 字符。
bool _isPrintable(int byte) => byte >= 0x20 && byte <= 0x7e;

/// hex 视图：显示选中块的内容。
class HexView extends StatefulWidget {
  const HexView({
    super.key,
    required this.node,
    required this.filePath,
    this.byteLimit = kDefaultHexByteLimit,
    this.collapsed = false,
    this.onCollapsedChanged,
  });

  /// 选中的块；`null` = 没有选中任何块（面板应该整个收起来）。
  final ContainerNode? node;

  /// 文件路径（字节从这里读）。
  final String filePath;

  /// 最多显示多少字节（超出的部分只报数量，不读）。
  final int byteLimit;

  /// 面板是否折叠。
  ///
  /// 给了 [onCollapsedChanged] 时这个值是**受控**的（由外部决定），
  /// 否则由本组件自己管（[collapsed] 只作为初始值）。
  final bool collapsed;

  /// 折叠状态变化时的回调。
  final ValueChanged<bool>? onCollapsedChanged;

  @override
  State<HexView> createState() => _HexViewState();
}

class _HexViewState extends State<HexView> {
  /// 自己管的折叠状态（受控模式下不用）。
  late bool _internalCollapsed = widget.collapsed;

  /// 读到的字节。
  Uint8List _bytes = Uint8List(0);

  /// 读到的字节的起始偏移。
  int _baseOffset = 0;

  /// 还没显示的字节数（块比 [HexView.byteLimit] 大时非零）。
  int _remaining = 0;

  /// 错误说明（中文）；`null` = 没有错误。
  String? _error;

  /// 文件本身被截断（块声明的大小超过文件剩余）。
  bool _fileTruncated = false;

  bool get _isCollapsed =>
      widget.onCollapsedChanged != null ? widget.collapsed : _internalCollapsed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HexView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.node, oldWidget.node) ||
        widget.filePath != oldWidget.filePath ||
        widget.byteLimit != oldWidget.byteLimit) {
      _load();
    }
  }

  /// 读出选中块的前 [HexView.byteLimit] 个字节。
  void _load() {
    final node = widget.node;
    if (node == null) {
      setState(() {
        _bytes = Uint8List(0);
        _error = null;
        _remaining = 0;
        _fileTruncated = false;
      });
      return;
    }
    FileByteSource? source;
    try {
      source = FileByteSource.fromPath(widget.filePath);
    } on FileSystemException catch (error) {
      setState(() {
        _bytes = Uint8List(0);
        _error = '无法打开文件：${error.message}';
        _remaining = node.size;
        _fileTruncated = false;
      });
      return;
    }
    try {
      final available = source.length - node.offset;
      if (available <= 0) {
        setState(() {
          _bytes = Uint8List(0);
          _error = '文件在偏移 ${node.offset} 处截断，没有可显示的字节';
          _remaining = node.size;
          _fileTruncated = true;
        });
        return;
      }
      final wanted = node.size < widget.byteLimit ? node.size : widget.byteLimit;
      final count = available < wanted ? available : wanted;
      final bytes = source.read(node.offset, count);
      setState(() {
        _bytes = bytes;
        _baseOffset = node.offset;
        _remaining = node.size - bytes.length;
        _fileTruncated = count < wanted;
        _error = null;
      });
    } on TruncatedFile catch (error) {
      setState(() {
        _bytes = Uint8List(0);
        _error = '文件在偏移 ${error.offset} 处截断，还差 ${error.missingBytes} 字节';
        _remaining = node.size;
        _fileTruncated = true;
      });
    } on FileSystemException catch (error) {
      setState(() {
        _bytes = Uint8List(0);
        _error = '读取文件失败：${error.message}';
        _remaining = node.size;
        _fileTruncated = false;
      });
    } finally {
      source.close();
    }
  }

  void _toggleCollapsed() {
    final next = !_isCollapsed;
    final callback = widget.onCollapsedChanged;
    if (callback != null) {
      callback(next);
      return;
    }
    setState(() => _internalCollapsed = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = widget.node;
    if (node == null) {
      return const SizedBox.shrink();
    }
    final lines = hexDumpLines(_bytes, baseOffset: _baseOffset);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamilyFallback: const <String>[
        'Consolas',
        'Menlo',
        'Courier New',
        'monospace',
      ],
      height: 1.25,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _header(context, theme, node),
        if (!_isCollapsed) ...<Widget>[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_fileTruncated && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Text(
                '文件在偏移 ${node.offset} 处截断，只读得到 ${_bytes.length} 字节',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_remaining > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Text(
                '仅显示前 ${_bytes.length} 字节，还有 $_remaining 字节未显示',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: Container(
              color: theme.colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 760,
                  child: ListView.builder(
                    itemCount: lines.length,
                    itemExtent: 18,
                    itemBuilder: (BuildContext context, int index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 1,
                      ),
                      child: Text(lines[index], style: mono),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 面板标题：块的类型、偏移、大小 + 折叠按钮。
  Widget _header(BuildContext context, ThemeData theme, ContainerNode node) {
    return Container(
      height: 26,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          Text(
            'hex',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            node.type,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '偏移 ${node.offset}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '大小 ${node.size}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _toggleCollapsed,
            icon: Icon(
              _isCollapsed ? Icons.expand_less : Icons.expand_more,
              size: 16,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            tooltip: _isCollapsed ? '展开 hex 面板' : '折叠 hex 面板',
          ),
        ],
      ),
    );
  }
}
