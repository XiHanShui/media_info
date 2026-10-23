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
import '../core/node.dart';
import 'document_tab.dart';
import 'file_strip.dart';
import 'player/player_panel.dart';
import 'position_service.dart';
import 'theme.dart';
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
    this.scaffoldMessengerKey,
  });

  /// 导出 JSON 的处理器（可为空 = 还没接上导出功能）。
  final ExportJsonHandler? onExportJson;

  /// 启动时预打开的文件路径（每个路径一个标签页）。
  ///
  /// 正式运行时用环境变量 `MEDIA_INFO_OPEN_FILES`；这个参数是给测试与
  /// 集成用的等价入口（文件选择对话框是系统窗口，测不了）。
  final List<String> initialPaths;

  /// SnackBar 的载体。
  ///
  /// 调用方（例如 `main.dart` 里的导出处理器）拿它来提示「已导出到 …」——
  /// 导出是个没有返回值的事件，不给用户反馈的话没法确认成没成。
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media_info',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: AppShell(onExportJson: onExportJson, initialPaths: initialPaths),
    );
  }
}

/// 应用主题：暗色仪器面板（见 `docs/design/visual-language.md`）。
ThemeData _buildTheme() => buildMediaTheme();

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

  /// 加一个标签页（不触发 rebuild），并**在这里发起解析**。
  ///
  /// 解析放在外壳而不是标签页组件里：`IndexedStack` 的子节点被 Flutter 包在
  /// **没有 key 的 `Visibility`** 里，只能按位置匹配——关掉一个标签，剩下的标签
  /// 会被整体重建、由标签页组件自己重新解析一遍（界面闪回「解析中…」）。
  /// 状态由外壳按路径缓存，就不会连带重来。
  void _addTab(String path, {required bool select}) {
    _paths.add(path);
    _states[path] = DocumentTabState(
      path: path,
      status: DocumentStatus.loading,
    );
    if (select) _selectedIndex = _paths.length - 1;

    parseFileInIsolate(path).then(
      (ParsedDocument document) {
        if (!mounted) return;
        setState(() {
          _states[path] = DocumentTabState(
            path: path,
            status: DocumentStatus.ready,
            document: document,
          );
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _states[path] = DocumentTabState(
            path: path,
            status: DocumentStatus.failed,
            error: '解析失败：$error',
          );
        });
      },
    );
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
      _selectedNode = null;
      _playheadOffset = null;
    });
  }

  /// 当前标签页的解析结果。
  ParsedDocument? get _currentDocument {
    if (_paths.isEmpty) return null;
    return _states[_paths[_selectedIndex]]?.document;
  }

  /// 当前标签页的扩展名提示。
  String? get _currentWarning => _currentDocument?.extensionWarning;

  /// 当前标签页的截断/损坏提示。
  ///
  /// 引擎在读到字节不足时会给出中文说明（"文件在偏移 X 处截断，声明长度还差 N 字节"），
  /// 但**已解析的部分结构仍然有效**——所以这是警告，不是错误：界面照常显示字段与结构树。
  String? get _currentParseWarning {
    final document = _currentDocument;
    if (document == null) return null;
    // 根本没能打开或识别文件（打不开、不是媒体）——那是错误状态，不是"解析途中出问题"，
    // 由各自的空态/错误页负责，这里不再重复提示。
    if (document.detectedFormat == null) return null;
    if (!document.truncated && document.error == null) return null;
    return document.error ?? '文件被截断';
  }

  /// 当前标签页里选中的块（胶片条与结构树共享）。
  ContainerNode? _selectedNode;

  /// 播放器面板是否展开。
  bool _showPlayer = false;

  /// 播放头当前所在的字节偏移（用来在结构树里高亮当前块）。
  int? _playheadOffset;

  /// 左栏当前选中的语义字段——它的字节范围会在右边的 hex 面板里高亮。
  SemanticField? _selectedField;

  /// 胶片条：顶层块按比例排开。
  Widget _buildFileStrip() {
    final document = _currentDocument;
    if (document?.root == null) return const SizedBox.shrink();
    return FileStrip(
      root: document!.root,
      selected: _selectedNode,
      onSelect: (ContainerNode node) => setState(() => _selectedNode = node),
    );
  }

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
      selectedField: _selectedField,
      onFieldSelected: (SemanticField? field) =>
          setState(() => _selectedField = field),
      rightPane: StructurePane(
        filePath: state.path,
        root: document?.root,
        loader: parseStructureAtDepth,
        resetToken: _selectedIndex,
        selectedNode: _selectedNode,
        playheadOffset: _playheadOffset,
        highlight: _selectedField?.byteRange,
        highlightLabel: _selectedField == null
            ? null
            : '${_selectedField!.label}（${_selectedField!.key}）',
        onNodeSelected: (ContainerNode node) =>
            setState(() => _selectedNode = node),
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
              if (_currentParseWarning != null)
                _WarningBanner(message: _currentParseWarning!, kind: _WarningKind.parse),
              _buildFileStrip(),
              Expanded(child: _buildBody()),
              if (_showPlayer) _buildPlayer(),
            ],
          ),
        ),
      ),
    );
  }

  /// 标签页栏。
  Widget _buildTabStrip() {
    if (_paths.isEmpty) {
      return Container(
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: MediaColors.panel,
        child: Text(
          '未打开文件',
          style: MediaType.note(MediaColors.chalkFaint),
        ),
      );
    }
    return Container(
      height: 36,
      color: MediaColors.panel,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: <Widget>[
          _FlatButton(
            icon: Icons.folder_open,
            label: '打开文件',
            onPressed: _pickFiles,
          ),
          const SizedBox(width: 8),
          _FlatButton(
            icon: Icons.data_object,
            label: '导出 JSON',
            onPressed: _currentDocument == null ? null : _exportJson,
          ),
          const SizedBox(width: 8),
          _FlatButton(
            icon: Icons.play_circle_outline,
            label: _showPlayer ? '收起播放器' : '播放',
            onPressed: _currentDocument == null
                ? null
                : () => setState(() {
                      _showPlayer = !_showPlayer;
                      _playheadOffset = null;
                    }),
          ),
          const Spacer(),
          if (_currentDocument != null)
            Text(
              _fileNameOf(_currentDocument!.path),
              style: MediaType.note(MediaColors.chalkFaint),
            ),
        ],
      ),
    );
  }

  /// 底部的播放器条（固定高度，不把上面的结构树挤没）。
  Widget _buildPlayer() {
    final document = _currentDocument;
    if (document == null) return const SizedBox.shrink();
    final hasVideo = _hasVideoTrack(document);
    return SizedBox(
      height: kPlayerBarHeight,
      child: PlayerPanel(
        path: document.path,
        positionIndex: positionIndexOf(document),
        selectedOffset: _selectedNode?.offset,
        hasVideo: hasVideo,
        onPositionOffset: (int? offset) => setState(() => _playheadOffset = offset),
      ),
    );
  }

  /// 这个文件里有没有视频轨。
  bool _hasVideoTrack(ParsedDocument document) {
    for (final track in document.tracks) {
      for (final field in track.fields) {
        if (field.key == 'track_type' && field.value == 'video') return true;
      }
    }
    return false;
  }

  /// 主体。
  Widget _buildBody() {
    // 空态**也要接拖放**——空态上写着"把媒体文件拖进来"，
    // 接不住就是骗人。
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
            if (_paths.isEmpty) {
              return _EmptyState(onOpen: _pickFiles);
            }
            return IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                for (final path in _paths)
                  DocumentTab(
                    key: ValueKey<String>(path),
                    path: path,
                    state:
                        _states[path] ??
                        DocumentTabState(
                          path: path,
                          status: DocumentStatus.loading,
                        ),
                    builder: _buildTabContent,
                  ),
              ],
            );
          },
    );
  }
}

