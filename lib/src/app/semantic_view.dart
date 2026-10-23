/// 左栏：语义字段视图。
///
/// 三个区段，顺序固定：「文件级」→「轨道级」（每条轨道一组）→「标签」。
/// 区段之间用分隔线，**不折叠**。
///
/// 排版取"仪器面板"的读法：**数据一律等宽、靠右对齐**，中文显示名是细体无衬线，
/// 英文技术名（`key`）以更暗的等宽小字紧跟在显示名后面——不翻译，也不另起一行
/// （另起一行会让长值换行时把英文名挤到别处，见 user story 47）。
///
/// 推算值（`origin == FieldOrigin.derived`）必须有视觉区分——标签后跟一个紫色
/// 「（推算）」chip（user story 15）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/node.dart';
import '../core/tag.dart';
import 'export.dart';
import 'parse_service.dart';
import 'theme.dart';

/// 推算值标记的后缀。
const String kDerivedSuffix = '（推算）';

/// 右键菜单里「复制」这一项的值。
const String _kCopyMenuValue = 'copy';

/// 右键菜单里「复制」这一项的文案。
const String _kCopyMenuLabel = '复制';

/// 复制成功后的提示文案前缀。
const String _kCopiedMessage = '已复制';

/// 值超过这个长度才截断并挂 tooltip（短值不挂，避免满屏 tooltip 的噪声）。
const int _kTruncateThreshold = 28;

/// 左栏：语义字段视图。
class SemanticView extends StatelessWidget {
  const SemanticView({
    super.key,
    required this.document,
    this.onFieldSelected,
    this.selectedField,
  });

  /// 已解析的文件。
  final ParsedDocument document;

  /// 选中一个字段时回调（用来在 hex 面板里高亮它占的字节）。
  final ValueChanged<SemanticField?>? onFieldSelected;

  /// 当前选中的字段（它那行的字节范围标签会点亮）。
  final SemanticField? selectedField;

  /// 是不是当前选中的那个字段。
  bool _isSelected(SemanticField field) {
    final selected = selectedField;
    if (selected == null) return false;
    return identical(selected, field) ||
        (selected.key == field.key &&
            selected.trackIndex == field.trackIndex &&
            selected.value == field.value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: <Widget>[
        const _SectionEyebrow('文件级'),
        if (document.fileFields.isEmpty)
          const _EmptyHint('没有文件级字段')
        else
          for (final field in document.fileFields)
            _FieldRow(
              field: field,
              selected: _isSelected(field),
              onSelected: onFieldSelected,
            ),
        const _Rule(),
        const _SectionEyebrow('轨道级'),
        if (document.tracks.isEmpty)
          const _EmptyHint('没有轨道级字段')
        else
          for (final track in document.tracks) ...<Widget>[
            _TrackHeader(trackIndex: track.trackIndex),
            for (final field in track.fields)
              _FieldRow(
                field: field,
                selected: _isSelected(field),
                onSelected: onFieldSelected,
              ),
          ],
        const _Rule(),
        const _SectionEyebrow('标签'),
        if (document.tags.isEmpty)
          const _EmptyHint('没有标签')
        else
          for (final tag in document.tags) _TagRow(tag: tag),
      ],
    );
  }
}

/// 区段眉标：仪器面板上的丝印字。
class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 2,
            height: 11,
            color: MediaColors.amber,
            margin: const EdgeInsets.only(right: 8),
          ),
          Text(title, style: MediaType.eyebrow(MediaColors.chalkDim)),
        ],
      ),
    );
  }
}

/// 区段之间的分隔线（发丝级，不留白）。
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(height: 1, color: MediaColors.edgeSoft),
    );
  }
}

/// 轨道分组标题（如「轨道 0」）。
class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.trackIndex});

  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: <Widget>[
          Text('轨道 $trackIndex', style: MediaType.eyebrow(MediaColors.teal)),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(height: 1, color: MediaColors.edgeSoft),
          ),
        ],
      ),
    );
  }
}

