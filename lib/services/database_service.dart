import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/bill.dart';
import 'error_reporter.dart';

/// 数据库服务 — SQLite 本地存储
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // 用 sqflite 官方推荐的 databases 目录（Android/HarmonyOS 上比
    // documents 目录更可靠，避免自定义路径在部分机型上的读写分叉问题）
    final dir = await getDatabasesPath();
    final dbPath = p.join(dir, 'ai_accounting.db');

    try {
      return await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE bills (
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              type        TEXT    NOT NULL,
              category    TEXT    NOT NULL,
              subcategory TEXT    DEFAULT '',
              amount      REAL    NOT NULL,
              date        TEXT    NOT NULL,
              remark      TEXT    DEFAULT '',
              created_at  TEXT    NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_bills_date ON bills(date)');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 → v2：新增子分类列，旧数据保留、子分类留空
          if (oldVersion < 2) {
            await db.execute(
                "ALTER TABLE bills ADD COLUMN subcategory TEXT DEFAULT ''");
          }
        },
      );
    } catch (e, st) {
      // 打开失败：可能是残留的损坏数据库文件 → 删除后重建再试一次
      ErrorReporter.report('db_open_first_attempt', e, st);
      try {
        final f = File(dbPath);
        if (await f.exists()) {
          await f.delete();
        }
        // 同时清理 -journal / -wal 残留
        for (final suffix in ['-journal', '-wal', '-shm']) {
          final aux = File('$dbPath$suffix');
          if (await aux.exists()) await aux.delete();
        }
        return await openDatabase(
          dbPath,
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE bills (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                type        TEXT    NOT NULL,
                category    TEXT    NOT NULL,
                subcategory TEXT    DEFAULT '',
                amount      REAL    NOT NULL,
                date        TEXT    NOT NULL,
                remark      TEXT    DEFAULT '',
                created_at  TEXT    NOT NULL
              )
            ''');
            await db.execute(
                'CREATE INDEX idx_bills_date ON bills(date)');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await db.execute(
                  "ALTER TABLE bills ADD COLUMN subcategory TEXT DEFAULT ''");
            }
          },
        );
      } catch (e2, st2) {
        ErrorReporter.report('db_open_after_rebuild', e2, st2);
        rethrow;
      }
    }
  }

  /// 插入一条账单，返回自增 id
  Future<int> insertBill(Bill bill) async {
    final db = await database;
    return await db.insert('bills', bill.toJson());
  }

  /// 更新一条账单（按 id），返回受影响行数
  Future<int> updateBill(Bill bill) async {
    if (bill.id == null) {
      throw ArgumentError('更新账单必须带 id');
    }
    final db = await database;
    final data = bill.toJson()..remove('id');
    return await db.update('bills', data,
        where: 'id = ?', whereArgs: [bill.id]);
  }

  /// 删除账单
  Future<int> deleteBill(int id) async {
    final db = await database;
    return await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取指定月份的所有账单（按日期降序排列）
  Future<List<Bill>> getBillsByMonth(String yearMonth) async {
    final db = await database;
    final startDate = '$yearMonth-01';
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final endDay = DateTime(year, month + 1, 0).day;
    final endDate = '$yearMonth-$endDay';

    final results = await db.query(
      'bills',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC, created_at DESC',
    );

    return results.map((row) => Bill.fromJson(row)).toList();
  }

  /// 获取月度收支汇总
  Future<Map<String, double>> getMonthlySummary(String yearMonth) async {
    final db = await database;
    final startDate = '$yearMonth-01';
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final endDay = DateTime(year, month + 1, 0).day;
    final endDate = '$yearMonth-$endDay';

    final results = await db.rawQuery('''
      SELECT type, SUM(amount) as total
      FROM bills
      WHERE date >= ? AND date <= ?
      GROUP BY type
    ''', [startDate, endDate]);

    double income = 0;
    double expense = 0;
    for (final row in results) {
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      if (row['type'] == '收入') {
        income = total;
      } else {
        expense = total;
      }
    }
    return {'收入': income, '支出': expense};
  }

  /// 获取年度汇总（按月分组的收支 + 总计）
  Future<Map<String, dynamic>> getYearlySummary(int year) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT
        substr(date, 6, 2) as month,
        type,
        SUM(amount) as total
      FROM bills
      WHERE date >= ? AND date <= ?
      GROUP BY month, type
      ORDER BY month
    ''', ['$year-01-01', '$year-12-31']);

    // 构建月度数据
    final monthly = <int, Map<String, double>>{};
    double totalIncome = 0;
    double totalExpense = 0;

    for (final row in results) {
      final month = int.parse(row['month'] as String);
      final type = row['type'] as String;
      final total = (row['total'] as num?)?.toDouble() ?? 0;

      monthly.putIfAbsent(month, () => {'收入': 0, '支出': 0});
      monthly[month]![type] = total;

      if (type == '收入') {
        totalIncome += total;
      } else {
        totalExpense += total;
      }
    }

    return {
      'year': year,
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'balance': totalIncome - totalExpense,
      'monthly': monthly,
    };
  }

  /// 库中已有账单的内容指纹集合（导入增量去重用）
  /// 只取去重所需的列，避免把整表读成 Bill 对象
  Future<Set<String>> getExistingFingerprints() async {
    final db = await database;
    final rows = await db.query(
      'bills',
      columns: ['type', 'category', 'subcategory', 'amount', 'date', 'remark'],
    );
    return rows.map((row) => Bill.fromJson(row).fingerprint).toSet();
  }

  /// 批量插入账单（用于导入历史数据）
  /// 分块提交（每 100 条一个事务）：避免超大事务在部分机型上失败
  Future<int> bulkInsertBills(List<Bill> bills) async {
    final db = await database;
    var inserted = 0;
    const chunkSize = 100;
    for (var i = 0; i < bills.length; i += chunkSize) {
      final end = (i + chunkSize) < bills.length ? i + chunkSize : bills.length;
      final batch = db.batch();
      for (final bill in bills.sublist(i, end)) {
        batch.insert('bills', bill.toJson());
      }
      final results = await batch.commit(noResult: false);
      inserted += results.length;
    }
    return inserted;
  }

  /// 获取最近 N 条账单
  Future<List<Bill>> getRecentBills({int limit = 5}) async {
    final db = await database;
    final results = await db.query(
      'bills',
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return results.map((row) => Bill.fromJson(row)).toList();
  }

  /// 获取全部账单（导出备份用，按日期正序，便于在表格里阅读）
  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final results = await db.query(
      'bills',
      orderBy: 'date ASC, created_at ASC',
    );
    return results.map((row) => Bill.fromJson(row)).toList();
  }
}
