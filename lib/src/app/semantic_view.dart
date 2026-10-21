/// 左栏：语义字段视图。
///
/// 三个区段，顺序固定：「文件级」→「轨道级」（每条轨道一组）→「标签」。
/// 区段之间用分隔线，**不折叠**。
///
/// 字段行：左 = 中文显示名（`label`），右 = 值（`value`）与单位（`unit`）。
/// **推算值**（`origin == FieldOrigin.derived`）必须有视觉区分——标签后加「（推算）」
/// 并用次要颜色，用户要能一眼分出"文件里写的"和"我们算的"（user story 15）。
///
/// 英文技术名（`key`）不翻译，作为次要信息显示在中文显示名下面
/// （user story 47：字段名保持英文原词）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/node.dart';
import '../core/tag.dart';
import 'export.dart';
import 'parse_service.dart';

/// 推算值标记的后缀。
const String kDerivedSuffix = '（推算）';

/// 右键菜单里「复制」这一项的值。
const String _kCopyMenuValue = 'copy';

/// 右键菜单里「复制」这一项的文案。
const String _kCopyMenuLabel = '复制';

/// 复制成功后的提示文案前缀。
const String _kCopiedMessage = '已复制';

/// 左栏：语义字段视图。
class SemanticView extends StatelessWidget {
  const SemanticView({super.key, required this.document});

  /// 已解析的文件。
  final ParsedDocument document;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        const _SectionHeader('文件级'),
        if (document.fileFields.isEmpty)
          const _EmptyHint('没有文件级字段')
        else
          for (final field in document.fileFields) _FieldRow(field: field),
        const Divider(height: 24),
        const _SectionHeader('轨道级'),
        if (document.tracks.isEmpty)
          const _EmptyHint('没有轨道级字段')
        else
          for (final track in document.tracks) ...<Widget>[
            _TrackHeader(trackIndex: track.trackIndex),
            for (final field in track.fields) _FieldRow(field: field),
          ],
        const Divider(height: 24),
        const _SectionHeader('标签'),
        if (document.tags.isEmpty)
          const _EmptyHint('没有标签')
        else
          for (final tag in document.tags) _TagRow(tag: tag),
      ],
    );
  }
}

/// 区段标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 轨道分组标题（如「轨道 0」）。
class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.trackIndex});

  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        '轨道 $trackIndex',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 一个语义字段行。
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final SemanticField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final derived = field.origin == FieldOrigin.derived;

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: derived
          ? theme.colorScheme.onSurfaceVariant
          : theme.colorScheme.onSurface,
      fontStyle: derived ? FontStyle.italic : FontStyle.normal,
    );
    final keyStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.outline,
      fontFamily: 'monospace',
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
    );
    final unitStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return _CopyableRow(
      value: formatCopiedFieldValue(field),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Flexible(child: Text(field.label, style: labelStyle)),
                      if (derived) ...<Widget>[
                        const SizedBox(width: 4),
                        Text(
                          kDerivedSuffix,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(field.key, style: keyStyle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 值用 Flexible：长值换行，不撑破左栏。
            Flexible(
              flex: 2,
              child: Text(
                formatFieldValue(field.value),
                style: valueStyle,
                textAlign: TextAlign.right,
              ),
            ),
            if (field.unit != null && field.unit!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(field.unit!, style: unitStyle),
              ),
          ],
        ),
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
    final theme = Theme.of(context);
    return _CopyableRow(
      value: formatCopiedTagValue(tag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Text(
                tag.key,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Text(
                formatFieldValue(tag.value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 把字段值格式化成界面上的文本。
///
/// - `null` → 「—」；
/// - 整数按整数显示，整数值的小数不显示小数尾巴；
/// - 字节串 → 「（N 字节）」，列表 → 「（N 项）」；
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
  if (value is List) return '（${value.length} 项）';
  if (value is Map) return '（${value.length} 项）';
  return value.toString();
}
