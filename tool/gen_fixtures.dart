// 生成测试样本素材（test/fixtures/）。
//
// 用法：dart run tool/gen_fixtures.dart
// 依赖：ffmpeg 在 PATH 上，或用环境变量 FFMPEG 指定可执行文件路径。
//
// 所有素材都由 ffmpeg 确定性地生成，不含任何外部下载内容，因此可以随仓库提交。
import 'dart:io';
import 'dart:typed_data';

/// 一个样本的生成方式。
class Sample {
  const Sample(this.name, this.args);

  /// 文件名（不含扩展名），形如 `wav_pcm_s16le_44100_stereo.normal`。
  final String name;

  /// 传给 ffmpeg 的参数（不含可执行文件名、输入输出路径）。
  final List<String> args;
}

/// 需要额外处理（截断 / 篡改长度字段）的样本。
class Damaged {
  const Damaged(this.name, {this.truncateTo, this.lieRiffSize});

  /// 对应 Sample 的 name。
  final String name;

  /// 截断到原文件字节数的这个比例；null 表示不截断。
  final double? truncateTo;

  /// 把 WAV 的 RIFF 长度与 data 块长度改成超大值（撒谎）。
  final bool? lieRiffSize;
}

/// 每种目标格式一个"正常"样本：最常见的参数组合。
const normalSamples = <Sample>[
  Sample('wav_pcm_s16le_44100_stereo.normal', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'pcm_s16le', '-ar', '44100', '-ac', '2',
  ]),
  Sample('aiff_pcm_s16be_48000_mono.normal', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'pcm_s16be', '-ar', '48000', '-ac', '1',
  ]),
  Sample('flac_s16_44100_stereo.normal', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'flac',
  ]),
  Sample('mp3_cbr128_44100_stereo.normal', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'libmp3lame', '-b:a', '128k',
  ]),
  Sample('mp4_h264_aac_320x240.normal', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
  ]),
  Sample('mov_mpeg4_aac_320x240.normal', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:v', 'mpeg4', '-c:a', 'aac',
  ]),
  Sample('mkv_vp9_opus_320x240.normal', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:v', 'libvpx-vp9', '-b:v', '200k', '-c:a', 'libopus',
  ]),
  Sample('webm_vp8_vorbis_320x240.normal', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:v', 'libvpx', '-b:v', '200k', '-c:a', 'libvorbis',
  ]),
];

/// "边界"样本：罕见但合法的参数组合。
const edgeSamples = <Sample>[
  Sample('wav_pcm_u8_8000_mono.edge', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'pcm_u8', '-ar', '8000', '-ac', '1',
  ]),
  Sample('wav_pcm_s24le_48000_stereo.edge', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'pcm_s24le', '-ar', '48000', '-ac', '2',
  ]),
  Sample('aiff_pcm_s24be_44100_stereo.edge', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'pcm_s24be', '-ar', '44100', '-ac', '2',
  ]),
  Sample('flac_s24_96000_mono.edge', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'flac', '-sample_fmt', 's32', '-ar', '96000', '-ac', '1',
  ]),
  Sample('mp3_vbr_q2_22050_mono.edge', [
    '-f', 'lavfi', '-i', 'sine=f=440:d=0.25',
    '-c:a', 'libmp3lame', '-q:a', '2', '-ar', '22050', '-ac', '1',
  ]),
  Sample('mp4_h264_noaudio_320x240.edge', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-an',
  ]),
  Sample('mkv_vp9_noaudio_320x240.edge', [
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:d=1',
    '-c:v', 'libvpx-vp9', '-b:v', '200k', '-an',
  ]),
];

/// "损坏"样本：在正常样本基础上做手脚。
const damagedSamples = <Damaged>[
  Damaged('wav_pcm_s16le_44100_stereo.normal', truncateTo: 0.6),
  Damaged('aiff_pcm_s16be_48000_mono.normal', truncateTo: 0.6),
  Damaged('flac_s16_44100_stereo.normal', truncateTo: 0.6),
  Damaged('mp3_cbr128_44100_stereo.normal', truncateTo: 0.6),
  Damaged('mp4_h264_aac_320x240.normal', truncateTo: 0.6),
  Damaged('mov_mpeg4_aac_320x240.normal', truncateTo: 0.6),
  Damaged('mkv_vp9_opus_320x240.normal', truncateTo: 0.6),
  Damaged('webm_vp8_vorbis_320x240.normal', truncateTo: 0.6),
  Damaged('wav_pcm_s16le_44100_stereo.normal', lieRiffSize: true),
];

