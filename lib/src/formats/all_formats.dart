/// 全部媒体格式的注册入口。
///
/// 各格式模块**不在 import 时做注册**——注册必须由调用方显式触发，
/// 否则 import 顺序会悄悄决定嗅探顺序。
///
/// 应用启动时调用一次 [registerAllFormats]；解析在 isolate 里跑的时候，
/// isolate 是全新的，全局注册表是空的，所以那个 isolate 里也要再调一次
/// （见 `parse_service.dart`）。
library;

import 'flac.dart';
import 'isobmff.dart';
import 'matroska.dart';
import 'mp3.dart';
import 'riff.dart';

/// 把全部已实现的媒体格式注册进全局格式注册表。
///
/// 重复调用安全：同名格式会被替换而不是重复登记。
///
/// 嗅探按注册顺序进行，第一个命中者胜出，所以结构明确的容器格式
/// （WAV / AIFF / MP4 / FLAC / Matroska）排在宽松的 MP3 前面。
void registerAllFormats() {
  registerWav();
  registerAiff();
  registerMp4();
  registerFlacFormat();
  registerMatroska();
  registerMp3();
}
