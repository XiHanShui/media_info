/// 应用级 widget 测试：启动**真实应用**，喂**真实素材**，断言渲染结果。
///
/// 接缝是 [MediaInfoApp.initialPaths]——与 `MEDIA_INFO_OPEN_FILES` 环境变量
/// 等价的进程内入口（文件选择对话框是系统窗口，测不了）。
///
/// 断言的都是**外部可观察的行为**（界面上渲染出了什么），不碰内部实现。
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/app.dart';
import 'package:media_info/src/ui/hex_view.dart';
import 'package:media_info/src/ui/structure_tree.dart';

/// 真实素材：H.264 + AAC 的 MP4。
const String mp4Fixture = 'test/fixtures/mp4_h264_aac_320x240.normal.mp4';

/// 真实素材：同一个 MP4 被截断的版本。
const String truncatedMp4Fixture =
    'test/fixtures/mp4_h264_aac_320x240.normal.truncated.mp4';

/// 真实素材：PCM 的 WAV。
const String wavFixture = 'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav';

/// 启动应用并等解析完成。
///
/// 解析跑在 isolate 里，测试环境的 fake async 不会让它前进——必须先
/// `runAsync` 让出真实时间，界面才会从「解析中…」切到真正的内容。
Future<void> _pumpApp(
  WidgetTester tester,
  List<String> paths, {
  Size size = const Size(1400, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MediaInfoApp(initialPaths: paths));
  await _waitForParse(tester);
}

/// 等到当前标签页解析完（「解析中…」消失）。
Future<void> _waitForParse(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    if (find.text('解析中…').evaluate().isEmpty) return;
  }
  fail('等待解析完成超时');
}

/// 结构树里的某一行（按块类型名定位）。
Finder _treeRow(String type) =>
    find.descendant(of: find.byType(StructureTree), matching: find.text(type));

/// hex 面板里的一个文本。
Finder _hexText(String text) =>
    find.descendant(
      of: find.byType(HexView),
      matching: find.text(text, findRichText: true),
    );

/// 造一个临时文件，返回路径。
String _tempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_app_widget');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

