/// 应用外壳的交互断言。
///
/// 覆盖 user story 1–7、39、46、54：
/// 拖放打开、文件选择器入口、多标签页、切换、关闭、当前文件提示、
/// 大文件不卡死、扩展名不符提示、无法识别的格式、中文界面。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/app.dart';

const String mp4Fixture = 'test/fixtures/mp4_h264_aac_320x240.normal.mp4';
const String wavFixture = 'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav';
const String mkvFixture = 'test/fixtures/mkv_vp9_opus_320x240.normal.mkv';

/// 启动应用并等解析完成。
Future<void> pumpApp(
  WidgetTester tester,
  List<String> paths, {
  Size size = const Size(1400, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MediaInfoApp(initialPaths: paths));
  await waitForParse(tester);
}

/// 等到当前标签页解析完（「解析中…」消失）。
Future<void> waitForParse(WidgetTester tester) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    if (find.text('解析中…').evaluate().isEmpty) return;
  }
  fail('等待解析完成超时');
}

/// 造一个临时文件，返回路径。
String writeTempFile(String name, List<int> bytes) {
  final Directory dir = Directory.systemTemp.createTempSync('media_info_shell');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

/// 把一个路径「拖」到窗口里。
Future<void> dropFile(WidgetTester tester, String path) async {
  final DragTarget<Object> target = tester.widget<DragTarget<Object>>(
    find.byType(DragTarget<Object>),
  );
  target.onAcceptWithDetails!(
    DragTargetDetails<Object>(data: path, offset: Offset.zero),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('空态', () {
    testWidgets('没有打开文件时给出中文提示与「打开文件」按钮', (WidgetTester tester) async {
      await tester.pumpWidget(const MediaInfoApp());
      await tester.pumpAndSettle();

      expect(find.text('没有打开的文件'), findsOneWidget);
      expect(find.text('把媒体文件拖进来，或点「打开文件」'), findsOneWidget);
      expect(find.text('未打开文件'), findsOneWidget);
      expect(find.text('打开文件'), findsWidgets);
    });

    testWidgets('工具条上有「打开文件」与「导出 JSON」', (WidgetTester tester) async {
      await tester.pumpWidget(const MediaInfoApp());
      await tester.pumpAndSettle();

      expect(find.text('打开文件'), findsWidgets);
      expect(find.text('导出 JSON'), findsOneWidget);
    });

    testWidgets('没有文档时「导出 JSON」是禁用的', (WidgetTester tester) async {
      await tester.pumpWidget(const MediaInfoApp());
      await tester.pumpAndSettle();

      final InkWell button = tester.widget<InkWell>(
        find.ancestor(of: find.text('导出 JSON'), matching: find.byType(InkWell)),
      );
      expect(button.onTap, isNull);
    });

    testWidgets('点「打开文件」在没有平台实现时不崩溃', (WidgetTester tester) async {
      await tester.pumpWidget(const MediaInfoApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开文件').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('标签页', () {
    testWidgets('打开一个文件就多一个标签，标签上是文件名', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture]);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
    });

    testWidgets('同时打开多个文件各占一个标签页', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture, wavFixture]);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
      expect(find.text('wav_pcm_s16le_44100_stereo.normal.wav'), findsWidgets);
    });

    testWidgets('在标签页之间切换，当前内容随之改变', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture, wavFixture]);

      // 当前是第一个标签：容器格式是 isom。
      expect(find.text('isom'), findsWidgets);

      await tester.tap(find.text('wav_pcm_s16le_44100_stereo.normal.wav'));
      await tester.pumpAndSettle();

      expect(find.text('WAV'), findsWidgets);
      expect(find.text('isom'), findsNothing);
    });

    // ⚠️ 已知缺陷（见 test/COVERAGE.md）：`IndexedStack` 的子节点被 Flutter 包在
    //    **没有 key 的 `Visibility`** 里，Flutter 只能按位置匹配它们——
    //    关掉一个标签后，剩下的标签页被整体重建，解析从头再来一遍
    //    （界面上会闪回「解析中…」）。这与 user story 5「关闭一个标签页后
    //    其余不受影响」相悖。
    testWidgets('关闭一个标签页，其余标签不受影响（不重新解析）', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture, wavFixture]);

      // 关掉第一个标签。
      await tester.tap(
        find
            .descendant(
              of: find.byType(IconButton),
              matching: find.byTooltip('关闭标签页'),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsNothing);
      expect(find.text('wav_pcm_s16le_44100_stereo.normal.wav'), findsWidgets);
      // 剩下的标签页不应该被重新解析。
      expect(find.text('解析中…'), findsNothing);
      expect(find.text('WAV'), findsWidgets);
    });

    testWidgets('Ctrl+Tab 切到下一个标签页', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture, wavFixture]);

      expect(find.text('isom'), findsWidgets);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('WAV'), findsWidgets);
    });

    testWidgets('同一个文件重复拖进来不会开第二个标签', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture]);

      await dropFile(tester, mp4Fixture);
      await waitForParse(tester);

      expect(
        find.byType(TabBar),
        findsNothing,
        reason: '本应用用自定义标签条，不是 Material 的 TabBar',
      );
      expect(
        find.descendant(
          of: find.byType(InkWell),
          matching: find.text('mp4_h264_aac_320x240.normal.mp4'),
        ),
        findsOneWidget,
      );
    });
  });

  group('当前打开的是哪个文件', () {
    testWidgets('工具条右侧显示当前文件的文件名', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture]);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
    });
  });

  group('拖放打开文件', () {
    testWidgets('把文件拖进窗口就打开它', (WidgetTester tester) async {
      await pumpApp(tester, <String>[wavFixture]);

      await dropFile(tester, mp4Fixture);
      await waitForParse(tester);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
    });

    testWidgets('拖进来一个列表会逐个打开', (WidgetTester tester) async {
      await pumpApp(tester, <String>[wavFixture]);

      final DragTarget<Object> target = tester.widget<DragTarget<Object>>(
        find.byType(DragTarget<Object>),
      );
      target.onAcceptWithDetails!(
        DragTargetDetails<Object>(
          data: <String>[mp4Fixture, mkvFixture],
          offset: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      await waitForParse(tester);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
      expect(find.text('mkv_vp9_opus_320x240.normal.mkv'), findsWidgets);
    });

    // ⚠️ 已知缺陷（见 test/COVERAGE.md）：空态下窗口里没有拖放目标，
    //    所以「把文件拖进窗口就打开」在**一个文件都没打开时**不成立，
    //    而空态的文案却写着「把媒体文件拖进来」。
    testWidgets('空态下也能把文件拖进来打开', (WidgetTester tester) async {
      await tester.pumpWidget(const MediaInfoApp());
      await tester.pumpAndSettle();

      expect(
        find.byType(DragTarget<Object>),
        findsOneWidget,
        reason: '空态也必须接受拖放，否则「把媒体文件拖进来」的提示是假的',
      );

      await dropFile(tester, mp4Fixture);
      await waitForParse(tester);

      expect(find.text('mp4_h264_aac_320x240.normal.mp4'), findsWidgets);
    });
  });

  group('解析中的状态', () {
    testWidgets('解析还没完成时显示「解析中…」', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MediaInfoApp(initialPaths: <String>[mp4Fixture]));

      expect(find.text('解析中…'), findsOneWidget);

      await waitForParse(tester);
      expect(find.text('解析中…'), findsNothing);
    });
  });

  group('异常状态', () {
    testWidgets('文件不存在：这个标签页显示「文件不存在」，其它标签不受影响', (WidgetTester tester) async {
      await pumpApp(tester, <String>['test/fixtures/not_here.mp4', mp4Fixture]);

      expect(find.text('文件不存在'), findsOneWidget);

      await tester.tap(find.text('mp4_h264_aac_320x240.normal.mp4'));
      await tester.pumpAndSettle();

      expect(find.text('文件不存在'), findsNothing);
      expect(find.text('isom'), findsWidgets);
    });

    testWidgets('不是媒体文件：显示「无法识别的文件格式」', (WidgetTester tester) async {
      final String path = writeTempFile('notes.txt', <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);

      await pumpApp(tester, <String>[path]);

      expect(find.text('无法识别的文件格式'), findsOneWidget);
      expect(find.text('解析失败'), findsNothing);
    });

    testWidgets('扩展名与实际格式不符：给出明确的提示条', (WidgetTester tester) async {
      final String path = writeTempFile('actually_mp4.wav', <int>[
        ...File(mp4Fixture).readAsBytesSync(),
      ]);

      await pumpApp(tester, <String>[path]);

      expect(find.text('扩展名 `.wav` 与实际格式 `MP4` 不符'), findsOneWidget);
    });

    testWidgets('文件被截断：给出警告条，但已读到的结构照样显示', (WidgetTester tester) async {
      await pumpApp(tester, <String>[
        'test/fixtures/mp4_h264_aac_320x240.normal.truncated.mp4',
      ]);

      expect(find.textContaining('截断'), findsOneWidget);
      expect(find.text('文件级'), findsOneWidget);
    });
  });

  group('界面语言', () {
    testWidgets('界面文案是中文，字段名与块名保持英文', (WidgetTester tester) async {
      await pumpApp(tester, <String>[mp4Fixture]);

      expect(find.text('文件级'), findsOneWidget);
      expect(find.text('轨道级'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      expect(find.text('container_format'), findsOneWidget);
      expect(find.text('mdat'), findsWidgets);
    });
  });
}
