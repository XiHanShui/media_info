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
    this.onNodeSelected,
    this.selectedNode,
    this.playheadOffset,
    this.highlight,
    this.highlightLabel,
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

  /// 选中块时通知外部（应用层用它把胶片条的高亮与树保持同步）。
  final ValueChanged<ContainerNode>? onNodeSelected;

  /// 外部指定的选中块（受控）。给了就用它——胶片条上点一段也能让树选中。
  final ContainerNode? selectedNode;

  /// 播放头当前所在的字节偏移（树里用播放头记号标出）。
  final int? playheadOffset;

  /// 要在 hex 面板里高亮的字节范围（语义字段选中时用）。
  final ByteRange? highlight;

  /// 高亮范围对应的字段名（显示在 hex 面板的提示行里）。
  final String? highlightLabel;

  @override
  State<StructurePane> createState() => _StructurePaneState();
}

class _StructurePaneState extends State<StructurePane> {
  /// 本地选中的块（外部没给 selectedNode 时用）。
  ContainerNode? _localSelected;

  /// 生效的选中块：外部受控优先。
  ContainerNode? get _selected => widget.selectedNode ?? _localSelected;

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
        _localSelected = null;
        _hexCollapsed = false;
      });
    }
  }

  void _onNodeSelected(ContainerNode node) {
    setState(() => _localSelected = node);
    widget.onNodeSelected?.call(node);
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
            playheadOffset: widget.playheadOffset,
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
              highlight: widget.highlight,
              highlightLabel: widget.highlightLabel,
              onCollapsedChanged: (bool value) =>
                  setState(() => _hexCollapsed = value),
            ),
          ),
        ],
      ],
    );
  }
}
