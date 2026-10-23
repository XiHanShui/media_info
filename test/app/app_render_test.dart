import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/app.dart';

const String wavFixture = 'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav';
const String mp4Fixture = 'test/fixtures/mp4_h264_aac_320x240.normal.mp4';

/// 启动应用并等到解析完成（解析在 isolate 里跑，必须让出真实时间）。
Future<void> _pumpApp(WidgetTester tester, List<String> paths) async {
  // 窗口开大一点，左栏的三个区段一次都能渲染出来。
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MediaInfoApp(initialPaths: paths));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

/// 造一个临时文件，返回路径。
String _tempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_app_widget');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  testWidgets('打开 WAV 文件后渲染三个区段与字段', (WidgetTester tester) async {
    await _pumpApp(tester, <String>[wavFixture]);

    expect(find.text('文件级'), findsOneWidget);
    expect(find.text('轨道级'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);

    // 文件级：解析服务统一补齐的三个字段。
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('文件大小'), findsOneWidget);
    expect(find.text('容器格式'), findsOneWidget);

    // 轨道级：WAV 的采样率。
    expect(find.text('轨道 0'), findsOneWidget);
    expect(find.text('采样率'), findsOneWidget);
    expect(find.text('44100'), findsOneWidget);
  });

  testWidgets('推算值有视觉区分', (WidgetTester tester) async {
    await _pumpApp(tester, <String>[wavFixture]);
    expect(find.text('（推算）'), findsWidgets);
  });

  testWidgets('扩展名与实际格式不符时给出提示条', (WidgetTester tester) async {
    final path = _tempFile(
      'mislabelled.wav',
      File(mp4Fixture).readAsBytesSync(),
    );
    await _pumpApp(tester, <String>[path]);
    expect(find.text('扩展名 `.wav` 与实际格式 `MP4` 不符'), findsOneWidget);
  });

  testWidgets('不是媒体的文件显示「无法识别的文件格式」', (WidgetTester tester) async {
    final path = _tempFile('notes.txt', '普通文本，不是媒体。'.codeUnits);
    await _pumpApp(tester, <String>[path]);
    expect(find.text('无法识别的文件格式'), findsOneWidget);
  });

  testWidgets('文件不存在时该标签页显示「文件不存在」', (WidgetTester tester) async {
    await _pumpApp(tester, <String>['test/fixtures/does_not_exist.wav']);
    expect(find.text('文件不存在'), findsOneWidget);
  });

  testWidgets('工具条上有「打开文件」与「导出 JSON」', (WidgetTester tester) async {
    await _pumpApp(tester, const <String>[]);
    expect(find.text('打开文件'), findsWidgets);
    expect(find.text('导出 JSON'), findsOneWidget);
  });
}
