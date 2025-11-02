import 'dart:typed_data';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveCsv(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = io.File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  // Partage natif (Mail, Drive, etc.)
  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Export partenaires',
  );
}
