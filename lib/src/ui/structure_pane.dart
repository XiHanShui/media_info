/// 右栏：结构树视图（上部）+ hex 视图（下部）。
///
/// 这是实现票 21 的**装配位置**——应用层把 [StructurePane] 放进右栏，
/// 上半是结构树，下半是选中块的 hex 面板。
///
/// - 结构树见 `structure_tree.dart`，hex 面板见 `hex_view.dart`。
/// - 选中一个块 → 树里高亮 + 下面的 hex 面板更新。
library;

import 'package:flutter/material.dart';

import '../core/node.dart';
import 'hex_view.dart';
import 'structure_tree.dart';

/// hex 面板展开时的高度。
const double kHexPanelHeight = 260;

/// hex 面板折叠时的高度（只有标题栏）。
const double kHexPanelCollapsedHeight = 26;

/// 右栏：结构树 + hex 面板。
class StructurePane extends StatefulWidget {
  const StructurePane({
    super.key,
    required this.filePath,
    required this.root,
    this.fileSize,
    this.loader,
    this.resetToken = 0,
  });

  /// 文件路径（惰性展开重新解析、hex 读字节都用它）。
  final String filePath;

  /// 结构树的根节点（`null` = 没有结构可显示）。
  final ContainerNode? root;

  /// 文件总字节数（占比条的分母）；`null` = 用根节点的大小。
  final int? fileSize;

  /// 惰性展开用的加载器（应用层注入解析服务的 `parseStructureAtDepth`）。
  final StructureLoader? loader;

  /// 变化时重置展开状态与选中状态（切换标签页时用）。
  final int resetToken;

  @override
  State<StructurePane> createState() => _StructurePaneState();
}

class _StructurePaneState extends State<StructurePane> {
  /// 当前选中的块。
  ContainerNode? _selected;

  /// hex 面板是否折叠。
  bool _hexCollapsed = false;

  /// 文件总字节数：优先用外面给的，否则用根节点的大小。
  int get _fileSize {
    final given = widget.fileSize;
    if (given != null && given > 0) return given;
    return widget.root?.size ?? 0;
  }

  @override
  void didUpdateWidget(StructurePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      setState(() {
        _selected = null;
        _hexCollapsed = false;
      });
    }
  }

  void _onNodeSelected(ContainerNode node) {
    setState(() => _selected = node);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: StructureTree(
            root: widget.root,
            filePath: widget.filePath,
            fileSize: _fileSize,
            loader: widget.loader,
            selectedNode: selected,
            onNodeSelected: _onNodeSelected,
            resetToken: widget.resetToken,
          ),
        ),
        if (selected != null) ...<Widget>[
          const Divider(height: 1),
          SizedBox(
            height: _hexCollapsed ? kHexPanelCollapsedHeight : kHexPanelHeight,
            child: HexView(
              node: selected,
              filePath: widget.filePath,
              collapsed: _hexCollapsed,
              onCollapsedChanged: (bool value) =>
                  setState(() => _hexCollapsed = value),
            ),
          ),
        ],
      ],
    );
  }
}
