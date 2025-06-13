import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:signature/signature.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

const String baseUrl = 'http://192.168.100.10:8003';

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
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  void login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;

    final response = await http.post(
      Uri.parse('$baseUrl/api/method/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'usr': username, 'pwd': password},
    );

    final res = jsonDecode(response.body);
    if (response.statusCode == 200 && res['message'] == 'Logged In') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AttendanceListPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login failed: Invalid credentials")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: login,
              child: const Text('Login'),
            )
          ],
        ),
      ),
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
  String selectedStatus = 'All';
  List<String> groups = ['All'];
  List<String> statuses = ['All', 'Present', 'Absent'];
  String? lastSyncTime;
  String studentNameFilter = '';
  String studentIdFilter = '';
  String courseFilter = '';
  String customerFilter = '';
  String dateFilter = '';
  TextEditingController dateController = TextEditingController();
  DateTime? selectedDate;
  late StreamSubscription<ConnectivityResult> connectivitySubscription;

  @override
  void initState() {
    super.initState();
    initApp();
    connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      if (result != ConnectivityResult.none) {
        syncToServer();
      }
    });
  }

  @override
  void dispose() {
    connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> initApp() async {
    await initDB();
    await checkConnectivity();
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("First launch requires internet to fetch data.")),
      );
      return;
    }
    await fetchFromFrappe();
    await loadLocal();
    await syncToServer();
  }

  Future<void> initDB() async {
    final dbPath = await getDatabasesPath();
    db = await openDatabase(
      p.join(dbPath, 'attendance.db'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS attendance(
            name TEXT PRIMARY KEY,
            student TEXT,
            student_name TEXT,
            course_schedule TEXT,
            student_group TEXT,
            date TEXT,
            status TEXT,
            customer_name TEXT,
            signature TEXT,
            synced INTEGER,
            docstatus INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE attendance ADD COLUMN docstatus INTEGER');
        }
      },
      version: 2,
    );
  }

  Future<void> checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      isOnline = connectivityResult != ConnectivityResult.none;
    });
  }

  Future<void> fetchFromFrappe() async {
    if (!isOnline) return;
    final url = Uri.parse(
        '$baseUrl/api/resource/Student Attendance?fields=["name","student","student_name","course_schedule","student_group","date","status","customer_name","docstatus"]&filters=[["docstatus","=",0]]&limit_page_length=1000');
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List items = data['data'];
        for (var record in items) {
          await db.insert(
              'attendance',
              {
                'name': record['name'],
                'student': record['student'],
                'student_name': record['student_name'],
                'course_schedule': record['course_schedule'],
                'student_group': record['student_group'],
                'date': record['date'],
                'status': record['status'],
                'customer_name': record['customer_name'],
                'signature': '',
                'synced': 0,
                'docstatus': record['docstatus'] ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    } catch (e) {
      print("Fetch error: $e");
    }
  }

  Future<void> loadLocal() async {
    final data = await db.query('attendance');
    final allGroups =
        data.map((e) => e['student_group'].toString()).toSet().toList();
    setState(() {
      groups = ['All', ...allGroups];
      attendanceList = data;
    });
  }

  Future<void> syncToServer() async {
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You are offline. Sync will resume when online.")),
      );
      return;
    }
    final unsynced =
        await db.query('attendance', where: 'synced = 0 AND signature != ""');
    for (var record in unsynced) {
      try {
        final uploadResponse = await http.post(
            Uri.parse('$baseUrl/api/method/frappe.client.attach_file'),
            headers: {
              'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
              'Content-Type': 'application/json'
            },
            // body: jsonEncode({
            //   "filename": "${record['name']}.png",
            //   "is_private": 0,
            //   "doctype": "Student Attendance",
            //   "docname": record['name'],
            //   "fieldname": "custom_student_signature1",
            //   "filedata": "data:image/png;base64,${record['signature']}"
            // }),
            body: jsonEncode({
              "filename": "${record['name']}.png",
              "filedata": record['signature'], // no prefix
              "is_private": 0,
              "doctype": "Student Attendance",
              "docname": record['name'],
              "fieldname": "custom_student_signature1",
              "decode_base64": true // <-- helps Frappe auto-save the PNG
            }));

        if (uploadResponse.statusCode == 200) {
          final uploaded = jsonDecode(uploadResponse.body);
          final fileUrl = uploaded['message']['file_url'];

          final response = await http.put(
            Uri.parse(
                '$baseUrl/api/resource/Student%20Attendance/${record['name']}'),
            headers: {
              'Authorization': 'token cefea2fba4f0821:98bc3f8b6d96741',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(
                {'custom_student_signature1': fileUrl, 'docstatus': 1}),
          );

          if (response.statusCode == 200) {
            await db.update('attendance', {'synced': 1},
                where: 'name = ?', whereArgs: [record['name']]);
            setState(() {
              lastSyncTime = DateTime.now().toString();
            });
          }
        }
      } catch (e) {
        print("Sync error for ${record['name']}: $e");
      }
    }
  }

  Future<void> exportToCSV() async {
    final rows = <List<String>>[
      ['Name', 'Student', 'Status', 'Date', 'Synced']
    ];
    for (var row in attendanceList) {
      rows.add([
        row['name'],
        row['student'],
        row['status'],
        row['date'],
        row['synced'].toString()
      ]);
    }

    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/attendance.csv');
    await file.writeAsString(const ListToCsvConverter().convert(rows));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV exported to ${file.path}')),
    );
  }

  void captureSignature(Map<String, dynamic> record) async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignaturePad(
          controller: controller,
          record: record,
        ),
      ),
    );

    if (result != null && result is String) {
      await db.update(
          'attendance',
          {
            'signature': result,
            'synced': 0,
          },
          where: 'name = ?',
          whereArgs: [record['name']]);
      await loadLocal();
      await syncToServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = attendanceList.where((item) {
      final groupMatch =
          selectedGroup == 'All' || item['student_group'] == selectedGroup;
      final statusMatch =
          selectedStatus == 'All' || item['status'] == selectedStatus;
      final docstatusZero = (item['docstatus'] ?? 0) == 0;
      final notSigned = (item['signature'] ?? '').isEmpty;
      final studentNameMatch = studentNameFilter.isEmpty ||
          (item['student_name'] ?? '')
              .toLowerCase()
              .contains(studentNameFilter.toLowerCase());
      final studentIdMatch = studentIdFilter.isEmpty ||
          (item['student'] ?? '')
              .toLowerCase()
              .contains(studentIdFilter.toLowerCase());
      final courseMatch = courseFilter.isEmpty ||
          (item['course_schedule'] ?? '')
              .toLowerCase()
              .contains(courseFilter.toLowerCase());
      final customerMatch = customerFilter.isEmpty ||
          (item['customer_name'] ?? '')
              .toLowerCase()
              .contains(customerFilter.toLowerCase());
      final dateMatch =
          dateFilter.isEmpty || (item['date'] ?? '').startsWith(dateFilter);
      return groupMatch &&
          statusMatch &&
          docstatusZero &&
          notSigned &&
          studentNameMatch &&
          studentIdMatch &&
          courseMatch &&
          customerMatch &&
          dateMatch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance List"),
        actions: [
          Icon(
            isOnline ? Icons.wifi : Icons.wifi_off,
            color: isOnline ? Colors.green : Colors.red,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await syncToServer();
              await loadLocal();
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: "View Submitted",
            onPressed: () {
              final submittedList = attendanceList
                  .where((item) => (item['signature'] ?? '').isNotEmpty)
                  .toList();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SubmittedAttendancePage(submittedList: submittedList),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: exportToCSV,
        child: const Icon(Icons.download),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedGroup,
                    isExpanded: true,
                    items: groups
                        .map((group) =>
                            DropdownMenuItem(value: group, child: Text(group)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedGroup = value!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedStatus,
                    isExpanded: true,
                    items: statuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedStatus = value!),
                  ),
                ),
              ],
            ),
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Student Name'),
            onChanged: (value) => setState(() => studentNameFilter = value),
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Student ID'),
            onChanged: (value) => setState(() => studentIdFilter = value),
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Course'),
            onChanged: (value) => setState(() => courseFilter = value),
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Customer'),
            onChanged: (value) => setState(() => customerFilter = value),
          ),
          TextField(
            controller: dateController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Date',
              suffixIcon: dateController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          dateController.clear();
                          dateFilter = '';
                          selectedDate = null;
                        });
                      },
                    )
                  : Icon(Icons.calendar_today),
            ),
            onTap: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  selectedDate = picked;
                  dateController.text =
                      "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                  dateFilter = dateController.text;
                });
              }
            },
          ),
          if (lastSyncTime != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("Last sync: $lastSyncTime"),
            ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (BuildContext context, int index) {
                      final item = filtered[index];
                      final isSynced = item['synced'] == 1;
                      return ListTile(
                        title: Text(
                            "${item['student_name']} (${item['student']})"),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Course: ${item['course_schedule']} | Group: ${item['student_group']} | Date: ${item['date']}\nStatus: ${item['status']} | Customer: ${item['customer_name']}\nSynced: ${isSynced ? 'Yes' : 'No'}",
                            ),
                            if (item['signature'] != '')
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Image.memory(
                                    base64Decode(item['signature']),
                                    height: 50),
                              )
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => captureSignature(item),
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
  final Map<String, dynamic> record;

  const SignaturePad(
      {super.key, required this.controller, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign Attendance")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Name: ${record['student_name']}\n"
              "ID: ${record['student']}\n"
              "Course: ${record['course_schedule']}\n"
              "Group: ${record['student_group']}\n"
              "Date: ${record['date']}\n"
              "Status: ${record['status']}\n"
              "Customer: ${record['customer_name']}",
              style: const TextStyle(fontSize: 16),
            ),
          ),
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

class SubmittedAttendancePage extends StatelessWidget {
  final List<Map<String, dynamic>> submittedList;
  const SubmittedAttendancePage({super.key, required this.submittedList});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Submitted Attendance")),
      body: ListView.builder(
        itemCount: submittedList.length,
        itemBuilder: (context, index) {
          final item = submittedList[index];
          final isSynced = item['synced'] == 1;
          return ListTile(
            title: Text("${item['student_name']} (${item['student']})"),
            subtitle: Text(
              "Course: ${item['course_schedule']} | Group: ${item['student_group']} | Date: ${item['date']}\n"
              "Status: ${item['status']} | Customer: ${item['customer_name']}\n"
              "Synced: ${isSynced ? 'Yes' : 'No'}",
            ),
            trailing: isSynced
                ? const Icon(Icons.cloud_done, color: Colors.green)
                : const Icon(Icons.cloud_upload, color: Colors.orange),
          );
        },
      ),
    );
  }
}
