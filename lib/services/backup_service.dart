import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/van_sale_db.dart';

/// Full SQLite backup / restore for VanSale offline DB.
class VanSaleBackupService {
  VanSaleBackupService(this.db);

  final VanSaleDb db;

  Future<File> createBackupFile() async {
    final srcPath = await db.databasePath();
    final src = File(srcPath);
    if (!await src.exists()) {
      throw StateError('Database file not found');
    }
    final database = await db.database;
    try {
      await database.execute('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final outDir = await getTemporaryDirectory();
    final dest = File(p.join(outDir.path, 'van_sale_backup_$stamp.db'));
    await src.copy(dest.path);
    return dest;
  }

  Future<void> shareBackup() async {
    final file = await createBackupFile();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'VanSale backup'),
    );
  }

  Future<void> restoreFromPath(String path) async {
    final src = File(path);
    if (!await src.exists()) {
      throw StateError('Backup file not found');
    }
    await db.closeDatabase();
    final dest = File(await db.databasePath());
    await src.copy(dest.path);
    await db.database; // reopen
  }
}
