import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/player/screenshot_candidate.dart';
import 'package:path/path.dart' as path;
import 'package:kazumi/services/platform/photo_gallery.dart';

class ScreenshotExportService {
  const ScreenshotExportService();

  bool get savesToPhotos => defaultTargetPlatform == TargetPlatform.iOS;

  Future<String?> chooseDestination() async {
    if (savesToPhotos) return '系统相册';
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择截图保存文件夹',
      lockParentWindow: true,
    );
  }

  Future<void> write(ScreenshotCandidate item, String location) async {
    final name = _fileName(item);
    if (savesToPhotos) {
      final result = await savePngToGallery(item.bytes, name);
      if (!result.isSuccess) {
        throw StateError(result.errorMessage ?? '无法写入系统相册');
      }
      return;
    }
    var file = File(path.join(location, name));
    var suffix = 1;
    while (await file.exists()) {
      file = File(
        path.join(
          location,
          '${path.basenameWithoutExtension(name)}_${suffix++}.png',
        ),
      );
    }
    await file.writeAsBytes(item.bytes, flush: true);
  }

  static String _fileName(ScreenshotCandidate item) {
    String clean(String value) {
      final safe = value
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .trim()
          .replaceAll(RegExp(r'[. ]+$'), '');
      // Leave room for the ID within common 255-byte filename limits.
      return String.fromCharCodes(safe.runes.take(24));
    }

    return 'Kazumi_${clean(item.title)}_${clean(item.episode)}_'
        '${item.timeLabel.replaceAll(':', '-')}_${item.id}.png';
  }
}
