import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VrixSettingsStore {
  static Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/vrix_settings.json');
  }
  static Future<Map<String, Object?>> load() async {
    final file = await _file();
    if (!await file.exists()) return <String, Object?>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return <String, Object?>{};
    return Map<String, Object?>.from(decoded);
  }
  static Future<void> save(Map<String, Object?> values) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
