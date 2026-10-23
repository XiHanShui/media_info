/// 各格式的**结构树**断言。
///
/// 覆盖 user story 17–22、29–37、48、49：
/// 结构树、偏移量与长度、逐层展开、原始类型标识、折叠、未知块、
/// 以及「损坏文件仍给出已读到的部分结构」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';

import '../support/coverage_lists.dart';
import '../support/format_parsers.dart';

/// 深度优先地收集所有节点的类型。
List<String> allTypes(ContainerNode root) {
  final List<String> out = <String>[];
  void walk(ContainerNode node) {
    out.add(node.type);
    for (final ContainerNode child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return out;
}

/// 找第一个指定类型的节点（深度优先）。
ContainerNode? findNode(ContainerNode root, String type) {
  for (final ContainerNode child in root.children) {
    if (child.type == type) return child;
    final ContainerNode? found = findNode(child, type);
    if (found != null) return found;
  }
  return null;
}

/// 某节点的字段值表。
Map<String, Object?> fieldValues(ContainerNode node) => <String, Object?>{
  for (final SemanticField field in node.fields) field.key: field.value,
};

void main() {
  group('WAV：RIFF chunk 布局', () {
    test('根节点是 WAV，顶层是 RIFF 块，form type 是 WAVE', () {
      final result = parseFixtureFile('wav_pcm_s16le_44100_stereo.normal.wav');

      expect(result.root.type, 'WAV');
      expect(result.root.offset, 0);
      expect(result.root.size, 44178);
      expect(result.root.children, hasLength(1));

      final ContainerNode riff = result.root.children.single;
      expect(riff.type, 'RIFF');
      expect(riff.offset, 0);
      expect(riff.size, 44178);
      expect(fieldValues(riff)['form_type'], 'WAVE');
    });

    test('RIFF 的子块按文件顺序排列：fmt 、LIST、data', () {
      final result = parseFixtureFile('wav_pcm_s16le_44100_stereo.normal.wav');

      final List<String> types = result.root.children.single.children
          .map((ContainerNode c) => c.type)
          .toList();
      expect(types, <String>['fmt ', 'LIST', 'data']);
    });

    test('fmt 块给出 16bit / 采样率 / 声道数', () {
      final result = parseFixtureFile('wav_pcm_s16le_44100_stereo.normal.wav');

      final ContainerNode? fmt = findNode(result.root, 'fmt ');
      expect(fmt, isNotNull);
      final Map<String, Object?> values = fieldValues(fmt!);
      expect(values['wFormatTag'], 1);
      expect(values['channels'], 2);
      expect(values['sample_rate'], 44100);
      expect(values['byte_rate'], 176400);
      expect(values['block_align'], 4);
      expect(values['bit_depth'], 16);
      expect(fmt.fields.first.source, 'fmt ');
    });

    test('fmt 与 data 各自的大小与偏移是精确的', () {
      final result = parseFixtureFile('wav_pcm_s16le_44100_stereo.normal.wav');

      final ContainerNode fmt = findNode(result.root, 'fmt ')!;
      expect(fmt.offset, 12);
      expect(fmt.size, 24);
      expect(fmt.dataOffset, 20);
      expect(fmt.dataSize, 16);

      final ContainerNode data = findNode(result.root, 'data')!;
      expect(data.offset, 70);
      expect(data.size, 44108);
      expect(data.dataOffset, 78);
      expect(data.dataSize, 44100);
    });

    test('不认识的子块（ISFT）仍然出现在树里，不会被丢掉', () {
      final result = parseFixtureFile('wav_pcm_s16le_44100_stereo.normal.wav');

      final ContainerNode? list = findNode(result.root, 'LIST');
      expect(list, isNotNull);
      expect(list!.children.map((ContainerNode c) => c.type), contains('ISFT'));
      expect(findNode(result.root, 'ISFT')!.isOpaque, isTrue);
    });

    test('24bit 样本用 WAVEFORMATEXTENSIBLE，fmt 载荷更长', () {
      final result = parseFixtureFile('wav_pcm_s24le_48000_stereo.edge.wav');

      final ContainerNode fmt = findNode(result.root, 'fmt ')!;
      expect(fieldValues(fmt)['wFormatTag'], 0xFFFE);
      expect(fmt.size, 48);
      expect(fieldValues(fmt)['bit_depth'], 24);
      expect(fieldValues(fmt)['sample_rate'], 48000);
    });

    test('8bit 单声道边界样本：位深 8、采样率 8000、声道 1', () {
      final result = parseFixtureFile('wav_pcm_u8_8000_mono.edge.wav');

      final Map<String, Object?> values = fieldValues(
        findNode(result.root, 'fmt ')!,
      );
      expect(values['bit_depth'], 8);
      expect(values['sample_rate'], 8000);
      expect(values['channels'], 1);
    });
  });

  group('AIFF：FORM chunk 结构', () {
    test('根节点是 AIFF，顶层是 FORM 块，form type 是 AIFF', () {
      final result = parseFixtureFile('aiff_pcm_s16be_48000_mono.normal.aiff');

      expect(result.root.type, 'AIFF');
      final ContainerNode form = result.root.children.single;
      expect(form.type, 'FORM');
      expect(fieldValues(form)['form_type'], 'AIFF');
      expect(form.size, 24054);
    });

    test('COMM 块给出声道数 / 采样帧数 / 位深', () {
      final result = parseFixtureFile('aiff_pcm_s16be_48000_mono.normal.aiff');

      final ContainerNode comm = findNode(result.root, 'COMM')!;
      final Map<String, Object?> values = fieldValues(comm);
      expect(values['num_channels'], 1);
      expect(values['num_sample_frames'], 12000);
      expect(values['sample_size'], 16);
      expect(comm.offset, 12);
      expect(comm.size, 26);
    });

    test('AIFF 的长度字段是大端（与 WAV 的小端不同）', () {
      final result = parseFixtureFile('aiff_pcm_s16be_48000_mono.normal.aiff');

      // 长度 24046 = 文件长 24054 - 8 字节块头。
      expect(result.root.children.single.size, 24054);
      expect(result.root.size, 24054);
    });

    test('SSND 块存在并带 offset / block_size 字段', () {
      final result = parseFixtureFile('aiff_pcm_s16be_48000_mono.normal.aiff');

      final ContainerNode ssnd = findNode(result.root, 'SSND')!;
      expect(ssnd.offset, 38);
      final Map<String, Object?> values = fieldValues(ssnd);
      expect(values['offset'], 0);
      expect(values['block_size'], 0);
    });

    test('24bit 立体声边界样本：COMM 给出 2 声道 24bit', () {
      final result = parseFixtureFile('aiff_pcm_s24be_44100_stereo.edge.aiff');

      final Map<String, Object?> values = fieldValues(
        findNode(result.root, 'COMM')!,
      );
      expect(values['num_channels'], 2);
      expect(values['sample_size'], 24);
      expect(values['num_sample_frames'], 11025);
    });
  });

  group('FLAC：metadata block 与 STREAMINFO', () {
    test('根节点是 FLAC，子块是 STREAMINFO 与 VORBIS_COMMENT', () {
      final result = parseFixtureFile('flac_s16_44100_stereo.normal.flac');

      expect(result.root.type, 'FLAC');
      expect(result.root.children.map((ContainerNode c) => c.type), <String>[
        'STREAMINFO',
        'VORBIS_COMMENT',
        'PADDING',
      ]);
    });

    test('STREAMINFO 给出位深 / 采样率 / 总采样数 / MD5', () {
      final result = parseFixtureFile('flac_s16_44100_stereo.normal.flac');

      final ContainerNode info = findNode(result.root, 'STREAMINFO')!;
      final Map<String, Object?> values = fieldValues(info);
      expect(values['sample_rate'], 44100);
      expect(values['channels'], 2);
      expect(values['bits_per_sample'], 16);
      expect(values['total_samples'], 11025);
      expect(values['md5'], 'f71656b039680036049eae0992606cfe');
      expect(
        (values['md5']! as String).length,
        32,
        reason: 'MD5 是 16 字节 = 32 个十六进制字符',
      );
    });

    test('24bit / 96kHz 边界样本：采样率与位深照实读出', () {
      final result = parseFixtureFile('flac_s24_96000_mono.edge.flac');

      final Map<String, Object?> values = fieldValues(
        findNode(result.root, 'STREAMINFO')!,
      );
      expect(values['sample_rate'], 96000);
      expect(values['bits_per_sample'], 24);
      expect(values['channels'], 1);
      expect(values['total_samples'], 24000);
    });

    test('VORBIS_COMMENT 块带 vendor 与字段数', () {
      final result = parseFixtureFile('flac_s16_44100_stereo.normal.flac');

      final ContainerNode comment = findNode(result.root, 'VORBIS_COMMENT')!;
      final Map<String, Object?> values = fieldValues(comment);
      expect(values['vendor_length'], 12);
      expect(values['vendor'], 'Lavf61.3.104');
      expect(values['field_count'], 1);
    });
  });

  group('MP3：帧头', () {
    test('根节点是 MP3，第一个子块是 ID3v2，其余是 MPEG Audio Frame', () {
      final result = parseFixtureFile('mp3_cbr128_44100_stereo.normal.mp3');

      expect(result.root.type, 'MP3');
      expect(result.root.children.first.type, 'ID3v2');
      expect(
        result.root.children
            .skip(1)
            .every((ContainerNode c) => c.type == 'MPEG Audio Frame'),
        isTrue,
      );
    });

    test('ID3v2 头给出版本与标志位', () {
      final result = parseFixtureFile('mp3_cbr128_44100_stereo.normal.mp3');

      final Map<String, Object?> values = fieldValues(
        result.root.children.first,
      );
      expect(values['id3v2_version'], '4.0');
      expect(values['id3v2_flags'], 0);
    });

    test('帧头给出版本 / 层 / 码率 / 采样率', () {
      final result = parseFixtureFile('mp3_cbr128_44100_stereo.normal.mp3');

      final ContainerNode frame = result.root.children[1];
      final Map<String, Object?> values = fieldValues(frame);
      expect(values['mpeg_version'], 'MPEG-1');
      expect(values['layer'], 3);
      expect(values['bitrate'], 128);
      expect(values['bitrate_mode'], 'CBR');
      expect(values['sample_rate'], 44100);
      expect(values['samples_per_frame'], 1152);
      expect(values['crc_protected'], isFalse);
    });

    test('MP3 没有块树：一帧一个节点，帧数等于节点数', () {
      final result = parseFixtureFile('mp3_cbr128_44100_stereo.normal.mp3');

      final int frames = result.root.children
          .where((ContainerNode c) => c.type == 'MPEG Audio Frame')
          .length;
      expect(frames, greaterThan(5));
      expect(result.root.children, hasLength(frames + 1));
    });

    test('VBR 边界样本：MPEG-2、每帧 576 个样本', () {
      final result = parseFixtureFile('mp3_vbr_q2_22050_mono.edge.mp3');

      final ContainerNode frame = result.root.children[1];
      final Map<String, Object?> values = fieldValues(frame);
      expect(values['mpeg_version'], 'MPEG-2');
      expect(values['bitrate_mode'], 'VBR');
      expect(values['sample_rate'], 22050);
      expect(values['samples_per_frame'], 576);
      expect(values['channel_mode'], 'Mono');
    });
  });

  group('MP4：完整 box 树', () {
    test('顶层块按文件顺序排列：ftyp、free、mdat、moov', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      expect(result.root.children.map((ContainerNode c) => c.type), <String>[
        'ftyp',
        'free',
        'mdat',
        'moov',
      ]);
    });

    test('moov 下是 mvhd、trak、trak、udta', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      final ContainerNode moov = findNode(result.root, 'moov')!;
      expect(moov.children.map((ContainerNode c) => c.type), <String>[
        'mvhd',
        'trak',
        'trak',
        'udta',
      ]);
    });

    test('trak 下是 tkhd、edts、mdia', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      final ContainerNode trak = findNode(result.root, 'trak')!;
      expect(trak.children.map((ContainerNode c) => c.type), <String>[
        'tkhd',
        'edts',
        'mdia',
      ]);
      expect(findNode(trak, 'mdia'), isNotNull);
    });

    test('顶层块的偏移量与长度是精确的', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      final ContainerNode ftyp = findNode(result.root, 'ftyp')!;
      expect(ftyp.offset, 0);
      expect(ftyp.size, 32);

      final ContainerNode mdat = findNode(result.root, 'mdat')!;
      expect(mdat.offset, 40);
      expect(mdat.size, 9787);

      final ContainerNode moov = findNode(result.root, 'moov')!;
      expect(moov.offset, 9827);
      expect(moov.size, 1831);
    });

    test('ftyp 给出主品牌与兼容品牌', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      final Map<String, Object?> values = fieldValues(
        findNode(result.root, 'ftyp')!,
      );
      expect(values['major_brand'], 'isom');
      expect(values['minor_version'], 512);
      expect(
        (values['compatible_brands']! as List<int>).length,
        16,
        reason: '四个 fourcc：isom / iso2 / avc1 / mp41',
      );
    });

    test('填充块 free 保留在树里（不透明叶子）', () {
      final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');

      final ContainerNode free = findNode(result.root, 'free')!;
      expect(free.isOpaque, isTrue);
      expect(free.dataSize, 0);
      expect(free.size, 8);
    });

    test('没有音轨的边界样本只有一条 trak', () {
      final result = parseFixtureFile('mp4_h264_noaudio_320x240.edge.mp4');

      final ContainerNode moov = findNode(result.root, 'moov')!;
      expect(
        moov.children.where((ContainerNode c) => c.type == 'trak'),
        hasLength(1),
      );
    });
  });

  group('MOV：QuickTime 素材', () {
    test('顶层块是 ftyp、wide、mdat、moov', () {
      final result = parseFixtureFile('mov_mpeg4_aac_320x240.normal.mov');

      expect(result.root.type, 'MP4');
      expect(result.root.children.map((ContainerNode c) => c.type), <String>[
        'ftyp',
        'wide',
        'mdat',
        'moov',
      ]);
    });

    test('ftyp 的主品牌是 qt（QuickTime）', () {
      final result = parseFixtureFile('mov_mpeg4_aac_320x240.normal.mov');

      expect(
        fieldValues(findNode(result.root, 'ftyp')!)['major_brand'],
        'qt  ',
      );
    });

    test('QuickTime 的 wide 占位盒保留在树里', () {
      final result = parseFixtureFile('mov_mpeg4_aac_320x240.normal.mov');

      final ContainerNode wide = findNode(result.root, 'wide')!;
      expect(wide.offset, 20);
      expect(wide.size, 8);
      expect(wide.isOpaque, isTrue);
    });

    test('udta 里的 ©swr 原子保留在树里', () {
      final result = parseFixtureFile('mov_mpeg4_aac_320x240.normal.mov');

      expect(allTypes(result.root), contains('©swr'));
    });
  });

  group('MKV / WebM：EBML 元素树', () {
    test('顶层是 EBML 头与 Segment', () {
      final result = parseFixtureFile('mkv_vp9_opus_320x240.normal.mkv');

      expect(result.root.type, 'Matroska');
      expect(result.root.children.map((ContainerNode c) => c.type), <String>[
        '0x1A45DFA3',
        '0x18538067',
      ]);
    });

    test('EBML 头里有 DocType', () {
      final result = parseFixtureFile('mkv_vp9_opus_320x240.normal.mkv');

      final ContainerNode header = result.root.children.first;
      final ContainerNode docType = header.children.firstWhere(
        (ContainerNode c) => c.type == '0x4282',
      );
      expect(docType.fields, isNotEmpty);
      expect(docType.fields.first.key, 'DocType');
    });

    test('Segment 下有 SeekHead、Info、Tracks、Cluster、Cues', () {
      final result = parseFixtureFile('mkv_vp9_opus_320x240.normal.mkv');

      final ContainerNode segment = result.root.children.last;
      final List<String> types = segment.children
          .map((ContainerNode c) => c.type)
          .toList();
      expect(types, contains('0x114D9B74'));
      expect(types, contains('0x1549A966'));
      expect(types, contains('0x1654AE6B'));
      expect(types, contains('0x1F43B675'));
      expect(types, contains('0x1C53BB6B'));
    });

    test('Cluster 的 SimpleBlock 是不透明叶子（块 lacing 载荷不可表驱动）', () {
      final result = parseFixtureFile('mkv_vp9_opus_320x240.normal.mkv');

      final ContainerNode cluster = findNode(result.root, '0x1F43B675')!;
      final List<ContainerNode> blocks = cluster.children
          .where((ContainerNode c) => c.type == '0xA3')
          .toList();
      expect(blocks, isNotEmpty);
      expect(blocks.first.isOpaque, isTrue);
      expect(blocks.first.children, isEmpty);
    });

    test('Void 这样的填充元素也留在树里', () {
      final result = parseFixtureFile('mkv_vp9_opus_320x240.normal.mkv');

      expect(allTypes(result.root), contains('0xEC'));
    });

    test('WebM 的 DocType 是 webm，Tracks 下有两条 TrackEntry', () {
      final result = parseFixtureFile('webm_vp8_vorbis_320x240.normal.webm');

      final ContainerNode header = result.root.children.first;
      final ContainerNode docType = header.children.firstWhere(
        (ContainerNode c) => c.type == '0x4282',
      );
      expect(docType.fields.first.value, <int>[119, 101, 98, 109]);

      final ContainerNode tracks = findNode(result.root, '0x1654AE6B')!;
      expect(
        tracks.children.where((ContainerNode c) => c.type == '0xAE'),
        hasLength(2),
      );
    });
  });

  group('损坏文件：已读到的部分结构仍然返回', () {
    test('MP4 被截断：标记截断、给出中文说明、已读的 ftyp 仍在', () {
      final result = parseFixtureFile(
        'mp4_h264_aac_320x240.normal.truncated.mp4',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 6994 处截断，声明长度还差 2833 字节');
      expect(findNode(result.root, 'ftyp'), isNotNull);
      expect(findNode(result.root, 'moov'), isNull);
    });

    test('WAV 的长度字段撒谎：走同一条截断路径', () {
      final result = parseFixtureFile(
        'wav_pcm_s16le_44100_stereo.normal.liesize.wav',
      );

      expect(result.truncated, isTrue);
      expect(result.error, contains('截断'));
      expect(result.error, contains('还差 4294922906 字节'));
      expect(findNode(result.root, 'fmt '), isNotNull);
    });

    test('WAV 被截断：data 块被裁到实际长度', () {
      final result = parseFixtureFile(
        'wav_pcm_s16le_44100_stereo.normal.truncated.wav',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 26506 处截断，声明长度还差 17672 字节');
      final ContainerNode data = findNode(result.root, 'data')!;
      expect(data.isOpaque, isTrue);
      expect(data.dataSize, 26428);
    });

    test('AIFF 被截断：COMM 仍读得到', () {
      final result = parseFixtureFile(
        'aiff_pcm_s16be_48000_mono.normal.truncated.aiff',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 14432 处截断，声明长度还差 9622 字节');
      expect(fieldValues(findNode(result.root, 'COMM')!)['num_channels'], 1);
    });

    test('FLAC 被截断：STREAMINFO 仍读得到', () {
      final result = parseFixtureFile(
        'flac_s16_44100_stereo.normal.truncated.flac',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 94 处截断，声明长度还差 1416 字节');
      expect(
        fieldValues(findNode(result.root, 'STREAMINFO')!)['sample_rate'],
        44100,
      );
    });

    test('MP3 被截断：说明里写明帧声明长度还差多少', () {
      final result = parseFixtureFile(
        'mp3_cbr128_44100_stereo.normal.truncated.mp3',
      );

      expect(result.truncated, isTrue);
      expect(result.error, contains('帧声明长度还差'));
      expect(result.error, contains('352 字节'));
    });

    test('MKV 被截断：EBML 头仍在', () {
      final result = parseFixtureFile(
        'mkv_vp9_opus_320x240.normal.truncated.mkv',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 10492 处截断，声明长度还差 6995 字节');
      expect(findNode(result.root, '0x1A45DFA3'), isNotNull);
    });

    test('WebM 被截断：EBML 头仍在', () {
      final result = parseFixtureFile(
        'webm_vp8_vorbis_320x240.normal.truncated.webm',
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 20745 处截断，声明长度还差 13831 字节');
      expect(findNode(result.root, '0x1A45DFA3'), isNotNull);
    });
  });

  group('块覆盖率清单', () {
    test('每个格式的必查块都能在结构树里找到', () {
      for (final BlockCoverage coverage in blockCoverageLists.values) {
        final String fixture = _fixtureOf(coverage.format);
        final result = parseFixtureFile(fixture);

        expect(
          missingRequiredBlocks(result.root, coverage),
          isEmpty,
          reason: '${coverage.format} 的必查块缺失（素材：$fixture）',
        );
      }
    });
  });
}

/// 按格式名挑一个正常素材。
String _fixtureOf(String format) => switch (format) {
  'WAV' => 'wav_pcm_s16le_44100_stereo.normal.wav',
  'AIFF' => 'aiff_pcm_s16be_48000_mono.normal.aiff',
  'FLAC' => 'flac_s16_44100_stereo.normal.flac',
  'MP3' => 'mp3_cbr128_44100_stereo.normal.mp3',
  'MP4' => 'mp4_h264_aac_320x240.normal.mp4',
  'MOV' => 'mov_mpeg4_aac_320x240.normal.mov',
  'MKV' => 'mkv_vp9_opus_320x240.normal.mkv',
  'WebM' => 'webm_vp8_vorbis_320x240.normal.webm',
  _ => throw ArgumentError('没有 $format 的素材'),
};
