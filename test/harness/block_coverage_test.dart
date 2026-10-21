import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/formats/matroska.dart';

import '../support/coverage_lists.dart';
import '../support/fixture_paths.dart';
import '../support/format_parsers.dart';

/// 覆盖率清单的格式名 → 素材的格式键。
const Map<String, String> _formatKeys = <String, String>{
  'WAV': 'wav',
  'AIFF': 'aiff',
  'FLAC': 'flac',
  'MP3': 'mp3',
  'MP4': 'mp4',
  'MOV': 'mov',
  'MKV': 'mkv',
  'WebM': 'webm',
};

void main() {
  group('清单本身', () {
    test('每个目标格式都有一份清单', () {
      expect(
        blockCoverageLists.keys.toSet(),
        containsAll(<String>[
          'WAV',
          'AIFF',
          'FLAC',
          'MP3',
          'MP4',
          'MOV',
          'MKV',
          'WebM',
        ]),
      );
    });

    test('每一条都写明了依据（哪份规范的哪一节）', () {
      for (final coverage in blockCoverageLists.values) {
        expect(coverage.spec, isNotEmpty, reason: coverage.format);
        for (final entry in coverage.entries) {
          expect(
            entry.spec,
            isNotEmpty,
            reason: '${coverage.format} ${entry.type}',
          );
          expect(
            entry.spec.length,
            greaterThan(10),
            reason: '${coverage.format} ${entry.type} 的依据写得太简略',
          );
        }
      }
    });

    test('MP4/MOV 的必查块覆盖了规范里要求的那些盒', () {
      expect(
        coverageFor('MP4').requiredTypes,
        containsAll(<String>[
          'ftyp',
          'moov',
          'trak',
          'mdia',
          'minf',
          'stbl',
          'stsd',
          'mdat',
          'free',
        ]),
      );
      expect(coverageFor('MP4').requiredTypes, contains('free'));
      expect(coverageFor('MOV').requiredTypes, contains('wide'));
    });

    test('skip / uuid 标成可选——ffmpeg 素材不写它们', () {
      for (final format in <String>['MP4', 'MOV']) {
        final coverage = coverageFor(format);
        expect(coverage.optionalTypes, contains('skip'), reason: format);
        expect(coverage.optionalTypes, contains('uuid'), reason: format);
        expect(coverage.requiredTypes, isNot(contains('skip')), reason: format);
        expect(coverage.requiredTypes, isNot(contains('uuid')), reason: format);
      }
    });

    test('Matroska 家族用规范名做块类型', () {
      for (final format in <String>['MKV', 'WebM']) {
        final coverage = coverageFor(format);
        expect(
          coverage.requiredTypes,
          containsAll(<String>[
            'EBML',
            'Segment',
            'Info',
            'Tracks',
            'TrackEntry',
            'Video',
            'Audio',
          ]),
          reason: format,
        );
      }
    });

    test('不认识格式时抛 ArgumentError', () {
      expect(() => coverageFor('WAVX'), throwsArgumentError);
    });
  });

  group('清单断言', () {
    for (final entry in _formatKeys.entries) {
      test('${entry.key}：必查的块都在结构树里', () {
        final coverage = coverageFor(entry.key);
        final fileName = requireFixtureName(
          entry.value,
          FixtureCategory.normal,
        );
        final result = parseFixtureFile(fileName);

        expect(result.truncated, isFalse, reason: fileName);
        expect(
          missingRequiredBlocks(result.root, coverage),
          isEmpty,
          reason: '$fileName 里找不到清单要求的块',
        );
      });
    }

    test('可选条目不进断言——素材里没有的块不算失败', () {
      // ffmpeg 素材里没有 `uuid` 盒，把它升级成必查就应当报缺失。
      const strict = BlockCoverage(
        format: 'MP4',
        spec: '测试用',
        entries: <BlockCoverageEntry>[
          BlockCoverageEntry('uuid', spec: 'ISO/IEC 14496-12 §8.10'),
        ],
      );
      final result = parseFixtureFile(
        requireFixtureName('mp4', FixtureCategory.normal),
      );

      expect(missingRequiredBlocks(result.root, strict), <String>['uuid']);
    });

    test('MP3 的帧节点是「MPEG Audio Frame」', () {
      const coverage = BlockCoverage(
        format: 'MP3',
        spec: 'ISO/IEC 11172-3',
        entries: <BlockCoverageEntry>[
          BlockCoverageEntry(
            'MPEG Audio Frame',
            spec: 'ISO/IEC 11172-3 §2.4.2.3',
          ),
        ],
      );
      final result = parseFixtureFile(
        requireFixtureName('mp3', FixtureCategory.normal),
      );

      expect(missingRequiredBlocks(result.root, coverage), isEmpty);
    });
  });

  group('Matroska 的块名归一化', () {
    test('元素 ID 换回规范名', () {
      expect(canonicalBlockType('MKV', '0x18538067'), 'Segment');
      expect(canonicalBlockType('MKV', '0x1549A966'), 'Info');
      expect(canonicalBlockType('MKV', '0x1654AE6B'), 'Tracks');
      expect(canonicalBlockType('MKV', '0xAE'), 'TrackEntry');
      expect(canonicalBlockType('MKV', '0xE0'), 'Video');
      expect(canonicalBlockType('MKV', '0xE1'), 'Audio');
      expect(canonicalBlockType('MKV', '0x1A45DFA3'), 'EBML');
    });

    test('换不回来的 ID 原样返回', () {
      expect(canonicalBlockType('MKV', '0xDEADBEEF'), '0xDEADBEEF');
      expect(matroskaElementName('0xDEADBEEF'), isNull);
    });

    test('非 Matroska 格式原样返回块名', () {
      expect(canonicalBlockType('MP4', 'ftyp'), 'ftyp');
      expect(canonicalBlockType('WAV', 'fmt '), 'fmt ');
    });

    test('收集到的块类型包含规范名', () {
      final result = parseFixtureFile(
        requireFixtureName('mkv', FixtureCategory.normal),
      );
      final types = collectBlockTypes(result.root, format: 'MKV');

      expect(types, containsAll(<String>['Segment', 'Info', 'Tracks']));
      expect(types, isNot(contains('0x18538067')));
    });
  });

  group('结构树遍历', () {
    test('收集到的块类型覆盖整棵树', () {
      final result = parseFixtureFile(
        requireFixtureName('mp4', FixtureCategory.normal),
      );
      final types = collectBlockTypes(result.root, format: 'MP4');

      expect(
        types,
        containsAll(<String>['ftyp', 'moov', 'trak', 'stsd', 'mdat']),
      );
      expect(types, contains('MP4'), reason: '根节点自己也在树里');
    });

    test('缺失的必查块按清单顺序报出来', () {
      const coverage = BlockCoverage(
        format: 'MP4',
        spec: '测试用',
        entries: <BlockCoverageEntry>[
          BlockCoverageEntry('mdat', spec: 'ISO/IEC 14496-12 §4.2'),
          BlockCoverageEntry('uuid', spec: 'ISO/IEC 14496-12 §8.10'),
          BlockCoverageEntry('nope', spec: '不存在的块'),
        ],
      );
      final root = ContainerNode(
        type: 'MP4',
        offset: 0,
        size: 0,
        dataOffset: 0,
        dataSize: 0,
      );

      expect(missingRequiredBlocks(root, coverage), <String>[
        'mdat',
        'uuid',
        'nope',
      ]);
    });
  });
}
