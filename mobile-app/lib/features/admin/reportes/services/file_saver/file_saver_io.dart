import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

Future<String> saveFileImpl({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  Directory? dir;

  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) {
      dir = await getExternalStorageDirectory();
    }
  } else {
    dir = await getApplicationDocumentsDirectory();
  }

  dir ??= await getApplicationDocumentsDirectory();
  final filePath = '${dir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes);

  final result = await OpenFile.open(filePath);
  if (result.type != ResultType.done && result.type != ResultType.noAppToOpen) {
    return 'Reporte guardado en: $filePath';
  }
  return 'Reporte $fileName descargado y abierto';
}
