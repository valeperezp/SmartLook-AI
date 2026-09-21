import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.html) 'file_saver_web.dart';

abstract class FileSaver {
  static Future<String> saveAndOpenFile({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) =>
      saveFileImpl(bytes: bytes, fileName: fileName, mimeType: mimeType);
}
