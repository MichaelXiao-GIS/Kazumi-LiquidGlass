import 'dart:typed_data';

import 'package:saver_gallery/saver_gallery.dart';
import 'package:synchronized/synchronized.dart';

// The iOS gallery plugin has a single pending result callback.
final _galleryWrites = Lock();

Future<SaveResult> savePngToGallery(Uint8List bytes, String fileName) =>
    _galleryWrites.synchronized(
      () => SaverGallery.saveImage(
        bytes,
        fileName: fileName,
        extension: 'png',
        skipIfExists: false,
      ),
    );