/// 文件名后缀 → 扩展名。
const extensions = <String, String>{
  'wav': 'wav',
  'aiff': 'aiff',
  'flac': 'flac',
  'mp3': 'mp3',
  'mp4': 'mp4',
  'mov': 'mov',
  'mkv': 'mkv',
  'webm': 'webm',
};

/// 从样本名推断扩展名：`wav_pcm_s16le_44100_stereo.normal` → `wav`。
String extensionOf(String name) {
  final format = name.split('_').first;
  final ext = extensions[format];
  if (ext == null) throw ArgumentError('未知格式：$format（来自 $name）');
  return ext;
}

Future<void> runFfmpeg(List<String> args, String outputPath) async {
  final exe = Platform.environment['FFMPEG'] ?? 'ffmpeg';
  final result = await Process.run(exe, [...args, '-y', outputPath]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg 失败 ($exe)：${result.stderr}');
  }
}

/// 截断文件到原字节数的 [ratio]。
Future<void> truncate(String path, double ratio) async {
  final bytes = File(path).readAsBytesSync();
  final keep = (bytes.length * ratio).floor();
  File(path).writeAsBytesSync(bytes.sublist(0, keep), flush: true);
}

/// 把 WAV 的 RIFF 长度（偏移 4）与 data 块长度（偏移 40）改成超大值——长度字段撒谎。
Future<void> lieRiffSize(String path) async {
  final bytes = File(path).readAsBytesSync();
  void putLe32(int offset, int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    for (var i = 0; i < 4; i++) {
      bytes[offset + i] = b.getUint8(i);
    }
  }

  putLe32(4, 0xFFFFFFFF);
  putLe32(40, 0xFFFFFF00);
  File(path).writeAsBytesSync(bytes, flush: true);
}

/// 自检：确认每个损坏样本真的被破坏了。
///
/// 如果 ffmpeg 改了行为、或字节改写逻辑有 bug，素材会静默地变成正常样本——这里直接报错。
void verifyDamaged() {
  for (final damaged in damagedSamples) {
    final ext = extensionOf(damaged.name);
    final suffix = damaged.lieRiffSize == true ? 'liesize' : 'truncated';
    final path = 'test/fixtures/${damaged.name}.$suffix.$ext';
    final bytes = File(path).readAsBytesSync();
    final source = File('test/fixtures/${damaged.name}.$ext').readAsBytesSync();

    if (damaged.truncateTo != null) {
      final expected = (source.length * damaged.truncateTo!).floor();
      if (bytes.length != expected) {
        throw StateError('$path 截断长度应为 $expected，实际 ${bytes.length}');
      }
      if (bytes.length >= source.length) {
        throw StateError('$path 没有比原文件短');
      }
    }

    if (damaged.lieRiffSize == true) {
      final riffSize = ByteData.sublistView(bytes, 4, 8).getUint32(0, Endian.little);
      final dataSize = ByteData.sublistView(bytes, 40, 44).getUint32(0, Endian.little);
      if (riffSize != 0xFFFFFFFF || dataSize != 0xFFFFFF00) {
        throw StateError('$path 的长度字段没有被改成超大值 '
            '(riff=$riffSize data=$dataSize)');
      }
    }
  }
}

Future<void> main() async {
  final outDir = Directory('test/fixtures');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // 清掉旧素材，避免上一轮遗留的孤儿文件混进仓库。
  for (final entity in outDir.listSync()) {
    if (entity is File) entity.deleteSync();
  }

  final generated = <String, File>{};

  for (final sample in [...normalSamples, ...edgeSamples]) {
    final path = '${outDir.path}/${sample.name}.${extensionOf(sample.name)}';
    await runFfmpeg(sample.args, path);
    generated[sample.name] = File(path);
    stdout.writeln('生成 ${sample.name}');
  }

  for (final damaged in damagedSamples) {
    final source = generated[damaged.name];
    if (source == null) throw StateError('找不到来源样本 ${damaged.name}');
    final ext = extensionOf(damaged.name);
    final suffix = damaged.lieRiffSize == true ? 'liesize' : 'truncated';
    final path = '${outDir.path}/${damaged.name}.$suffix.$ext';
    source.copySync(path);
    if (damaged.truncateTo != null) await truncate(path, damaged.truncateTo!);
    if (damaged.lieRiffSize == true) await lieRiffSize(path);
    stdout.writeln('生成 ${damaged.name}.$suffix');
  }

  verifyDamaged();

  stdout.writeln('\n共 ${outDir.listSync().length} 个素材，'
      '总大小 ${outDir.listSync().fold<int>(0, (sum, e) => sum + (e as File).lengthSync())} 字节');
}