/// 一个语义字段行。
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.selected,
    required this.onSelected,
  });

  final SemanticField field;

  /// 这个字段是不是当前选中的。
  final bool selected;

  /// 点这一行时回调。
  final ValueChanged<SemanticField?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final derived = field.origin == FieldOrigin.derived;
    final text = formatFieldValue(field.value);

    return _CopyableRow(
      value: formatCopiedFieldValue(field),
      child: _Hoverable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected?.call(field),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 左：中文显示名 + 英文技术名（暗色等宽小字）
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          field.label,
                          style: MediaType.label(MediaColors.chalk),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          field.key,
                          style: MediaType.note(MediaColors.chalkFaint),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (derived) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: MediaColors.violet.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: MediaColors.violet.withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            kDerivedSuffix,
                            style: MediaType.note(MediaColors.violet),
                          ),
                        ),
                      ],
                      if (field.byteRange != null) ...<Widget>[
                        const SizedBox(width: 7),
                        Flexible(
                          child: ClipRect(
                            child: _ByteRangeChip(
                              range: field.byteRange!,
                              selected: selected,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // 右：值（等宽、靠右）
                Flexible(
                  child: _ValueText(text: text, align: TextAlign.right),
                ),
                if (field.unit != null && field.unit!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      field.unit!,
                      style: MediaType.note(MediaColors.chalkFaint),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 字段的字节范围标签：`0x2C–0x2F`。
///
/// 点这一行就能在右边的 hex 面板里高亮出这几个字节——
/// 把 hex 与字段值对起来（user story 27）。
class _ByteRangeChip extends StatelessWidget {
  const _ByteRangeChip({required this.range, required this.selected});

  /// 覆盖的字节范围。
  final ByteRange range;

  /// 当前是否被选中。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final label =
        '0x${range.start.toRadixString(16).toUpperCase()}'
        '–0x${(range.end - 1).toRadixString(16).toUpperCase()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? MediaColors.amber.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: selected
              ? MediaColors.amber
              : MediaColors.teal.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: MediaType.coordinate(
          selected ? MediaColors.amber : MediaColors.teal,
        ).copyWith(fontSize: 10),
      ),
    );
  }
}

/// 一个标签行（key 保留英文原名，不翻译）。
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final text = formatFieldValue(tag.value);
    return _CopyableRow(
      value: formatCopiedTagValue(tag),
      child: _Hoverable(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: Text(
                  tag.key,
                  style: MediaType.value(MediaColors.teal),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: _ValueText(text: text, align: TextAlign.right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 值文本：等宽、超长截断并挂 tooltip（完整值仍可通过右键复制拿到，不丢信息）。
class _ValueText extends StatelessWidget {
  const _ValueText({required this.text, required this.align});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final style = MediaType.value(MediaColors.chalk);
    final widget = Text(
      text,
      style: style,
      textAlign: align,
      // 单行 + 省略号：长值（文件名、编码器串）不该把行撑成两截。
      // 完整值仍可通过悬停看到、右键复制拿到，不丢信息。
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (text.length <= _kTruncateThreshold) return widget;
    return Tooltip(message: text, child: widget);
  }
}

/// 悬停时给行一点底色，让长列表好扫读。
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.child});

  final Widget child;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // 尊重系统的"减少动态效果"：开了就把过渡时长压到 0。
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 90),
        color: _hovered ? MediaColors.panelHigh : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// 整行可右键复制的包装。
///
/// 右键 → 弹出「复制」菜单 → 点了就把这一行的值复制到剪贴板
/// （user story 16）。
class _CopyableRow extends StatelessWidget {
  const _CopyableRow({required this.value, required this.child});

  /// 右键复制时写进剪贴板的文本。
  final String value;

  /// 行的内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (TapDownDetails details) =>
          _copyValueFromMenu(context, details.globalPosition, value),
      child: child,
    );
  }
}

/// 弹出「复制」菜单，点了就把 [value] 复制到剪贴板并给出提示。
Future<void> _copyValueFromMenu(
  BuildContext context,
  Offset globalPosition,
  String value,
) async {
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: const <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: _kCopyMenuValue,
        child: Text(_kCopyMenuLabel),
      ),
    ],
  );
  if (selected != _kCopyMenuValue) return;

  await copyTextToClipboard(value);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$_kCopiedMessage：$value')));
}

/// 空区段的提示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text, style: MediaType.note(MediaColors.chalkFaint)),
    );
  }
}

/// 把字段值格式化成界面上的文本。
///
/// - `null` → 「—」；
/// - 整数按整数显示，整数值的小数不显示小数尾巴；
/// - 字节串 → 「（N 字节）」；
/// - **短列表展开显示**（`isom, iso2, avc1, mp41`），长列表才折叠成「（N 项）」——
///   折叠会把 `compatible_brands` 这类信息直接丢掉；
/// - 布尔值 → 「是」/「否」。
String formatFieldValue(Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? '是' : '否';
  if (value is double) {
    if (!value.isFinite) return value.toString();
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(3);
  }
  if (value is num) return value.toString();
  if (value is Uint8List) return '（${value.length} 字节）';
  if (value is List) {
    if (value.isEmpty) return '（空）';
    final simple = value.every(
      (Object? item) =>
          item == null || item is num || item is String || item is bool,
    );
    if (simple && value.length <= 6) {
      return value.map((Object? item) => item?.toString() ?? '—').join(', ');
    }
    return '（${value.length} 项）';
  }
  if (value is Map) return '（${value.length} 项）';
  return value.toString();
}
