/// 语义字段视图里「右键复制」的 widget 测试。
///
/// 断言的是用户能看见的行为：右键弹出菜单 → 点「复制」→ 剪贴板里是这个字段
/// 的值 → 界面上有「已复制」的提示。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/app/semantic_view.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

/// 记录写进剪贴板的文本。
final List<String> _clipboard = <String>[];

/// 把平台通道的剪贴板调用记下来（测试环境里没有真的剪贴板）。
void _mockClipboard(WidgetTester tester) {
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

/// 造一个文档：有文件级字段、轨道级字段与标签。
ParsedDocument _document() {
  return ParsedDocument(
    path: 'C:/media/sample.wav',
    detectedFormat: 'WAV',
    fileFields: const <SemanticField>[
      SemanticField(key: 'file_name', label: '文件名', value: 'sample.wav'),
      SemanticField(key: 'duration', label: '时长', value: 3661.25, unit: 's'),
    ],
    tracks: const <TrackFields>[
      TrackFields(
        trackIndex: 0,
        fields: <SemanticField>[
          SemanticField(
            key: 'sample_rate',
            label: '采样率',
            value: 44100,
            unit: 'Hz',
            scope: FieldScope.track,
            trackIndex: 0,
          ),
        ],
      ),
    ],
    tags: const <Tag>[
      Tag(key: 'TITLE', value: 'Song', source: 'VORBIS_COMMENT'),
    ],
  );
}

Future<void> _pump(WidgetTester tester) async {
  _clipboard.clear();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SemanticView(document: _document())),
    ),
  );
  await tester.pumpAndSettle();
}

/// 在某个控件上右键。
Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  await tester.tapAt(tester.getCenter(finder), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('右键字段行弹出「复制」菜单', (WidgetTester tester) async {
    _mockClipboard(tester);
    await _pump(tester);

    await _rightClick(tester, find.text('44100'));

    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('复制字段值：数值按字符串形式进剪贴板', (WidgetTester tester) async {
    _mockClipboard(tester);
    await _pump(tester);

    await _rightClick(tester, find.text('44100'));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(_clipboard, <String>['44100']);
  });

  testWidgets('复制时长字段：按 HH:MM:SS.mmm 进剪贴板，不带单位', (WidgetTester tester) async {
    _mockClipboard(tester);
    await _pump(tester);

    await _rightClick(tester, find.text('3661.250'));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(_clipboard, <String>['01:01:01.250']);
  });

  testWidgets('复制后给出「已复制」提示', (WidgetTester tester) async {
    _mockClipboard(tester);
    await _pump(tester);

    await _rightClick(tester, find.text('sample.wav'));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已复制'), findsOneWidget);
    expect(_clipboard, <String>['sample.wav']);
  });

  testWidgets('右键标签行也能复制', (WidgetTester tester) async {
    _mockClipboard(tester);
    await _pump(tester);

    await _rightClick(tester, find.text('Song'));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(_clipboard, <String>['Song']);
  });
}
