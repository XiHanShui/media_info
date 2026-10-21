/// 应用入口。
///
/// 启动流程：
///
/// 1. 注册全部媒体格式（核心的全局注册表是 isolate 级的，解析用的 isolate 里
///    会再注册一遍，见 `parse_service.dart`）；
/// 2. 启动应用。
///
/// 环境变量 `MEDIA_INFO_OPEN_FILES`（分号分隔的路径）会在启动时预打开文件，
/// 各开一个标签页——这是唯一的自动化入口。
library;

import 'package:flutter/material.dart';

import 'src/app/app.dart';
import 'src/formats/all_formats.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAllFormats();
  runApp(const MediaInfoApp());
}
