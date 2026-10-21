/// 一个标签页的解析状态与视图。
///
/// 每个标签页**独立**持有自己的解析状态（解析中 / 解析成功 / 解析失败），
/// 关闭一个标签不影响其它标签。
library;

import 'package:flutter/material.dart';

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

/// 一个标签页：持有解析状态，并把结果回调给外壳。
///
/// 外壳（`app.dart`）用 [onStateChanged] 拿到解析结果，
/// 再用 [builder] 决定这一页显示什么——**右栏的装配在 app.dart 里**。
class DocumentTab extends StatefulWidget {
  const DocumentTab({
    super.key,
    required this.path,
    required this.builder,
    this.onStateChanged,
  });

  /// 本标签页对应的文件路径。
  final String path;

  /// 由外壳决定这一页显示什么。
  final Widget Function(BuildContext context, DocumentTabState state) builder;

  /// 解析状态变化时回调（解析完成时触发一次）。
  final ValueChanged<DocumentTabState>? onStateChanged;

  @override
  State<DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<DocumentTab> {
  late final Future<ParsedDocument> _future = _parse();

  Future<ParsedDocument> _parse() {
    final future = parseFileInIsolate(widget.path);
    future.then(
      (ParsedDocument document) {
        _emit(
          DocumentTabState(
            path: widget.path,
            status: DocumentStatus.ready,
            document: document,
          ),
        );
      },
      onError: (Object error) {
        _emit(
          DocumentTabState(
            path: widget.path,
            status: DocumentStatus.failed,
            error: '解析失败：$error',
          ),
        );
      },
    );
    return future;
  }

  void _emit(DocumentTabState state) {
    if (!mounted) return;
    widget.onStateChanged?.call(state);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ParsedDocument>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<ParsedDocument> snapshot) {
        final state = _stateOf(snapshot);
        return widget.builder(context, state);
      },
    );
  }

  DocumentTabState _stateOf(AsyncSnapshot<ParsedDocument> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return DocumentTabState(
        path: widget.path,
        status: DocumentStatus.loading,
      );
    }
    if (snapshot.hasError) {
      return DocumentTabState(
        path: widget.path,
        status: DocumentStatus.failed,
        error: '解析失败：${snapshot.error}',
      );
    }
    return DocumentTabState(
      path: widget.path,
      status: DocumentStatus.ready,
      document: snapshot.data,
    );
  }
}

/// 一个标签页的默认视图：左栏语义字段 + 右栏（由外壳传入）。
///
/// [rightPane] 是右栏的插槽——结构树视图与 hex 面板由实现票 21 装进去。
class DocumentTabBody extends StatelessWidget {
  const DocumentTabBody({
    super.key,
    required this.state,
    required this.rightPane,
  });

  /// 当前标签页的状态。
  final DocumentTabState state;

  /// 右栏（结构树 + hex）的占位组件。
  final Widget rightPane;

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
            Expanded(child: SemanticView(document: document)),
            const VerticalDivider(width: 1),
            Expanded(flex: 2, child: rightPane),
          ],
        );
    }
  }
}

/// 标签页里的整页消息（解析中 / 解析失败）。
class DocumentTabMessage extends StatelessWidget {
  const DocumentTabMessage(this.message, {super.key, this.icon});

  /// 消息文案（中文）。
  final String message;

  /// 可选的图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
