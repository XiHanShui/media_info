/// 结构树视图（右栏上部）：可展开的块树。
///
/// - **虚拟滚动**：只构建可见的行（[ListView.builder]），`moov` 里上万个
///   `stts` / `stsz` 条目也不会卡。
/// - **惰性展开**：展开一个没有子块的节点时，按更大的深度重新解析整个文件
///   （[StructureLoader]），再把新解析出来的子块接到那棵子树上。
/// - **占比条**：每行右侧一条细条，表示这个块占文件大小的比例
///   （user story 55：`mdat` 占 95% 时一眼看得出来）。
///
/// 节点模型见 `docs/design/core-api.md`；界面契约见 `docs/design/ui-layout.md`。
library;

import 'package:flutter/material.dart';

import '../core/node.dart';
import '../app/theme.dart';
import '../formats/matroska.dart';

/// 惰性展开用的加载器：按更大深度重新解析整个文件的结构树。
///
/// 与解析服务的 `parseStructureAtDepth(path, depth: depth)` 签名一致，
/// 由应用层注入（UI 层不依赖应用层）。
typedef StructureLoader =
    Future<ContainerNode?> Function(String path, {required int depth});

/// 结构树默认的解析深度（与解析服务的默认深度一致）。
const int kDefaultStructureDepth = 8;

/// 惰性展开时解析深度增加的步长。
const int kStructureDepthStep = 4;

/// 结构树能用的最大解析深度（引擎的递归上限是 64 层）。
const int kMaxStructureDepth = 64;

/// 占比条的最大宽度（像素）。
const double kProportionBarWidth = 72;

/// 节点显示名：Matroska 的十六进制元素 ID 换成 schema 里的元素名。
///
/// EBML 元素 ID 没有 ASCII 形式（`0x18538067`），用元素名（`Segment`）
/// 才有可读性；其它格式的块类型名（`moov` / `fmt ` / `ftyp`）原样显示，不翻译。
String structureNodeLabel(String type) {
  if (_hexElementId.hasMatch(type)) {
    final name = matroskaElementName(type);
    if (name != null) return name;
  }
  return type;
}

final RegExp _hexElementId = RegExp(r'^0x[0-9A-Fa-f]+$');

/// 行 key 用的路径文本：根节点是 `root`，其它是子节点下标链（如 `2.1`）。
///
/// 用**路径**而不是偏移做 key——偏移可能重复（根节点和第一个子块都在 0），
/// 重复的 key 会让 Flutter 的元素树错位。
String _rowKey(String path) => path.isEmpty ? 'root' : path;

/// 结构树视图。
class StructureTree extends StatefulWidget {
  const StructureTree({
    super.key,
    required this.root,
    required this.filePath,
    this.fileSize = 0,
    this.loader,
    this.selectedNode,
    this.onNodeSelected,
    this.resetToken = 0,
  });

  /// 结构树的根节点（`null` = 没有结构可显示）。
  final ContainerNode? root;

  /// 文件路径（惰性展开重新解析时用）。
  final String filePath;

  /// 文件总字节数（占比条的分母）。
  final int fileSize;

  /// 惰性展开的加载器；`null` = 不做惰性展开。
  final StructureLoader? loader;

  /// 当前选中的块（在树里高亮）。
  final ContainerNode? selectedNode;

  /// 选中一个块时的回调（hex 面板靠它更新）。
  final ValueChanged<ContainerNode>? onNodeSelected;

  /// 变化时重置展开状态与选中状态（切换标签页时用）。
  final int resetToken;

  @override
  State<StructureTree> createState() => _StructureTreeState();
}

class _StructureTreeState extends State<StructureTree> {
  /// 已展开的节点（键是节点在树里的路径，如 `0.2.1`；根节点是空串）。
  final Set<String> _expanded = <String>{''};

  /// 惰性展开后换上的节点（键是节点路径）。
  final Map<String, ContainerNode> _overrides = <String, ContainerNode>{};

  /// 正在重新解析的节点（键是节点路径）。
  final Set<String> _busy = <String>{};

  /// 试过但确实没有子块的节点（不再显示展开按钮）。
  final Set<String> _leaf = <String>{};

  /// 按深度重新解析出来的整棵树（最新的在最后）。
  final List<ContainerNode> _deeperRoots = <ContainerNode>[];

  /// 当前解析深度。
  int _depth = kDefaultStructureDepth;

  @override
  void initState() {
    super.initState();
    _depth = kDefaultStructureDepth;
  }

