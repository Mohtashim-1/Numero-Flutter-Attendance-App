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
  String selectedGroup = 'All';
  List<String> groups = ['All'];

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
    await loadLocal();
    await syncToServer();
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
            '&limit_page_length=1000'
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
    final allGroups = data.map((e) => e['student_group'].toString()).toSet().toList();
    setState(() {
      groups = ['All', ...allGroups];
      attendanceList = data;
    });
  }

  Future<void> syncToServer() async {
    if (!isOnline) return;
    final unsynced = await db.query('attendance', where: 'synced = 0 AND signature != ""');

    for (var record in unsynced) {
      try {
        final uploadResponse = await http.post(
          // Uri.parse('http://192.168.100.10:8003/api/method/upload_file'),
          Uri.parse('http://192.168.100.10:8003/api/method/frappe.client.attach_file'),
          headers: {
            'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            // "file_name": "${record['name']}.png",
            // "is_private": 0,
            // "attached_to_doctype": "Student Attendance",
            // "attached_to_name": record['name'],
            // "attached_to_field": "custom_student_signature1",
            // "content": record['signature'],
            // "encoding": "base64"
            "filename": "${record['name']}.png",
            "is_private": 0,
            "doctype": "Student Attendance",
            "docname": record['name'],
            "fieldname": "custom_student_signature1",
            "filedata": "data:image/png;base64,${record['signature']}"
          }),
        );

        if (uploadResponse.statusCode == 200) {
          final uploaded = jsonDecode(uploadResponse.body);
          final fileUrl = uploaded['message']['file_url'];

          final url = Uri.parse('http://192.168.100.10:8003/api/resource/Student%20Attendance/${record['name']}');
          final response = await http.put(
            url,
            headers: {
              'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'custom_student_signature1': fileUrl,
            }),
          );

          print("PUT ${record['name']} => ${response.statusCode}");
          print("Response: ${response.body}");

          if (response.statusCode == 200) {
            await db.update('attendance', {'synced': 1}, where: 'name = ?', whereArgs: [record['name']]);
          } else {
            print("Failed to sync ${record['name']} => ${response.body}");
          }
        } else {
          print("Upload failed for ${record['name']}: ${uploadResponse.body}");
        }
      } catch (e) {
        print("Sync error for ${record['name']}: $e");
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
      await syncToServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = attendanceList.where((item) => selectedGroup == 'All' || item['student_group'] == selectedGroup).toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Attendance List")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              value: selectedGroup,
              items: groups.map((group) => DropdownMenuItem(value: group, child: Text(group))).toList(),
              onChanged: (value) {
                setState(() {
                  selectedGroup = value!;
                });
              },
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (BuildContext context, int index) {
                final item = filtered[index];
                return ListTile(
                  title: Text("${item['student_name']} (${item['student']})"),
                  subtitle: Text(
                    "Course: ${item['course_schedule']} | Group: ${item['student_group']} | Date: ${item['date']}\n"
                        "Status: ${item['status']} | Customer: ${item['customer_name']}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => captureSignature(item['name']),
                  ),
                );
              },
            ),
          ),
        ],
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
