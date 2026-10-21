/// 应用骨架：窗口 + 标签页 + 打开文件 + 左栏语义字段视图。
///
/// 布局（见 `docs/design/ui-layout.md`）：
///
/// ```text
/// ┌──────────────────────────────────────────────┐
/// │ 标签页栏（每个标签 = 一个打开的文件）           │
/// ├──────────────────────────────────────────────┤
/// │ 工具条：打开文件 / 导出 JSON                   │
/// ├──────────────────────────────────────────────┤
/// │ 扩展名不一致提示（可选）                        │
/// ├───────────────────┬──────────────────────────┤
/// │ 左：语义字段视图    │ 右：结构树视图             │
/// │ 文件级/轨道级/标签  │      + hex 面板（下方）    │
/// └───────────────────┴──────────────────────────┘
/// ```
///
/// **右栏的装配位置**是 [StructurePane]（实现票 21 的结构树视图 + hex 面板）——
/// 装在 [_buildTabContent] 里。
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/structure_pane.dart';
import 'document_tab.dart';
import 'parse_service.dart';

/// 导出 JSON 的处理器。
///
/// 实现票 22 会提供 `export.dart` 里的实现，并通过 [MediaInfoApp.onExportJson]
/// 接进来。现在还没有实现，所以工具条上的按钮是禁用的。
typedef ExportJsonHandler = Future<void> Function(ParsedDocument document);

/// 根 Widget：MaterialApp + 主题。
class MediaInfoApp extends StatelessWidget {
  const MediaInfoApp({
    super.key,
    this.onExportJson,
    this.initialPaths = const <String>[],
  });

  /// 导出 JSON 的处理器（可为空 = 还没接上导出功能）。
  final ExportJsonHandler? onExportJson;

  /// 启动时预打开的文件路径（每个路径一个标签页）。
  ///
  /// 正式运行时用环境变量 `MEDIA_INFO_OPEN_FILES`；这个参数是给测试与
  /// 集成用的等价入口（文件选择对话框是系统窗口，测不了）。
  final List<String> initialPaths;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media_info',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AppShell(onExportJson: onExportJson, initialPaths: initialPaths),
    );
  }
}

/// 应用主题。
ThemeData _buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B6EA5));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}