/// 警告条：扩展名与实际格式不符 / 文件被截断。
///
/// 两种都是**警告不是错误**——解析照实际内容走，已读到的部分照常显示。
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message, this.kind = _WarningKind.extension});

  final String message;
  final _WarningKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MediaColors.rose.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 15, color: MediaColors.rose),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: MediaType.note(MediaColors.rose)),
          ),
        ],
      ),
    );
  }
}

/// 警告的种类（决定图标与措辞）。
enum _WarningKind { extension, parse }

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
    return Material(
      color: selected ? MediaColors.ink : MediaColors.panel,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? MediaColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: MediaType.value(
                  selected ? MediaColors.chalk : MediaColors.chalkDim,
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 13),
                iconSize: 13,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    color: MediaColors.chalkFaint,
                tooltip: '关闭标签页',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 平面按钮：发丝描边、无阴影、无圆角胶囊——仪器面板的味道。
class _FlatButton extends StatelessWidget {
  const _FlatButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? MediaColors.chalkDim : MediaColors.chalkFaint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: MediaColors.edge),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: MediaType.label(color)),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.movie_filter_outlined,
            size: 34,
            color: MediaColors.chalkFaint,
          ),
          const SizedBox(height: 14),
          Text('没有打开的文件', style: MediaType.label(MediaColors.chalkDim)),
          const SizedBox(height: 6),
          Text(
            '把媒体文件拖进来，或点「打开文件」',
            style: MediaType.note(MediaColors.chalkFaint),
          ),
          const SizedBox(height: 16),
          _FlatButton(
            icon: Icons.folder_open,
            label: '打开文件',
            onPressed: onOpen,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.help_outline,
            size: 30,
            color: MediaColors.chalkFaint,
          ),
          const SizedBox(height: 12),
          Text('无法识别的文件格式', style: MediaType.label(MediaColors.chalkDim)),
          const SizedBox(height: 6),
          Text(path, style: MediaType.note(MediaColors.chalkFaint)),
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
