/// 视觉语言：暗色仪器面板。
///
/// 设计定位是"调色台 / 示波器"这类**技术仪器**，不是消费级应用：
/// - 底色是偏蓝的石墨灰（不是纯黑——纯黑让边界糊在一起）
/// - **所有数据用等宽字体**，界面才读起来像一台仪器而不是一张网页表格
/// - 琥珀色是唯一的强调色（胶片引导片、钨丝灯），只用在真正需要看的地方
/// - 青色专供"坐标与结构"（偏移量、块类型、层级）
/// - 分隔线是发丝级的 1px，不使用 Material 的阴影与圆角卡片
library;

import 'package:flutter/material.dart';

/// 配色。
class MediaColors {
  const MediaColors._();

  /// 底色：深石墨，偏蓝。
  static const Color ink = Color(0xFF0E1116);

  /// 面板底色（比底色略亮一层）。
  static const Color panel = Color(0xFF161A21);

  /// 再高一层（悬浮、选中行）。
  static const Color panelHigh = Color(0xFF1C212A);

  /// 发丝分隔线。
  static const Color edge = Color(0xFF252B35);

  /// 更弱的分隔线（行内的分组线）。
  static const Color edgeSoft = Color(0xFF1B2029);

  /// 主文字：暖白，像胶片片基。
  static const Color chalk = Color(0xFFE4E1DA);

  /// 次要文字。
  static const Color chalkDim = Color(0xFF9BA1AC);

  /// 三级文字（英文技术名、注记）。
  static const Color chalkFaint = Color(0xFF616875);

  /// 强调色：琥珀（胶片引导片 / 钨丝灯）。
  static const Color amber = Color(0xFFE8A33D);

  /// 强调色的暗调（用于边框、底纹）。
  static const Color amberDeep = Color(0xFF8C6220);

  /// 坐标与结构色：青。
  static const Color teal = Color(0xFF5FA8A0);

  /// 坐标色的暗调。
  static const Color tealDeep = Color(0xFF2E5551);

  /// 警告色（截断、损坏、扩展名不符）。
  static const Color rose = Color(0xFFD96A6A);

  /// 推算值的颜色（我们自己算的，不是文件里写的）。
  static const Color violet = Color(0xFF9189C9);

  /// 坐标色的半透明版本（文本选区背景）。
  static const Color tealSoft = Color(0x335FA8A0);
}

/// 字体。
///
/// 不打包字体文件——一个桌面工具要跨 Windows 与 macOS，系统字体栈是最稳的，
/// 而且这个界面的排版个性来自**等宽/无衬线二分**与字距，不是来自某一款字。
class MediaType {
  const MediaType._();

  /// 等宽字体栈：所有数据、块名、偏移量都用它。
  static const List<String> mono = <String>[
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'monospace',
  ];

  /// 无衬线字体栈：标签与界面文字用它。
  static const List<String> sans = <String>[
    'Segoe UI',
    'SF Pro Text',
    'Helvetica Neue',
    'Microsoft YaHei UI',
    'system-ui',
    'sans-serif',
  ];

  /// 区段眉标：全大写、宽字距、小字号——仪器面板上的丝印字。
  static TextStyle eyebrow(Color color) => TextStyle(
    fontFamily: sans.first,
    fontFamilyFallback: sans,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.8,
    color: color,
  );

  /// 字段显示名（中文）。
  static TextStyle label(Color color) => TextStyle(
    fontFamily: sans.first,
    fontFamilyFallback: sans,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w400,
    color: color,
  );

  /// 字段值：等宽、右对齐靠右对齐做。
  static TextStyle value(Color color) => TextStyle(
    fontFamily: mono.first,
    fontFamilyFallback: mono,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// 英文技术名 / 注记。
  static TextStyle note(Color color) => TextStyle(
    fontFamily: mono.first,
    fontFamilyFallback: mono,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: color,
  );

  /// 块类型名（结构树）。
  static TextStyle blockName(Color color) => TextStyle(
    fontFamily: mono.first,
    fontFamilyFallback: mono,
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// 偏移量与长度（结构树的坐标列）。
  static TextStyle coordinate(Color color) => TextStyle(
    fontFamily: mono.first,
    fontFamilyFallback: mono,
    fontSize: 11.5,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// 应用主题。
ThemeData buildMediaTheme() {
  const ColorScheme scheme = ColorScheme.dark(
    primary: MediaColors.amber,
    onPrimary: MediaColors.ink,
    secondary: MediaColors.teal,
    onSecondary: MediaColors.ink,
    surface: MediaColors.panel,
    onSurface: MediaColors.chalk,
    error: MediaColors.rose,
    onError: MediaColors.ink,
    outline: MediaColors.edge,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: MediaColors.ink,
    canvasColor: MediaColors.ink,
    dividerColor: MediaColors.edge,
    splashFactory: NoSplash.splashFactory,
    highlightColor: MediaColors.panelHigh,
    hoverColor: MediaColors.panelHigh,
    dividerTheme: const DividerThemeData(
      color: MediaColors.edge,
      thickness: 1,
      space: 1,
    ),
    // 默认 Material 的滚动条在深色底上是刺眼的亮灰细条——压暗、收窄。
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(MediaColors.chalkFaint),
      trackColor: WidgetStatePropertyAll<Color>(Colors.transparent),
      thickness: WidgetStatePropertyAll<double>(6),
      radius: Radius.zero,
    ),
    iconTheme: const IconThemeData(color: MediaColors.chalkDim, size: 16),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MediaColors.amber,
      selectionColor: MediaColors.tealSoft,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MediaColors.panelHigh,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: MediaColors.edge),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Cascadia Mono',
        fontFamilyFallback: MediaType.mono,
        fontSize: 11.5,
        color: MediaColors.chalk,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: MediaType.sans,
        fontSize: 13,
        color: MediaColors.chalk,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: MediaType.sans,
        fontSize: 11.5,
        color: MediaColors.chalkDim,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Cascadia Mono',
        fontFamilyFallback: MediaType.mono,
        fontSize: 10.5,
        color: MediaColors.chalkFaint,
      ),
    ),
  );
}
