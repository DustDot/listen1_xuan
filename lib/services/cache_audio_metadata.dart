import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path/path.dart' as p;

class CacheTrackMetadata {
  const CacheTrackMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
}

class CacheAudioMetadata {
  const CacheAudioMetadata();

  static const _maxErrorLength = 2000;

  Future<void> rewrite({
    required String inputPath,
    required String outputPath,
    required bool retainMetadata,
    CacheTrackMetadata? metadata,
  }) async {
    final session = await _execute(
      buildArguments(
        inputPath: inputPath,
        outputPath: outputPath,
        retainMetadata: retainMetadata,
        metadata: metadata,
      ),
    );
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) return;

    final output = await session.getOutput();
    throw CacheAudioMetadataException(_errorMessage(output));
  }

  static List<String> buildArguments({
    required String inputPath,
    required String outputPath,
    required bool retainMetadata,
    CacheTrackMetadata? metadata,
  }) {
    final arguments = <String>[
      '-hide_banner',
      '-nostdin',
      '-loglevel',
      'warning',
      '-i',
      inputPath,
      '-map',
      '0:a:0',
      '-c:a',
      'copy',
      ...outputMetadataArguments(
        retainMetadata: retainMetadata,
        metadata: metadata,
        outputPath: outputPath,
      ),
    ];

    if (p.extension(outputPath).toLowerCase() == '.mka') {
      arguments.addAll(['-f', 'matroska']);
    }
    arguments.addAll(['-y', outputPath]);
    return arguments;
  }

  static List<String> outputMetadataArguments({
    required bool retainMetadata,
    required String outputPath,
    CacheTrackMetadata? metadata,
  }) {
    final arguments = <String>[];
    if (retainMetadata) {
      _addMetadata(arguments, 'title', metadata?.title);
      _addMetadata(arguments, 'artist', metadata?.artist);
      _addMetadata(arguments, 'album', metadata?.album);
      _addMetadata(arguments, 'album_artist', metadata?.albumArtist);
    } else {
      arguments.addAll([
        '-map_metadata',
        '-1',
        '-map_metadata:s:a',
        '-1',
        '-map_chapters',
        '-1',
        '-fflags',
        '+bitexact',
      ]);
    }

    if (p.extension(outputPath).toLowerCase() == '.mp3') {
      arguments.addAll(['-id3v2_version', '3']);
    }
    return arguments;
  }

  static String temporaryOutputPath(String targetPath) {
    final extension = p.extension(targetPath);
    if (extension.isEmpty) return '$targetPath.listen1-metadata.mka';
    return '${p.withoutExtension(targetPath)}.listen1-metadata$extension';
  }

  static String temporaryDownloadPath(String targetPath) {
    final extension = p.extension(targetPath);
    if (extension.isEmpty) return '$targetPath.listen1-download';
    return '${p.withoutExtension(targetPath)}.listen1-download$extension';
  }

  static Future<FFmpegSession> _execute(List<String> arguments) async {
    final completedSession = Completer<FFmpegSession>();
    await FFmpegKit.executeWithArgumentsAsync(arguments, (session) {
      if (!completedSession.isCompleted) completedSession.complete(session);
    });
    return completedSession.future;
  }

  static void _addMetadata(List<String> arguments, String key, String? value) {
    final normalized = value?.replaceAll('\u0000', '').trim() ?? '';
    if (normalized.isEmpty) return;
    arguments.addAll(['-metadata', '$key=$normalized']);
  }

  static String _errorMessage(String? output) {
    final message = output?.trim() ?? '';
    if (message.isEmpty) return '缓存元数据处理失败';
    if (message.length <= _maxErrorLength) return message;
    return 'FFmpeg 输出过长，仅显示末尾：\n'
        '${message.substring(message.length - _maxErrorLength)}';
  }
}

class CacheAudioMetadataException implements Exception {
  const CacheAudioMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}
