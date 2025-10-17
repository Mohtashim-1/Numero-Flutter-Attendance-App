import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/constants.dart';
import '../models/student.dart';
import '../models/attendance.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), databaseName);
    return await openDatabase(
      path,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create students table
    await db.execute('''
      CREATE TABLE $studentsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        nationality TEXT NOT NULL,
        gender TEXT NOT NULL,
        eid_no TEXT NOT NULL,
        address TEXT NOT NULL,
        card_number TEXT NOT NULL,
        occupation TEXT NOT NULL,
        employer TEXT NOT NULL,
        issuing_place TEXT NOT NULL,
        blood_type TEXT NOT NULL,
        emergency_contact TEXT NOT NULL,
        email TEXT NOT NULL,
        contact_type TEXT NOT NULL,
        mode_of_payment TEXT NOT NULL,
        customer TEXT,
        customer_name TEXT,
        employer_name TEXT,
        signature_path TEXT,
        photo_path TEXT,
        front_card_image_path TEXT,
        back_card_image_path TEXT,
        extracted_photo_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Create attendance table
    await db.execute('''
      CREATE TABLE $attendanceTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL,
        student_name TEXT NOT NULL,
        eid_no TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        signature_path TEXT,
        photo_path TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Drop and recreate attendance table to remove timestamp column
      await db.execute('DROP TABLE IF EXISTS $attendanceTable');
      await db.execute('''
        CREATE TABLE $attendanceTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id TEXT NOT NULL,
          student_name TEXT NOT NULL,
          eid_no TEXT NOT NULL,
          status TEXT NOT NULL,
          notes TEXT,
          signature_path TEXT,
          photo_path TEXT,
          synced INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }
    
    if (oldVersion < 3) {
      // Add Emirates ID card image columns to students table
      await db.execute('ALTER TABLE $studentsTable ADD COLUMN front_card_image_path TEXT');
      await db.execute('ALTER TABLE $studentsTable ADD COLUMN back_card_image_path TEXT');
    }
    
    if (oldVersion < 4) {
      // Add extracted photo path column to students table
      await db.execute('ALTER TABLE $studentsTable ADD COLUMN extracted_photo_path TEXT');
    }
  }

  // Student operations
  Future<int> insertStudent(Student student) async {
    final db = await database;
    return await db.insert(studentsTable, student.toMap());
  }

  Future<List<Student>> getAllStudents() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      studentsTable,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Student.fromMap(maps[i]));
  }

  Future<Student?> getStudentByEid(String eidNo) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      studentsTable,
      where: 'eid_no = ?',
      whereArgs: [eidNo],
    );
    if (maps.isNotEmpty) {
      return Student.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateStudent(Student student) async {
    final db = await database;
    return await db.update(
      studentsTable,
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return await db.delete(
      studentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Attendance operations
  Future<int> insertAttendance(Attendance attendance) async {
    final db = await database;
    return await db.insert(attendanceTable, attendance.toMap());
  }

  Future<List<Attendance>> getAllAttendance() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      attendanceTable,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<List<Attendance>> getAttendanceByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final List<Map<String, dynamic>> maps = await db.query(
      attendanceTable,
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<List<Attendance>> getUnsyncedAttendance() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      attendanceTable,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<int> markAttendanceAsSynced(int id) async {
    final db = await database;
    return await db.update(
      attendanceTable,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateAttendance(Attendance attendance) async {
    final db = await database;
    return await db.update(
      attendanceTable,
      attendance.toMap(),
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
  }

  Future<int> deleteAttendance(int id) async {
    final db = await database;
    return await db.delete(
      attendanceTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Statistics
  Future<Map<String, int>> getAttendanceStats(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final List<Map<String, dynamic>> maps = await db.query(
      attendanceTable,
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
    );

    int present = 0;
    int absent = 0;
    int late = 0;

    for (var map in maps) {
      switch (map['status']) {
        case 'present':
          present++;
          break;
        case 'absent':
          absent++;
          break;
        case 'late':
          late++;
          break;
      }
    }

    return {
      'present': present,
      'absent': absent,
      'late': late,
      'total': maps.length,
    };
  }

  // Cleanup
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