  @override
  void didUpdateWidget(StructureTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _resetState();
      return;
    }
    if (!identical(widget.root, oldWidget.root)) {
      _resetState();
    }
  }

  /// 清空展开 / 惰性展开 / 缓存的状态。
  void _resetState() {
    _expanded
      ..clear()
      ..add('');
    _overrides.clear();
    _busy.clear();
    _leaf.clear();
    _deeperRoots.clear();
    _depth = kDefaultStructureDepth;
  }

  // -------------------------------------------------------------------------
  // 展开
  // -------------------------------------------------------------------------

  /// 展开 / 收起一个节点；没有子块时走惰性展开。
  void _onToggle(_TreeRow row) {
    if (_busy.contains(row.key)) return;
    if (row.hasChildren) {
      setState(() {
        if (_expanded.contains(row.key)) {
          _expanded.remove(row.key);
        } else {
          _expanded.add(row.key);
        }
      });
      return;
    }
    _lazyExpand(row);
  }

  /// 惰性展开：按更大的深度重新解析，把新解析出来的子块接上。
  Future<void> _lazyExpand(_TreeRow row) async {
    final loader = widget.loader;
    if (loader == null) return;
    if (row.node.isOpaque) return;
    if (_leaf.contains(row.key)) return;
    if (_depth >= kMaxStructureDepth) return;

    setState(() => _busy.add(row.key));
    try {
      var found = _findInDeeperTrees(row.key);
      if (found == null || found.children.isEmpty) {
        final next = _depth + kStructureDepthStep;
        final depth = next > kMaxStructureDepth ? kMaxStructureDepth : next;
        final root = await loader(widget.filePath, depth: depth);
        if (root != null) {
          _deeperRoots.add(root);
          _depth = depth;
        }
        found = _findInDeeperTrees(row.key);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(row.key);
        if (found != null && found.children.isNotEmpty) {
          _overrides[row.key] = found;
          _expanded.add(row.key);
          _leaf.remove(row.key);
        } else {
          // 重新解析了也没有子块：这是个叶子，不再显示展开按钮。
          _leaf.add(row.key);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy.remove(row.key);
        _leaf.add(row.key);
      });
    }
  }

  /// 在按更大深度解析出来的树里找某个路径上的节点（找不到返回 `null`）。
  ContainerNode? _findInDeeperTrees(String key) {
    for (final root in _deeperRoots.reversed) {
      final node = _nodeAt(root, key);
      if (node != null) return node;
    }
    return null;
  }

  /// 按路径（`0.2.1` 这样的子节点下标链）找节点。
  static ContainerNode? _nodeAt(ContainerNode root, String key) {
    if (key.isEmpty) return root;
    var node = root;
    for (final part in key.split('.')) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= node.children.length) {
        return null;
      }
      node = node.children[index];
    }
    return node;
  }

  // -------------------------------------------------------------------------
  // 渲染
  // -------------------------------------------------------------------------

  /// 可见的行（只有展开的节点才带上子块）。
  List<_TreeRow> _buildRows() {
    final root = widget.root;
    if (root == null) return const <_TreeRow>[];
    final rows = <_TreeRow>[];
    void visit(ContainerNode node, String key, int depth) {
      final effective = _overrides[key] ?? node;
      rows.add(_TreeRow(key: key, node: effective, depth: depth));
      if (!_expanded.contains(key)) return;
      final children = effective.children;
      for (var index = 0; index < children.length; index++) {
        visit(children[index], key.isEmpty ? '$index' : '$key.$index', depth + 1);
      }
    }

    visit(root, '', 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.root;
    if (root == null) {
      return Center(
        child: Text(
          '没有结构信息',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final rows = _buildRows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TreeHeader(fileSize: widget.fileSize),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 22,
            itemBuilder: (BuildContext context, int index) {
              final row = rows[index];
              return _TreeRowWidget(
                row: row,
                fileSize: widget.fileSize,
                expanded: _expanded.contains(row.key),
                busy: _busy.contains(row.key),
                lazy: _leaf.contains(row.key),
                selected: _isSelected(row.node),
                onToggle: () => _onToggle(row),
                onSelect: () => widget.onNodeSelected?.call(row.node),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 选中的块是否就是这一行（按 offset + size + type 比，重新解析后仍然对得上）。
  bool _isSelected(ContainerNode node) {
    final selected = widget.selectedNode;
    if (selected == null) return false;
    return selected.offset == node.offset &&
        selected.size == node.size &&
        selected.type == node.type;
  }
}

/// 一行（一个块）在树里的信息。
class _TreeRow {
  const _TreeRow({required this.key, required this.node, required this.depth});

  /// 节点在树里的路径（子节点下标链）。
  final String key;

  /// 该行对应的节点（可能是惰性展开后换上的新节点）。
  final ContainerNode node;

  /// 缩进层级。
  final int depth;

  /// 有没有已经解析出来的子块。
  bool get hasChildren => node.children.isNotEmpty;
}

/// 表头：列的含义。
class _TreeHeader extends StatelessWidget {
  const _TreeHeader({required this.fileSize});

  final int fileSize;

  @override
  Widget build(BuildContext context) {
    final style = MediaType.eyebrow(MediaColors.chalkFaint);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: MediaColors.panel,
        border: Border(bottom: BorderSide(color: MediaColors.edge)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 18),
          Expanded(child: Text('块', style: style)),
          SizedBox(
            width: 88,
            child: Text('偏移', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 88,
            child: Text('大小', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: kProportionBarWidth + 58,
            child: Text('占比', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// 树里的一行。
class _TreeRowWidget extends StatelessWidget {
  const _TreeRowWidget({
    required this.row,
    required this.fileSize,
    required this.expanded,
    required this.busy,
    required this.lazy,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });

  final _TreeRow row;
  final int fileSize;
  final bool expanded;
  final bool busy;
  final bool lazy;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamilyFallback: const <String>[
        'Consolas',
        'Menlo',
        'Courier New',
        'monospace',
      ],
    );
    final typeStyle = (selected
            ? theme.textTheme.bodySmall?.copyWith(
                fontFamilyFallback: const <String>[
                  'Consolas',
                  'Menlo',
                  'Courier New',
                  'monospace',
                ],
                fontWeight: FontWeight.w600,
              )
            : mono)
        ?.copyWith(
          color: MediaColors.chalk,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );

    return InkWell(
      key: ValueKey<String>('structure-row-${_rowKey(row.key)}'),
      onTap: onSelect,
      child: Container(
        // 选中态是"发丝边 + 一点底色"，不是一整条琥珀横杠——那太吵。
        color: selected ? MediaColors.panelHigh : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundDecoration: selected
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: MediaColors.amber, width: 2),
                ),
              )
            : null,
        child: Row(
          children: <Widget>[
            SizedBox(width: row.depth * 14.0),
            SizedBox(
              width: 18,
              height: 18,
              child: _toggleButton(context),
            ),
            Expanded(
              child: Text(
                structureNodeLabel(row.node.type),
                style: typeStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                '${row.node.offset}',
                style: MediaType.coordinate(
                  selected ? MediaColors.chalkDim : MediaColors.chalkFaint,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                '${row.node.size}',
                style: MediaType.coordinate(
                  selected ? MediaColors.chalkDim : MediaColors.chalkFaint,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: kProportionBarWidth + 58,
              child: _ProportionBar(
                path: row.key,
                size: row.node.size,
                fileSize: fileSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 展开按钮：有子块是箭头，没有子块（但不透明、且没试过）是"还有更多"的意思。
  Widget _toggleButton(BuildContext context) {
    if (busy) {
      return const Center(
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    if (row.hasChildren) {
      return IconButton(
        key: ValueKey<String>('structure-toggle-${_rowKey(row.key)}'),
        onPressed: onToggle,
        icon: Icon(
          expanded ? Icons.expand_more : Icons.chevron_right,
          size: 16,
          color: MediaColors.chalkFaint,
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        tooltip: expanded ? '收起' : '展开',
      );
    }
    if (lazy || row.node.isOpaque) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: ValueKey<String>('structure-toggle-${_rowKey(row.key)}'),
      onPressed: onToggle,
      icon: Icon(
        Icons.add,
        size: 14,
        color: MediaColors.chalkFaint,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      tooltip: '展开更多内容',
    );
  }
}

/// 占比条：这个块占文件大小的比例。
class _ProportionBar extends StatelessWidget {
  const _ProportionBar({
    required this.path,
    required this.size,
    required this.fileSize,
  });

  final String path;
  final int size;
  final int fileSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = fileSize <= 0 ? 0.0 : size / fileSize;
    final clamped = fraction.clamp(0.0, 1.0);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: MediaColors.chalkFaint,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        SizedBox(
          width: 44,
          child: Text(
            _percentText(fraction),
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: kProportionBarWidth,
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: ValueKey<String>('structure-bar-${_rowKey(path)}'),
                width: kProportionBarWidth * clamped,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MediaColors.amber.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 占比的百分比文本（小于 1% 保留一位小数）。
  static String _percentText(double fraction) {
    if (fraction <= 0) return '0%';
    final percent = fraction * 100;
    if (percent < 1) return '${percent.toStringAsFixed(1)}%';
    if (percent < 10) return '${percent.toStringAsFixed(1)}%';
    return '${percent.round()}%';
  }
}
