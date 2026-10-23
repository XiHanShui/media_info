/// 一个标签页的解析状态与视图。
///
/// 每个标签页**独立**持有自己的解析状态（解析中 / 解析成功 / 解析失败），
/// 关闭一个标签不影响其它标签。
///
/// 注意：解析本身在**外壳**（`app.dart`）里发起，状态也由外壳按路径缓存。
/// 这样关闭一个标签页时，剩下标签页的解析结果不会被连带丢掉——
/// 早先由本组件自己解析，`IndexedStack` 的子节点被 Flutter 包在**没有 key 的
/// `Visibility`** 里，只能按位置匹配，关掉一个标签就会让剩下的标签整体重建、
/// 重新解析一遍（界面上闪回「解析中…」）。
library;

import 'package:flutter/material.dart';

import '../core/node.dart';
import 'parse_service.dart';
import 'semantic_view.dart';

/// 一个标签页的解析状态。
enum DocumentStatus {
  /// 正在解析。
  loading,

  /// 解析完成（可能带错误说明，例如文件被截断）。
  ready,

  /// 解析过程本身失败。
  failed,
}

/// 一个标签页的状态快照。
class DocumentTabState {
  const DocumentTabState({
    required this.path,
    required this.status,
    this.document,
    this.error,
  });

  /// 标签页对应的文件路径。
  final String path;

  /// 解析状态。
  final DocumentStatus status;

  /// 解析结果（`status == [DocumentStatus.ready]` 时有值）。
  final ParsedDocument? document;

  /// 中文错误说明。
  final String? error;
}

/// 一个标签页的视图：只负责把状态画出来。
///
/// 解析在**外壳**里做（见 `app.dart`），这里不持有任何解析状态。
class DocumentTab extends StatelessWidget {
  const DocumentTab({
    super.key,
    required this.path,
    required this.state,
    required this.builder,
  });

  /// 本标签页对应的文件路径。
  final String path;

  /// 当前的解析状态。
  final DocumentTabState state;

  /// 由外壳决定这一页显示什么——**右栏的装配在 app.dart 里**。
  final Widget Function(BuildContext context, DocumentTabState state) builder;

  @override
  Widget build(BuildContext context) => builder(context, state);
}

/// 一个标签页的主体：左边的字段视图 + 右边的装配区。
class DocumentTabBody extends StatelessWidget {
  const DocumentTabBody({
    super.key,
    required this.state,
    required this.rightPane,
    this.selectedField,
    this.onFieldSelected,
  });

  /// 当前状态。
  final DocumentTabState state;

  /// 右栏（结构树 + hex + 播放器）。
  final Widget rightPane;

  /// 左栏当前选中的字段（用来点亮它的字节范围标签）。
  final SemanticField? selectedField;

  /// 左栏选中字段时的回调。
  final ValueChanged<SemanticField?>? onFieldSelected;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case DocumentStatus.loading:
        return const DocumentTabMessage('解析中…');
      case DocumentStatus.failed:
        return DocumentTabMessage(state.error ?? '解析失败');
      case DocumentStatus.ready:
        final document = state.document;
        if (document == null) {
          return const DocumentTabMessage('解析失败');
        }
        if (document.detectedFormat == null && document.error == null) {
          // 不是媒体文件：由外壳（app.dart）渲染「无法识别的文件格式」状态。
          return const DocumentTabMessage('无法识别的文件格式');
        }
        if (document.detectedFormat == null) {
          // 文件不存在 / 打不开：这一页自己的错误，不影响其它标签页。
          return DocumentTabMessage(document.error ?? '无法打开文件');
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: SemanticView(
                document: document,
                selectedField: selectedField,
                onFieldSelected: onFieldSelected,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(flex: 2, child: rightPane),
          ],
        );
    }
  }
}

/// 一个居中的状态提示。
class DocumentTabMessage extends StatelessWidget {
  const DocumentTabMessage(this.message, {super.key, this.icon});

  /// 提示文字。
  final String message;

  /// 可选的图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