/// 窗口骨架：标签页栏 + 工具条 + 主体。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.onExportJson,
    this.initialPaths = const <String>[],
  });

  /// 导出 JSON 的处理器。
  final ExportJsonHandler? onExportJson;

  /// 启动时预打开的文件路径（每个路径一个标签页）。
  ///
  /// 正式运行时用环境变量 `MEDIA_INFO_OPEN_FILES`；这个参数是给测试与
  /// 集成用的等价入口。
  final List<String> initialPaths;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 打开的标签页（每个标签 = 一个文件路径）。
  final List<String> _paths = <String>[];

  /// 每个标签页的解析状态。
  final Map<String, DocumentTabState> _states = <String, DocumentTabState>{};

  /// 当前选中的标签页。
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // 文件注入点：应用启动时读环境变量 MEDIA_INFO_OPEN_FILES，
    // 按顺序预打开这些文件并各开一个标签页。
    // 路径不存在时那个标签页显示"文件不存在"，不影响其它标签页。
    final injected = <String>[
      ...widget.initialPaths,
      ...readOpenFilesFromEnvironment(),
    ];
    for (var index = 0; index < injected.length; index++) {
      _addTab(injected[index], select: index == 0);
    }
  }

  /// 加一个标签页（不触发 rebuild）。
  void _addTab(String path, {required bool select}) {
    _paths.add(path);
    _states[path] = DocumentTabState(
      path: path,
      status: DocumentStatus.loading,
    );
    if (select) _selectedIndex = _paths.length - 1;
  }

  /// 打开一个文件（拖放 / 文件选择器）。
  void _openPath(String path) {
    if (path.isEmpty) return;
    setState(() {
      final existing = _paths.indexOf(path);
      if (existing >= 0) {
        _selectedIndex = existing;
        return;
      }
      _addTab(path, select: true);
    });
  }

  /// 关闭一个标签页（不影响其它标签页）。
  void _closeTab(int index) {
    setState(() {
      final path = _paths.removeAt(index);
      _states.remove(path);
      if (_selectedIndex >= _paths.length) {
        _selectedIndex = _paths.length - 1;
      }
      if (_selectedIndex < 0) _selectedIndex = 0;
    });
  }

  /// `Ctrl+Tab`：切到下一个标签页。
  void _selectNextTab() {
    if (_paths.length < 2) return;
    setState(() {
      _selectedIndex = (_selectedIndex + 1) % _paths.length;
    });
  }

  /// 当前标签页的解析结果。
  ParsedDocument? get _currentDocument {
    if (_paths.isEmpty) return null;
    return _states[_paths[_selectedIndex]]?.document;
  }

  /// 当前标签页的扩展名提示。
  String? get _currentWarning => _currentDocument?.extensionWarning;

  /// 弹出文件选择器。
  Future<void> _pickFiles() async {
    const typeGroup = XTypeGroup(
      label: '媒体文件',
      extensions: <String>[
        'wav',
        'wave',
        'aiff',
        'aif',
        'aifc',
        'flac',
        'mp3',
        'mp4',
        'm4v',
        'm4a',
        'mov',
        'qt',
        'mkv',
        'webm',
        'mka',
        'mks',
      ],
    );
    List<XFile> files;
    try {
      files = await openFiles(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (_) {
      // 系统对话框被取消或不可用：不做任何事，不崩。
      return;
    }
    for (final file in files) {
      _openPath(file.path);
    }
  }

  /// 导出 JSON（实现票 22 接上 `export.dart` 之后才真正可用）。
  Future<void> _exportJson() async {
    final handler = widget.onExportJson;
    final document = _currentDocument;
    if (handler == null || document == null) return;
    await handler(document);
  }

  void _onTabStateChanged(DocumentTabState state) {
    if (!mounted) return;
    setState(() {
      _states[state.path] = state;
    });
  }

  /// 决定一个标签页显示什么——**右栏的装配位置在这里**。
  Widget _buildTabContent(BuildContext context, DocumentTabState state) {
    final document = state.document;
    if (state.status == DocumentStatus.ready &&
        document != null &&
        document.detectedFormat == null &&
        document.error == null) {
      // 完全不是媒体的文件：「无法识别的文件格式」。
      return _UnrecognizedFormatPane(path: state.path);
    }
    return DocumentTabBody(
      state: state,
      rightPane: StructurePane(
        filePath: state.path,
        root: document?.root,
        loader: parseStructureAtDepth,
        resetToken: _selectedIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            _selectNextTab,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: <Widget>[
              _buildTabStrip(),
              _buildToolbar(),
              if (_currentWarning != null)
                _WarningBanner(message: _currentWarning!),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  /// 标签页栏。
  Widget _buildTabStrip() {
    final theme = Theme.of(context);
    if (_paths.isEmpty) {
      return Container(
        height: 34,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Text(
          '未打开文件',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      height: 34,
      color: theme.colorScheme.surfaceContainerHigh,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _paths.length,
        itemBuilder: (BuildContext context, int index) {
          final path = _paths[index];
          final selected = index == _selectedIndex;
          return _TabButton(
            label: _fileNameOf(path),
            selected: selected,
            onTap: () => setState(() => _selectedIndex = index),
            onClose: () => _closeTab(index),
          );
        },
      ),
    );
  }

  /// 工具条：打开文件 / 导出 JSON。
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('打开文件'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _currentDocument == null ? null : _exportJson,
            icon: const Icon(Icons.data_object),
            label: const Text('导出 JSON'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// 主体。
  Widget _buildBody() {
    if (_paths.isEmpty) {
      return _EmptyState(onOpen: _pickFiles);
    }
    return DragTarget<Object>(
      onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
          _pathsOf(details.data).isNotEmpty,
      onAcceptWithDetails: (DragTargetDetails<Object> details) {
        for (final path in _pathsOf(details.data)) {
          _openPath(path);
        }
      },
      builder:
          (
            BuildContext context,
            List<Object?> candidate,
            List<Object?> rejected,
          ) {
            return IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                for (final path in _paths)
                  DocumentTab(
                    key: ValueKey<String>(path),
                    path: path,
                    builder: _buildTabContent,
                    onStateChanged: _onTabStateChanged,
                  ),
              ],
            );
          },
    );
  }
}

/// 扩展名与实际格式不一致的提示条。
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个标签页按钮。
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 14),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: '关闭标签页',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 没有打开任何文件时的空态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.movie_filter_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('没有打开的文件', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            '把媒体文件拖进来，或点「打开文件」',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open),
            label: const Text('打开文件'),
          ),
        ],
      ),
    );
  }
}

/// 「无法识别的文件格式」状态。
class _UnrecognizedFormatPane extends StatelessWidget {
  const _UnrecognizedFormatPane({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.help_outline,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('无法识别的文件格式', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            path,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 取路径里的文件名（不含目录）。
String _fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

/// 从拖放数据里取出文件路径。
List<String> _pathsOf(Object? data) {
  if (data is String) return <String>[data];
  if (data is List) return data.whereType<String>().toList();
  return const <String>[];
}
