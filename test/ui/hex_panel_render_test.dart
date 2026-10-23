/// hex 面板的渲染断言。
///
/// 覆盖 user story 25–28：
/// 原始 hex、ASCII 侧栏、独立滚动、大块截断与截断降级。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/ui/hex_view.dart';

import '../support/document_builder.dart';

/// 把 hex 视图放进一个有边界的窗口里。
Widget appOf(Widget child, {double width = 900, double height = 400}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: child),
      ),
    );

/// 写一个临时文件，返回路径。
String writeTempFile(String name, List<int> bytes) {
  final Directory dir = Directory.systemTemp.createTempSync('media_info_hex');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  group('hexDumpLines：每行 16 字节', () {
    test('一行最多 16 个字节', () {
      final List<String> lines = hexDumpLines(Uint8List(20), baseOffset: 0);

      expect(lines, hasLength(2));
      expect(
        lines.first
            .split(RegExp(r'\s+'))
            .where((String s) => s.isNotEmpty)
            .length,
        greaterThan(16),
      );
    });

    test('满行的列宽固定：地址 8 位 + 十六进制 47 列 + ASCII 16 列', () {
      final List<String> lines = hexDumpLines(Uint8List(16), baseOffset: 0);

      expect(lines, hasLength(1));
      expect(lines.single.length, 77);
      expect(lines.single.substring(0, 8), '00000000');
      expect(lines.single.substring(8, 10), '  ');
      expect(lines.single.substring(57, 60), '  |');
      expect(lines.single.substring(59, 77), '|${'.' * 16}|');
    });

    test('不足一行时补空格，ASCII 列仍然对齐', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0x41, 0x42, 0x43]),
        baseOffset: 0,
      );

      expect(lines, hasLength(1));
      expect(lines.single.length, 64);
      expect(lines.single.endsWith('|ABC|'), isTrue);
    });

    test('地址列是八位十六进制，随偏移递增', () {
      final List<String> lines = hexDumpLines(Uint8List(32), baseOffset: 0x10);

      expect(lines.first.substring(0, 8), '00000010');
      expect(lines.last.substring(0, 8), '00000020');
    });

    test('每行可以自定义宽度', () {
      final List<String> lines = hexDumpLines(
        Uint8List(8),
        baseOffset: 0,
        bytesPerLine: 8,
      );

      expect(lines, hasLength(1));
    });

    test('宽度为 0 时不产生任何行', () {
      expect(
        hexDumpLines(Uint8List(8), baseOffset: 0, bytesPerLine: 0),
        isEmpty,
      );
    });

    test('空字节串不产生任何行', () {
      expect(hexDumpLines(Uint8List(0), baseOffset: 0), isEmpty);
    });
  });

  group('ASCII 侧栏', () {
    test('不可打印的字节替换成点', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0x00, 0x41, 0x42, 0xFF]),
        baseOffset: 16,
      );

      expect(lines.single, contains('|.AB.|'));
    });

    test('0x20（空格）是可打印的', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0x20]),
        baseOffset: 0,
      );

      expect(lines.single, endsWith('| |'));
    });

    test('0x7E（~）是可打印的', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0x7E]),
        baseOffset: 0,
      );

      expect(lines.single, endsWith('|~|'));
    });

    test('0x1F 与 0x7F 不可打印', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0x1F, 0x7F]),
        baseOffset: 0,
      );

      expect(lines.single, endsWith('|..|'));
    });

    test('十六进制用大写字母', () {
      final List<String> lines = hexDumpLines(
        Uint8List.fromList(<int>[0xAB, 0xCD, 0xEF]),
        baseOffset: 0,
      );

      expect(lines.single, contains('AB CD EF'));
    });
  });

  group('面板标题', () {
    testWidgets('标题给出块的类型、偏移与大小', (WidgetTester tester) async {
      final String path = writeTempFile('a.bin', List<int>.filled(64, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 16, 32), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(find.text('mdat'), findsOneWidget);
      expect(find.text('偏移 16'), findsOneWidget);
      expect(find.text('大小 32'), findsOneWidget);
      expect(find.text('hex'), findsOneWidget);
    });

    testWidgets('Matroska 的元素 ID 显示成元素名', (WidgetTester tester) async {
      final String path = writeTempFile('b.bin', List<int>.filled(64, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('0x18538067', 0, 16), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Segment'), findsOneWidget);
    });
  });

  group('大块：截断显示，不整块读入', () {
    testWidgets('只显示前 N 字节，并说明还剩多少没显示', (WidgetTester tester) async {
      final String path = writeTempFile(
        'big.bin',
        List<int>.filled(100000, 0x41),
      );

      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 100000),
            filePath: path,
            byteLimit: 4096,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('仅显示前 4096 字节，还有 95904 字节未显示'), findsOneWidget);
    });

    testWidgets('大块不会被整块渲染出来（只渲染前 N 字节的行）', (WidgetTester tester) async {
      final String path = writeTempFile(
        'big2.bin',
        List<int>.filled(100000, 0x41),
      );

      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 100000),
            filePath: path,
            byteLimit: 4096,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 4096 字节 = 256 行；整块读进来会是 6250 行。
      expect(find.textContaining('41 41 41 41', findRichText: true), findsWidgets);
      expect(
        tester.widgetList<Text>(find.byType(Text)).length,
        lessThan(400),
        reason: '只应该渲染出前 4096 字节对应的 256 行',
      );
    });

    testWidgets('字节上限可以调小', (WidgetTester tester) async {
      final String path = writeTempFile(
        'big3.bin',
        List<int>.filled(1000, 0x41),
      );

      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 1000),
            filePath: path,
            byteLimit: 16,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('仅显示前 16 字节，还有 984 字节未显示'), findsOneWidget);
    });

    testWidgets('块比上限还小时不显示截断提示', (WidgetTester tester) async {
      final String path = writeTempFile(
        'small.bin',
        List<int>.filled(32, 0x41),
      );

      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 32),
            filePath: path,
            byteLimit: 4096,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('未显示'), findsNothing);
    });
  });

  group('截断与错误降级', () {
    testWidgets('块声明的长度超过文件剩余：读得到多少显示多少', (WidgetTester tester) async {
      final String path = writeTempFile('short.bin', List<int>.filled(8, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 0, 100), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('41 41 41 41', findRichText: true), findsOneWidget);
      expect(find.textContaining('截断'), findsOneWidget);
    });

    testWidgets('块完全在文件之外：给出中文说明，不抛异常', (WidgetTester tester) async {
      final String path = writeTempFile(
        'short2.bin',
        List<int>.filled(8, 0x41),
      );

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 100, 10), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('截断'), findsOneWidget);
      expect(find.textContaining('没有可显示的字节'), findsOneWidget);
    });

    testWidgets('文件打不开：给出中文说明，不抛异常', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 100),
            filePath: 'test/fixtures/does_not_exist.bin',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('无法打开文件'), findsOneWidget);
    });
  });

  group('折叠与空态', () {
    testWidgets('折叠时只留标题栏，内容不显示', (WidgetTester tester) async {
      final String path = writeTempFile('c.bin', List<int>.filled(64, 0x41));

      await tester.pumpWidget(
        appOf(
          HexView(
            node: buildNode('mdat', 0, 16),
            filePath: path,
            collapsed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('mdat'), findsOneWidget);
      expect(find.textContaining('41 41 41 41', findRichText: true), findsNothing);
    });

    testWidgets('展开按钮的提示随折叠状态变化', (WidgetTester tester) async {
      final String path = writeTempFile('d.bin', List<int>.filled(64, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 0, 16), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('折叠 hex 面板'), findsOneWidget);

      await tester.tap(find.byTooltip('折叠 hex 面板'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('展开 hex 面板'), findsOneWidget);
    });

    testWidgets('没有选中块时不显示任何东西', (WidgetTester tester) async {
      final String path = writeTempFile('e.bin', List<int>.filled(64, 0x41));

      await tester.pumpWidget(appOf(HexView(node: null, filePath: path)));
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('独立滚动', () {
    testWidgets('hex 面板有自己的滚动视图', (WidgetTester tester) async {
      final String path = writeTempFile('f.bin', List<int>.filled(4096, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 0, 4096), filePath: path)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('横向滚动条存在（长行可以左右看）', (WidgetTester tester) async {
      final String path = writeTempFile('g.bin', List<int>.filled(4096, 0x41));

      await tester.pumpWidget(
        appOf(HexView(node: buildNode('mdat', 0, 4096), filePath: path)),
      );
      await tester.pumpAndSettle();

      final SingleChildScrollView horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere(
            (SingleChildScrollView view) =>
                view.scrollDirection == Axis.horizontal,
          );
      expect(horizontal.scrollDirection, Axis.horizontal);
    });
  });
}
