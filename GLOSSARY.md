# media_info

A desktop tool for inspecting the internal structure of audio and video files on Windows and macOS. It answers
two questions at once: *what is this file* (semantic fields) and *what is this file made of* (container structure).

## Language

### The file

**容器 (Container)**:
The outermost structure of a media file, holding tracks and metadata in a format-specific tree — e.g. an
ISO base media file, a Matroska file, or a RIFF file.
_Avoid_: 封装格式, 包装格式, Format

**块 (Chunk)**:
One node of a container's structural tree, with a size, an offset in the file, and possibly children. Each
container family names these differently (ISO base media: box; RIFF: chunk; EBML: element), but they play
the same role and are shown the same way.
_Avoid_: Box, Atom, Element, 原子, 元素

**轨道 (Track)**:
One continuous sequence of media inside a container — a video track, an audio track, a subtitle track —
carrying its own codec, dimensions, and timing.
_Avoid_: Stream, 流, 轨

**语义字段 (Semantic Field)**:
A decoded, human-meaningful value about a file or one of its tracks — duration, sample rate, bit depth,
resolution — as opposed to the raw bytes it was derived from.
_Avoid_: 元数据, Metadata, 属性, Property

**结构树 (Structure Tree)**:
The expandable view of a container's chunks, showing each chunk's name, type, offset, and size.
_Avoid_: 结构视图, Box 树, 详情树
