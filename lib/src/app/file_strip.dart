/// 胶片条：整个文件的一览图。
///
/// 顶层块按各自的长度在一条横带上按比例排开——像一卷胶片上的画格。
/// 一眼能看出两件事：**这个文件里哪块最占地方**，以及**当前选中的块在哪儿**。
///
/// 颜色不是装饰，是编码：
/// - **琥珀** = 媒体载荷（`mdat`）——真正的音视频数据
/// - **青** = 元数据与结构（`moov`/`ftyp`/`meta`/`udta`…）
/// - **暗灰** = 填充与未知块（`free`/`skip`/`wide`/没见过的）
///
/// 这条带子就是本工具的立身之本：MediaInfo 给你字段，但丢掉了坐标系；
/// 这里把「文件由什么构成」和「东西在文件的哪个位置」合成一张图。
library;

import 'package:flutter/material.dart';

import '../core/node.dart';
import '../ui/structure_tree.dart';
import 'theme.dart';

/// 胶片条。
class FileStrip extends StatelessWidget {
  const FileStrip({super.key, required this.root, this.selected, this.onSelect});

  /// 已解析的树（用它的顶层子块）。
  final ContainerNode? root;

  /// 当前选中的节点（高亮显示）。
  final ContainerNode? selected;

  /// 点击某一段时的回调。
  final ValueChanged<ContainerNode>? onSelect;

  /// 带子的高度。
  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final root = this.root;
    final children = root?.children ?? const <ContainerNode>[];
    if (children.isEmpty) {
      return const SizedBox(height: height);
    }

    final total = root!.size <= 0 ? 1 : root.size;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final width = constraints.maxWidth;
            // 按累计偏移排布：每一段的位置就是它在文件里的真实位置。
            var cursor = 0;
            final segments = <Widget>[];
            for (final child in children) {
              final left = width * (cursor / total);
              cursor += child.size;
              segments.add(
                _Segment(
                  node: child,
                  left: left,
                  total: total,
                  width: width,
                  isSelected: _isSameOrAncestor(child, selected),
                  onTap: onSelect,
                ),
              );
            }
            return Stack(children: segments);
          },
        ),
      ),
    );
  }

  /// 选中的节点是不是这一段本身，或它的后代。
  static bool _isSameOrAncestor(ContainerNode node, ContainerNode? selected) {
    if (selected == null) return false;
    var current = selected;
    while (true) {
      if (identical(current, node) || current.offset == node.offset) return true;
      final parent = _parentOf(current);
      if (parent == null) return false;
      current = parent;
    }
  }

  /// 从根往下找父节点（层级不深，线性找足够）。
  static ContainerNode? _parentOf(ContainerNode target) {
    ContainerNode? found;
    void walk(ContainerNode node) {
      if (found != null) return;
      for (final child in node.children) {
        if (identical(child, target) || child.offset == target.offset) {
          found = node;
          return;
        }
        walk(child);
      }
    }

    walk(target);
    return found;
  }
}

/// 一段（一个顶层块）。
class _Segment extends StatelessWidget {
  const _Segment({
    required this.node,
    required this.left,
    required this.total,
    required this.width,
    required this.isSelected,
    this.onTap,
  });

  final ContainerNode node;

  /// 这一段在整条带子上的左边界（像素），由父级按累计偏移算出。
  final double left;
  final int total;
  final double width;
  final bool isSelected;
  final ValueChanged<ContainerNode>? onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : node.size / total;
    final segmentWidth = (width * fraction).clamp(1.0, width);
    // 用**规范名**（Matroska 的十六进制 ID 要映射成 Segment/Info/…）
    final label = structureNodeLabel(node.type);
    final role = _roleOf(label);

    final fill = isSelected
        ? Color.alphaBlend(role.fill.withValues(alpha: 0.85), MediaColors.amber)
        : role.fill;
    final border = isSelected ? MediaColors.amber : role.border;

    return Positioned(
      left: left,
      width: segmentWidth,
      top: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.only(right: 1),
        child: Tooltip(
          message: '$label  ·  偏移 ${node.offset}  ·  长度 ${node.size}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null ? null : () => onTap!(node),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: border, width: 1),
                borderRadius: BorderRadius.circular(1),
              ),
              child: segmentWidth > 46
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MediaType.note(
                            role.onFill,
                          ).copyWith(fontSize: 10),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  /// 块在文件里的角色 → 颜色。
  static _StripRole _roleOf(String type) {
    const String media = 'mdat';
    if (type == media || type == 'mdat ') {
      return const _StripRole(
        fill: MediaColors.amberDeep,
        border: MediaColors.amber,
        onFill: MediaColors.chalk,
      );
    }
    const Set<String> metadata = <String>{
      // ISO base media
      'moov',
      'moof',
      'trak',
      'mdia',
      'minf',
      'stbl',
      'meta',
      'udta',
      'ftyp',
      'mfra',
      'sidx',
      // Matroska / EBML——用**规范名**，不是十六进制 ID
      'EBML',
      'Segment',
      'SeekHead',
      'Info',
      'Tracks',
      'TrackEntry',
      'Video',
      'Audio',
      'Tags',
    };
    if (metadata.contains(type)) {
      return const _StripRole(
        fill: MediaColors.tealDeep,
        border: MediaColors.teal,
        onFill: MediaColors.chalk,
      );
    }
    return const _StripRole(
      fill: MediaColors.edge,
      border: MediaColors.chalkFaint,
      onFill: MediaColors.chalkDim,
    );
  }
}

/// 一段的角色配色。
class _StripRole {
  const _StripRole({
    required this.fill,
    required this.border,
    required this.onFill,
  });

  final Color fill;
  final Color border;
  final Color onFill;
}
