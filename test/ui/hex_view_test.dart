import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/ui/hex_view.dart';

ContainerNode testNode(String type, int offset, int size) => ContainerNode(
  type: type,
  offset: offset,
  size: size,
  dataOffset: offset,
  dataSize: size,
);

Widget appOf(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 900, child: child)));

/// 写一个临时文件，返回路径。
String tempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_hex');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  test('hex 行同时给出十六进制与 ASCII', () {
    final bytes = Uint8List.fromList(<int>[0x00, 0x41, 0x42, 0xff]);
    final lines = hexDumpLines(bytes, baseOffset: 16);

    expect(lines, hasLength(1));
    expect(lines.single, contains('00000010'));
    expect(lines.single, contains('00 41 42 FF'));
    expect(lines.single, contains('|.AB.'));
  });

  test('hex 行按 16 字节一行分组', () {
    final bytes = Uint8List(20);
    final lines = hexDumpLines(bytes, baseOffset: 0);

    expect(lines, hasLength(2));
    expect(lines.first, contains('00000000'));
    expect(lines.last, contains('00000010'));
  });

  testWidgets('hex 视图显示选中块的类型、偏移与大小', (
    WidgetTester tester,
  ) async {
    final path = tempFile('a.bin', List<int>.filled(64, 0x41));

    await tester.pumpWidget(
      appOf(
        HexView(node: testNode('mdat', 16, 32), filePath: path),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('mdat'), findsOneWidget);
    expect(find.text('偏移 16'), findsOneWidget);
    expect(find.text('大小 32'), findsOneWidget);
  });

  testWidgets('hex 视图显示十六进制内容与 ASCII 侧栏', (
    WidgetTester tester,
  ) async {
    final path = tempFile('b.bin', <int>[0x66, 0x74, 0x79, 0x70]);

    await tester.pumpWidget(
      appOf(HexView(node: testNode('ftyp', 0, 4), filePath: path)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('66 74 79 70'), findsOneWidget);
    expect(find.textContaining('|ftyp|'), findsOneWidget);
  });

  testWidgets('大块只显示前 N 字节并说明还剩多少', (WidgetTester tester) async {
    final path = tempFile('big.bin', List<int>.filled(100000, 0x41));

    await tester.pumpWidget(
      appOf(
        HexView(
          node: testNode('mdat', 0, 100000),
          filePath: path,
          byteLimit: 4096,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 4096 字节 = 256 行。
    expect(find.textContaining('还有 95904 字节未显示'), findsOneWidget);
  });

  testWidgets('文件被截断时优雅降级，不抛异常', (WidgetTester tester) async {
    final path = tempFile('short.bin', List<int>.filled(8, 0x41));

    await tester.pumpWidget(
      appOf(HexView(node: testNode('mdat', 0, 100), filePath: path)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('截断'), findsOneWidget);
    // 只读得到 8 个字节。
    expect(find.textContaining('41 41 41 41'), findsOneWidget);
  });

  testWidgets('文件打不开时给出中文提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      appOf(
        HexView(
          node: testNode('mdat', 0, 100),
          filePath: 'test/fixtures/does_not_exist.bin',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('无法打开文件'), findsOneWidget);
  });
}