/// 把字节格式化成大写十六进制串（独立于实现，用来核对 hex 面板的内容）。
String _hexOf(List<int> bytes) => bytes
    .map((int byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0'))
    .join(' ');

/// 记录写进剪贴板的文本。
final List<String> _clipboard = <String>[];

/// 让剪贴板调用可断言（测试环境里没有真的剪贴板）。
void _mockClipboard(WidgetTester tester) {
  _clipboard.clear();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        _clipboard.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  group('语义字段视图', () {
    testWidgets('打开真实素材后显示中文显示名与值', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      // 三个区段都在。
      expect(find.text('文件级'), findsOneWidget);
      expect(find.text('轨道级'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);

      // 文件级：解析服务统一补齐的字段 + 提取器读到的字段。
      expect(find.text('文件名'), findsOneWidget);
      expect(find.text('文件大小'), findsOneWidget);
      expect(find.text('容器格式'), findsOneWidget);
      // `isom` 既是容器格式也是 major brand，所以不止一处。
      expect(find.text('isom'), findsWidgets, reason: 'MP4 的 major brand');

      // 轨道级：每条轨道一组。
      expect(find.text('轨道 0'), findsOneWidget);
      expect(find.text('轨道 1'), findsOneWidget);

      // 轨道字段：显示名是中文，值保持原样。
      expect(find.text('编码标识'), findsWidgets);
      expect(find.text('avc1'), findsOneWidget, reason: '视频轨的 codec');
      expect(find.text('采样率'), findsOneWidget);
      expect(find.text('44100'), findsWidgets, reason: '音频轨的采样率');
    });

    testWidgets('推算出来的值有视觉区分', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      // 平均码率是我们算的，不是文件里写的。
      expect(find.text('平均码率'), findsOneWidget);
      expect(find.text('（推算）'), findsWidgets);
    });

    // 已知缺陷：解析服务调用 `collectTags` 时没有传字节源
    // （`lib/src/app/parse_service.dart`），于是标签载荷解不出来，
    // 应用里的「标签」区段恒为空。缺陷修好前先跳过这条——它描述的是应有行为。
    testWidgets('标签区段显示文件里写下的标签', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      expect(find.text('没有标签'), findsNothing);
      expect(find.text('©too'), findsOneWidget);
    });
  });

  group('结构树', () {
    testWidgets('列出素材的顶层块类型', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      expect(_treeRow('ftyp'), findsOneWidget);
      expect(_treeRow('free'), findsOneWidget);
      expect(_treeRow('mdat'), findsOneWidget);
      expect(_treeRow('moov'), findsOneWidget);
    });
  });

  group('hex 面板', () {
    testWidgets('选中一个块后 hex 面板出现，显示类型、偏移与大小', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      // 没选中块时没有 hex 面板。
      expect(find.byType(HexView), findsNothing);

      await tester.tap(_treeRow('ftyp'));
      await tester.pumpAndSettle();

      expect(find.byType(HexView), findsOneWidget);
      expect(_hexText('ftyp'), findsOneWidget);
      expect(_hexText('偏移 0'), findsOneWidget);
      expect(_hexText('大小 32'), findsOneWidget);
    });

    testWidgets('hex 里的字节与文件里该偏移处的字节一致', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[mp4Fixture]);

      await tester.tap(_treeRow('ftyp'));
      await tester.pumpAndSettle();

      // `ftyp` 在文件里的开头：00 00 00 20 66 74 79 70 ...
      final bytes = File(mp4Fixture).readAsBytesSync();
      final expected = _hexOf(bytes.sublist(0, 16));

      expect(
        find.descendant(
          of: find.byType(HexView),
          matching: find.textContaining(expected, findRichText: true),
        ),
        findsOneWidget,
        reason: 'hex 面板显示的应该是文件偏移 0 处的 16 个字节',
      );
    });
  });

  group('异常与提示', () {
    testWidgets('扩展名与实际格式不符：给出提示，且仍按实际格式解析', (WidgetTester tester) async {
      final path = _tempFile(
        'actually_mp4.wav',
        File(mp4Fixture).readAsBytesSync(),
      );

      await _pumpApp(tester, <String>[path]);

      expect(find.text('扩展名 `.wav` 与实际格式 `MP4` 不符'), findsOneWidget);
      // 提示是提示，解析照实际内容走：仍然按 MP4 解析。
      expect(find.text('容器格式'), findsOneWidget);
      expect(find.text('isom'), findsWidgets);
      expect(find.text('编码标识'), findsWidgets);
      expect(find.text('avc1'), findsOneWidget);
    });

    testWidgets('被截断的文件：不崩溃，显示截断说明，仍显示读到的字段', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[truncatedMp4Fixture]);

      expect(tester.takeException(), isNull, reason: '截断的文件不该让应用崩掉');

      // 截断说明。
      expect(find.textContaining('截断'), findsOneWidget);

      // 已经读到的部分照常显示。
      expect(find.text('文件名'), findsOneWidget);
      expect(find.text('容器格式'), findsOneWidget);
      expect(find.text('isom'), findsWidgets);
      expect(_treeRow('ftyp'), findsOneWidget);
    });

    testWidgets('不是媒体的文件：显示「无法识别的文件格式」', (WidgetTester tester) async {
      final path = _tempFile('notes.txt', '普通文本，不是媒体。'.codeUnits);

      await _pumpApp(tester, <String>[path]);

      expect(find.text('无法识别的文件格式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('文件不存在：显示「文件不存在」，其它标签页不受影响', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[
        'test/fixtures/does_not_exist.wav',
        wavFixture,
      ]);

      expect(find.text('文件不存在'), findsOneWidget);

      // 切到另一个标签页：它照常显示自己的内容。
      await tester.tap(find.text('wav_pcm_s16le_44100_stereo.normal.wav').last);
      await _waitForParse(tester);

      expect(find.text('文件不存在'), findsNothing);
      expect(find.text('采样率'), findsOneWidget);
      expect(find.text('44100'), findsWidgets);
    });
  });

  group('多标签页', () {
    testWidgets('打开两个文件得到两个标签', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[wavFixture, mp4Fixture]);

      // 每个标签页都有一个关闭按钮。
      expect(find.byTooltip('关闭标签页'), findsNWidgets(2));
      expect(find.text('wav_pcm_s16le_44100_stereo.normal.wav'), findsWidgets);
      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
    });

    testWidgets('切换标签页后内容随之改变', (WidgetTester tester) async {
      await _pumpApp(tester, <String>[wavFixture, mp4Fixture]);

      // 第一个标签页是 WAV。
      expect(find.text('PCM'), findsOneWidget);
      expect(find.text('avc1'), findsNothing);

      await tester.tap(find.text('mp4_h264_aac_320x240.normal.mp4').last);
      await _waitForParse(tester);

      // 换成了 MP4 的内容。
      expect(find.text('avc1'), findsOneWidget);
      expect(find.text('PCM'), findsNothing);
      expect(_treeRow('ftyp'), findsOneWidget);
    });
  });

  group('复制字段值', () {
    testWidgets('右键弹出「复制」菜单，复制后剪贴板里是字段值', (WidgetTester tester) async {
      _mockClipboard(tester);
      await _pumpApp(tester, <String>[mp4Fixture]);

      await tester.tapAt(
        tester.getCenter(find.text('avc1')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsOneWidget);

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(_clipboard, <String>['avc1']);
    });
  });
}
