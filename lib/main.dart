import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:signature/signature.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Attendance',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AttendanceListPage(),
    );
  }
}

class AttendanceListPage extends StatefulWidget {
  @override
  _AttendanceListPageState createState() => _AttendanceListPageState();
}

class _AttendanceListPageState extends State<AttendanceListPage> {
  List<Map<String, dynamic>> attendanceList = [];
  late Database db;
  bool isOnline = false;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await clearDB();
    await initDB();
    await checkConnectivity();
    await fetchFromFrappe();
    await syncToServer();
    await loadLocal();
  }

  Future<void> clearDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'attendance.db');
    await deleteDatabase(path);
  }

  Future<void> initDB() async {
    final dbPath = await getDatabasesPath();
    db = await openDatabase(
      p.join(dbPath, 'attendance.db'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance(
            name TEXT PRIMARY KEY,
            student TEXT,
            student_name TEXT,
            course_schedule TEXT,
            student_group TEXT,
            date TEXT,
            status TEXT,
            customer_name TEXT,
            signature TEXT,
            synced INTEGER
          )
        ''');
      },
      version: 1,
    );
  }

  Future<void> checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      isOnline = connectivityResult != ConnectivityResult.none;
    });
  }

  Future<void> fetchFromFrappe() async {
    if (!isOnline) {
      print("Device offline, skipping fetch.");
      return;
    }

    final url = Uri.parse(
        'http://192.168.100.10:8003/api/resource/Student Attendance'
            '?fields=["name","student","student_name","course_schedule","student_group","date","status","customer_name"]'
    );

    try {
      final response = await http.get(url, headers: {
        'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
      });

      print("API Status Code: ${response.statusCode}");
      print("API Response: ${response.body}");

      if (response.statusCode != 200) {
        print("Fetch failed!");
        return;
      }

      final data = json.decode(response.body);
      final List items = data['data'];
      print("Received ${items.length} records");

      for (var record in items) {
        await db.insert('attendance', {
          'name': record['name'] ?? '',
          'student': record['student'] ?? '',
          'student_name': record['student_name'] ?? '',
          'course_schedule': record['course_schedule'] ?? '',
          'student_group': record['student_group'] ?? '',
          'date': record['date'] ?? '',
          'status': record['status'] ?? '',
          'customer_name': record['customer_name'] ?? '',
          'signature': '',
          'synced': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      print("Inserted records into SQLite.");

    } catch (e) {
      print("ERROR during fetch: $e");
    }
  }

  Future<void> loadLocal() async {
    final data = await db.query('attendance');
    print("LOADED LOCAL RECORDS: ${data.length}");
    for (var d in data) {
      print(d);
    }

    setState(() {
      attendanceList = data;
    });
  }

  Future<void> syncToServer() async {
    if (!isOnline) return;
    final unsynced = await db.query('attendance', where: 'synced = 0 AND signature != ""');

    for (var record in unsynced) {
      final url = Uri.parse('http://192.168.100.10:8003/api/resource/Student%20Attendance/${record['name']}');
      final response = await http.put(url,
          headers: {
            'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'student_signature': record['signature'],
          }));

      if (response.statusCode == 200) {
        await db.update('attendance', {'synced': 1}, where: 'name = ?', whereArgs: [record['name']]);
      }
    }
  }

  void captureSignature(String name) async {
    final controller = SignatureController();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignaturePad(controller: controller),
      ),
    );

    if (result != null && result is String) {
      await db.update('attendance', {'signature': result, 'synced': 0}, where: 'name = ?', whereArgs: [name]);
      await loadLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Attendance List")),
      body: attendanceList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: attendanceList.length,
        itemBuilder: (BuildContext context, int index) {
          final item = attendanceList[index];
          return ListTile(
            title: Text("${item['student_name'] ?? 'No Name'} (${item['student'] ?? '-'})"),
            subtitle: Text(
              "Course: ${item['course_schedule'] ?? '-'} | Group: ${item['student_group'] ?? '-'} | Date: ${item['date'] ?? '-'}\n"
                  "Status: ${item['status'] ?? '-'} | Customer: ${item['customer_name'] ?? '-'}",
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => captureSignature(item['name']),
            ),
          );
        },
      ),
    );
  }
}

class SignaturePad extends StatelessWidget {
  final SignatureController controller;

  const SignaturePad({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign Attendance")),
      body: Column(
        children: [
          Expanded(
            child: Signature(
              controller: controller,
              backgroundColor: Colors.grey[200]!,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final image = await controller.toPngBytes();
                  if (image != null) {
                    final base64Image = base64Encode(image);
                    Navigator.pop(context, base64Image);
                  }
                },
                child: const Text("Save"),
              ),
              ElevatedButton(
                onPressed: () => controller.clear(),
                child: const Text("Clear"),
              )
            ],
          )
        ],
      ),
    );
  }
}
