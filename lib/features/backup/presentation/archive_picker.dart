import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// A document provider may only expose a content URI. Keep the temporary
/// encrypted copy alive until the reader has closed it.
Future<T?> withPickedArchive<T>(Future<T> Function(File) read) async {
  final files = await FilePicker.pickFiles(type: FileType.any);
  if (files.isEmpty) return null;
  final selected = files.single;
  final path = selected.path;
  if (path != null && await File(path).exists()) return read(File(path));
  final temp = await Directory.systemTemp.createTemp('seneb-recovery-');
  try {
    final copy = File(p.join(temp.path, 'archive.seneb'));
    await copy.writeAsBytes(await selected.readAsBytes(), flush: true);
    return await read(copy);
  } finally {
    await temp.delete(recursive: true);
  }
}
