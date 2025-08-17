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
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String baseUrl = 'https://numerouno-uat.u.frappe.cloud';
const String apiToken = 'token 8a893b8d854cbe5:ea4c207706bd484';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'numero UNO',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false, // Remove debug banner
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
      appBar: AppBar(
        title: const Text('numero UNO'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight -
                48, // 48 for padding
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // NFC Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: SvgPicture.asset(
                  'assets/images/nfc_logo.svg',
                  width: 120,
                  height: 120,
                ),
              ),

              // Login Form
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
        'Authorization': apiToken,
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
              'Authorization': apiToken,
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              "filename": "${record['name']}.png",
              "filedata": record['signature'],
              "is_private": 0,
              "doctype": "Student Attendance",
              "docname": record['name'],
              "fieldname": "custom_student_signature1",
              "decode_base64": true
            }));

        if (uploadResponse.statusCode == 200) {
          final uploaded = jsonDecode(uploadResponse.body);
          final fileUrl = uploaded['message']['file_url'];

          final response = await http.put(
            Uri.parse(
                '$baseUrl/api/resource/Student%20Attendance/${record['name']}'),
            headers: {
              'Authorization': apiToken,
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
        title: Row(
          children: [
            const Icon(Icons.nfc, size: 28),
            const SizedBox(width: 10),
            const Text("Attendance List"),
          ],
        ),
        centerTitle: true,
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
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: "Scan Emirates ID",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EmiratesIDScanPage(),
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
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.nfc, size: 24),
            const SizedBox(width: 8),
            const Text("Sign Attendance"),
          ],
        ),
        centerTitle: true,
      ),
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
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.nfc, size: 24),
            const SizedBox(width: 8),
            const Text("Submitted Attendance"),
          ],
        ),
        centerTitle: true,
      ),
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

class EmiratesIDScanPage extends StatefulWidget {
  @override
  _EmiratesIDScanPageState createState() => _EmiratesIDScanPageState();
}

class _EmiratesIDScanPageState extends State<EmiratesIDScanPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isScanning = false;
  Map<String, String> extractedDataFront = {};
  Map<String, String> extractedDataBack = {};
  final ImagePicker _picker = ImagePicker();
  String? frontImagePath;
  String? backImagePath;

  // Controllers for editable fields
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController eidNoController = TextEditingController();
  final TextEditingController dobController = TextEditingController();
  final TextEditingController nationalityController = TextEditingController();
  final TextEditingController genderController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController cardNumberController = TextEditingController();
  final TextEditingController occupationController = TextEditingController();
  final TextEditingController employerController = TextEditingController();
  final TextEditingController issuingPlaceController = TextEditingController();
  final TextEditingController bloodTypeController = TextEditingController();
  final TextEditingController emergencyContactController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Check if permission_handler is available
      try {
        final status = await Permission.camera.request();
        if (status != PermissionStatus.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required')),
          );
          return;
        }
      } catch (e) {
        print(
            'Permission handler not available, proceeding without permission check: $e');
        // Continue without permission check for emulator testing
      }

      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        setState(() {
          _isInitialized = true;
        });
      } else {
        throw Exception('No cameras available');
      }
    } catch (e) {
      print('Error initializing camera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing camera: $e')),
      );
    }
  }

  Future<void> _captureAndScan(String side) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final image = await _controller!.takePicture();
      if (side == 'front') {
        setState(() {
          frontImagePath = image.path;
        });
        await _processImage(image.path, 'front');
      } else {
        setState(() {
          backImagePath = image.path;
        });
        await _processImage(image.path, 'back');
      }
    } catch (e) {
      print('Error capturing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing image: $e')),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _uploadAndScan(String side) async {
    try {
      setState(() {
        _isScanning = true;
      });

      // Simple permission request for Redmi 10
      bool hasPermission = false;

      try {
        // Try multiple permission types for better compatibility
        var photosStatus = await Permission.photos.status;
        var storageStatus = await Permission.storage.status;
        var mediaLibraryStatus = await Permission.mediaLibrary.status;

        print(
            'Permission status - Photos: $photosStatus, Storage: $storageStatus, Media: $mediaLibraryStatus');

        if (photosStatus.isGranted ||
            storageStatus.isGranted ||
            mediaLibraryStatus.isGranted) {
          hasPermission = true;
        } else {
          // Request permissions one by one
          photosStatus = await Permission.photos.request();
          if (photosStatus.isGranted) {
            hasPermission = true;
          } else {
            storageStatus = await Permission.storage.request();
            if (storageStatus.isGranted) {
              hasPermission = true;
            } else {
              mediaLibraryStatus = await Permission.mediaLibrary.request();
              hasPermission = mediaLibraryStatus.isGranted;
            }
          }
        }
      } catch (e) {
        print('Permission request error: $e');
        // Fallback to basic storage permission
        try {
          final status = await Permission.storage.request();
          hasPermission = status.isGranted;
        } catch (e2) {
          print('Fallback permission request failed: $e2');
        }
      }

      if (!hasPermission) {
        _showPermissionDialog();
        return;
      }

      try {
        final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          if (side == 'front') {
            setState(() {
              frontImagePath = image.path;
            });
            await _processImage(image.path, 'front');
          } else {
            setState(() {
              backImagePath = image.path;
            });
            await _processImage(image.path, 'back');
          }
        }
      } catch (e) {
        print('Image picker error: $e');
        if (e.toString().contains('permission')) {
          _showPermissionDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error accessing gallery: $e')),
          );
        }
      }
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'Storage permission is required to access your gallery and upload images.\n\n'
            'Please grant permission in the next dialog, or go to Settings to enable it manually.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processImage(String imagePath, String side) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();

      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      Map<String, String> data = {};
      String fullText = '';

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String lineText = line.text;
          fullText += lineText + '\n';

          // Extract Emirates ID information based on common patterns
          _extractEmiratesIDData(lineText, data, side);
        }
      }

      print('Full extracted text for $side:');
      print(fullText);
      print('\nExtracted Emirates ID data for $side:');
      data.forEach((key, value) {
        print('$key: $value');
      });

      setState(() {
        if (side == 'front') {
          extractedDataFront = data;
          // Update the text controllers with extracted data
          if (data.containsKey('Name')) {
            String fullName = data['Name']!;
            List<String> nameParts = fullName.split(' ');
            if (nameParts.isNotEmpty) {
              firstNameController.text = nameParts.first;
              if (nameParts.length > 1) {
                lastNameController.text = nameParts.sublist(1).join(' ');
              }
            }
          }
          if (data.containsKey('ID Number')) {
            eidNoController.text = data['ID Number']!;
          }
          if (data.containsKey('Date of Birth')) {
            dobController.text = data['Date of Birth']!;
          }
          if (data.containsKey('Nationality')) {
            nationalityController.text = data['Nationality']!;
          }
          if (data.containsKey('Sex')) {
            genderController.text = data['Sex']!;
          }
        } else {
          extractedDataBack = data;
          // Update the text controllers with extracted data
          if (data.containsKey('Address')) {
            addressController.text = data['Address']!;
          }
          if (data.containsKey('Card Number')) {
            cardNumberController.text = data['Card Number']!;
          }
          if (data.containsKey('Occupation')) {
            occupationController.text = data['Occupation']!;
          }
          if (data.containsKey('Employer')) {
            employerController.text = data['Employer']!;
          }
          if (data.containsKey('Issuing Place')) {
            issuingPlaceController.text = data['Issuing Place']!;
          }
          if (data.containsKey('Blood Type')) {
            bloodTypeController.text = data['Blood Type']!;
          }
          if (data.containsKey('Emergency Contact')) {
            emergencyContactController.text = data['Emergency Contact']!;
          }
        }

        // Show data preview dialog after both sides are scanned
        if (extractedDataFront.isNotEmpty && extractedDataBack.isNotEmpty) {
          _showDataPreviewDialog();
        }
      });

      textRecognizer.close();
    } catch (e) {
      print('Error processing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    }
  }

  Future<void> _uploadToFrappe() async {
    try {
      setState(() {
        _isScanning = true;
      });

      // Get data from the editable fields
      String firstName = firstNameController.text.trim();
      String lastName = lastNameController.text.trim();
      String nationality = nationalityController.text.trim();
      String gender = genderController.text.trim();
      String eidNo = eidNoController.text.trim();
      String address = addressController.text.trim();
      String cardNumber = cardNumberController.text.trim();
      String occupation = occupationController.text.trim();
      String employer = employerController.text.trim();
      String issuingPlace = issuingPlaceController.text.trim();
      String bloodType = bloodTypeController.text.trim();
      String emergencyContact = emergencyContactController.text.trim();

      // Convert gender format from Emirates ID (M/F) to Frappe format (Male/Female)
      String frappeGender = gender;
      if (gender.toUpperCase() == 'M') {
        frappeGender = 'Male';
      } else if (gender.toUpperCase() == 'F') {
        frappeGender = 'Female';
      }

      // Handle employer/customer validation and creation
      String customerName = '';
      if (employer.isNotEmpty) {
        try {
          // First, test if user can access Customer doctype at all
          print('🔍 Testing Customer doctype access...');
          final testAccessResponse = await http.get(
            Uri.parse('$baseUrl/api/resource/Customer?limit_page_length=1'),
            headers: {
              'Authorization': apiToken,
              'Content-Type': 'application/json',
            },
          );

          print(
              '📊 Customer access test status: ${testAccessResponse.statusCode}');
          if (testAccessResponse.statusCode != 200) {
            print(
                '❌ User cannot access Customer doctype. Status: ${testAccessResponse.statusCode}');
            print('📄 Response: ${testAccessResponse.body}');
          } else {
            print('✅ User can access Customer doctype');
          }

          // Then, check if customer exists
          final customerCheckResponse = await http.get(
            Uri.parse(
                '$baseUrl/api/resource/Customer?filters=[["customer_name","=","$employer"]]'),
            headers: {
              'Authorization': apiToken,
              'Content-Type': 'application/json',
            },
          );

          if (customerCheckResponse.statusCode == 200) {
            final customerData = jsonDecode(customerCheckResponse.body);
            if (customerData['data'] != null &&
                customerData['data'].isNotEmpty) {
              // Customer exists, use the existing customer name
              customerName = customerData['data'][0]['name'];
              print('Found existing customer: $customerName');
            } else {
              // Customer doesn't exist, try to create new customer
              print('Customer not found, attempting to create: $employer');

              // Try multiple approaches to create customer
              bool customerCreated = false;

              // Approach 1: Direct Customer creation (minimal fields)
              try {
                print(
                    '🔍 Attempting to create customer with minimal fields: $employer');
                final createCustomerResponse = await http.post(
                  Uri.parse('$baseUrl/api/resource/Customer'),
                  headers: {
                    'Authorization': apiToken,
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'doctype': 'Customer',
                    'customer_name': employer,
                  }),
                );

                print(
                    '📊 Customer creation response status: ${createCustomerResponse.statusCode}');
                print(
                    '📄 Customer creation response body: ${createCustomerResponse.body}');

                if (createCustomerResponse.statusCode == 200 ||
                    createCustomerResponse.statusCode == 201) {
                  final newCustomerData =
                      jsonDecode(createCustomerResponse.body);
                  customerName = newCustomerData['data']['name'];
                  print('✅ Successfully created new customer: $customerName');
                  customerCreated = true;
                } else {
                  print(
                      '❌ Failed to create customer: ${createCustomerResponse.body}');

                  // Try to parse error details for better debugging
                  try {
                    final errorData = jsonDecode(createCustomerResponse.body);
                    if (errorData.containsKey('_server_messages')) {
                      print(
                          '🔍 Server messages: ${errorData['_server_messages']}');
                    }
                    if (errorData.containsKey('_error_message')) {
                      print('🔍 Error message: ${errorData['_error_message']}');
                    }
                    if (errorData.containsKey('exc_type')) {
                      print('🔍 Exception type: ${errorData['exc_type']}');
                    }
                  } catch (parseError) {
                    print('⚠️ Could not parse error response: $parseError');
                  }
                }
              } catch (e) {
                print('💥 Error in direct customer creation: $e');
              }

              // Approach 2: Try with Company type if first fails
              if (!customerCreated) {
                try {
                  print(
                      '🔍 Attempting to create customer with Company type: $employer');
                  final createCustomerResponse2 = await http.post(
                    Uri.parse('$baseUrl/api/resource/Customer'),
                    headers: {
                      'Authorization': apiToken,
                      'Content-Type': 'application/json',
                    },
                    body: jsonEncode({
                      'doctype': 'Customer',
                      'customer_name': employer,
                      'customer_type': 'Company',
                    }),
                  );

                  print(
                      '📊 Company customer creation status: ${createCustomerResponse2.statusCode}');
                  print(
                      '📄 Company customer creation response: ${createCustomerResponse2.body}');

                  if (createCustomerResponse2.statusCode == 200 ||
                      createCustomerResponse2.statusCode == 201) {
                    final newCustomerData =
                        jsonDecode(createCustomerResponse2.body);
                    customerName = newCustomerData['data']['name'];
                    print(
                        '✅ Successfully created new customer (Company): $customerName');
                    customerCreated = true;
                  } else {
                    print(
                        '❌ Failed to create customer (Company): ${createCustomerResponse2.body}');
                  }
                } catch (e) {
                  print('💥 Error in company customer creation: $e');
                }
              }

              // Approach 3: Try using a different API endpoint (if available)
              if (!customerCreated) {
                try {
                  print(
                      '🔍 Attempting alternative customer creation method...');
                  // Try using the method API instead of resource API
                  final createCustomerResponse3 = await http.post(
                    Uri.parse('$baseUrl/api/method/frappe.client.insert'),
                    headers: {
                      'Authorization': apiToken,
                      'Content-Type': 'application/json',
                    },
                    body: jsonEncode({
                      'doc': {
                        'doctype': 'Customer',
                        'customer_name': employer,
                      }
                    }),
                  );

                  print(
                      '📊 Alternative method status: ${createCustomerResponse3.statusCode}');
                  print(
                      '📄 Alternative method response: ${createCustomerResponse3.body}');

                  if (createCustomerResponse3.statusCode == 200) {
                    final newCustomerData =
                        jsonDecode(createCustomerResponse3.body);
                    customerName = newCustomerData['data']['name'];
                    print(
                        '✅ Successfully created customer via alternative method: $customerName');
                    customerCreated = true;
                  } else {
                    print(
                        '❌ Alternative method failed: ${createCustomerResponse3.body}');
                  }
                } catch (e) {
                  print('💥 Error in alternative customer creation: $e');
                }
              }

              // If both approaches failed, show warning
              if (!customerCreated) {
                // Show user-friendly message about customer creation failure
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '⚠️ Note: Could not create customer for employer "$employer". Student will be created without customer link.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
                // Continue without customer if creation fails
              }
            }
          } else {
            print(
                'Failed to check customer existence: ${customerCheckResponse.body}');
          }
        } catch (e) {
          print('Error handling customer: $e');
          // Show user-friendly error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '⚠️ Note: Error checking customer for employer "$employer". Student will be created without customer link.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          // Continue without customer if there's an error
        }
      }

      // Validate required fields
      if (firstName.isEmpty || lastName.isEmpty || eidNo.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Please fill in First Name, Last Name, and ID Number'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Create the request payload
      Map<String, dynamic> payload = {
        'doctype': 'Student',
        'first_name': firstName,
        'last_name': lastName,
        'nationality': nationality,
        'gender': frappeGender,
        'custom_eid_no': eidNo,
        'custom_address': address,
        'custom_card_number': cardNumber,
        'custom_occupation': occupation,
        'custom_employer': employer,
        'custom_issuing_place': issuingPlace,
        'custom_blood_type': bloodType,
        'custom_emergency_contact': emergencyContact,
      };

      // Add customer_name if available
      if (customerName.isNotEmpty) {
        payload['customer_name'] = customerName;
      } else if (employer.isNotEmpty) {
        // If customer creation failed, store employer name in a custom field
        payload['custom_employer_name'] = employer;
      }

      print('Uploading to Frappe with payload: $payload');

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Uploading to Frappe...'),
            content: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Please wait...'),
              ],
            ),
          );
        },
      );

      // Make the API call to Frappe
      final response = await http.post(
        Uri.parse('$baseUrl/api/resource/Student'),
        headers: {
          'Authorization': apiToken,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      // Close loading dialog
      Navigator.of(context).pop();

      print('Frappe response status: ${response.statusCode}');
      print('Frappe response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);

        // Show success dialog with details
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text('✅ Upload Successful!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Student ID: ${responseData['data']['name'] ?? 'N/A'}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text('Name: $firstName $lastName'),
                        Text('ID Number: $eidNo'),
                        Text('Nationality: $nationality'),
                        Text('Gender: $frappeGender'),
                        if (address.isNotEmpty) Text('Address: $address'),
                        if (cardNumber.isNotEmpty)
                          Text('Card Number: $cardNumber'),
                        if (occupation.isNotEmpty)
                          Text('Occupation: $occupation'),
                        if (employer.isNotEmpty) Text('Employer: $employer'),
                        if (customerName.isNotEmpty)
                          Text('Customer: $customerName',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold))
                        else if (employer.isNotEmpty)
                          Text('Customer: Not linked (permission issue)',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontStyle: FontStyle.italic)),
                        if (employer.isNotEmpty && customerName.isEmpty)
                          Text('Employer stored in custom field',
                              style: TextStyle(
                                  color: Colors.blue,
                                  fontStyle: FontStyle.italic)),
                        if (issuingPlace.isNotEmpty)
                          Text('Issuing Place: $issuingPlace'),
                        if (bloodType.isNotEmpty)
                          Text('Blood Type: $bloodType'),
                        if (emergencyContact.isNotEmpty)
                          Text('Emergency Contact: $emergencyContact'),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Data has been successfully uploaded to Frappe system!',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Clear the form after successful upload
                    _clearForm();
                    // Show a snackbar confirmation
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Form cleared. Ready for next scan!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Continue'),
                ),
              ],
            );
          },
        );
      } else {
        throw Exception(
            'Failed to upload to Frappe: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error uploading to Frappe: $e');

      // Close loading dialog if it's still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading to Frappe: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showDataPreviewDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                '📋 Extracted Emirates ID Data',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              content: Container(
                width: double.maxFinite,
                height: 400,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Please review and edit the extracted data:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _buildDialogDataField('First Name', firstNameController),
                      _buildDialogDataField('Last Name', lastNameController),
                      _buildDialogDataField('ID Number', eidNoController),
                      _buildDialogDataField('Date of Birth', dobController),
                      _buildDialogDataField(
                          'Nationality', nationalityController),
                      _buildDialogDataField('Gender', genderController),
                      _buildDialogDataField('Address', addressController),
                      _buildDialogDataField(
                          'Card Number', cardNumberController),
                      _buildDialogDataField('Occupation', occupationController),
                      _buildDialogDataField('Employer', employerController),
                      _buildDialogDataField(
                          'Issuing Place', issuingPlaceController),
                      _buildDialogDataField('Blood Type', bloodTypeController),
                      _buildDialogDataField(
                          'Emergency Contact', emergencyContactController),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearForm();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _uploadToFrappe();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Upload to Frappe'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogDataField(String label, TextEditingController controller) {
    String? helperText;

    // Add helper text for gender field to show conversion
    if (label == 'Gender') {
      String genderValue = controller.text.trim().toUpperCase();
      if (genderValue == 'M') {
        helperText = 'Will be converted to "Male" in Frappe';
      } else if (genderValue == 'F') {
        helperText = 'Will be converted to "Female" in Frappe';
      }
    }

    // Add helper text for employer field to show customer creation
    if (label == 'Employer') {
      String employerValue = controller.text.trim();
      if (employerValue.isNotEmpty) {
        helperText = 'Will create/link customer in Frappe';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          helperText: helperText,
          helperStyle: TextStyle(
            color: Colors.blue.shade600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _clearForm() {
    firstNameController.clear();
    lastNameController.clear();
    eidNoController.clear();
    dobController.clear();
    nationalityController.clear();
    genderController.clear();
    addressController.clear();
    cardNumberController.clear();
    occupationController.clear();
    employerController.clear();
    issuingPlaceController.clear();
    bloodTypeController.clear();
    emergencyContactController.clear();
    setState(() {
      extractedDataFront.clear();
      extractedDataBack.clear();
      frontImagePath = null;
      backImagePath = null;
    });
  }

  void _extractEmiratesIDData(
      String text, Map<String, String> data, String side) {
    if (side == 'front') {
      // ID Number pattern: 784-XXXX-XXXXXXX-X
      RegExp idPattern = RegExp(r'784-\d{4}-\d{7}-\d');
      if (idPattern.hasMatch(text)) {
        data['ID Number'] = idPattern.firstMatch(text)!.group(0)!;
      }

      // Date patterns (DD/MM/YYYY or YYYY-MM-DD)
      RegExp datePattern = RegExp(r'\d{2}/\d{2}/\d{4}|\d{4}-\d{2}-\d{2}');
      if (datePattern.hasMatch(text)) {
        if (text.toLowerCase().contains('birth') ||
            text.toLowerCase().contains('ميلاد')) {
          data['Date of Birth'] = datePattern.firstMatch(text)!.group(0)!;
        } else if (text.toLowerCase().contains('issue') ||
            text.toLowerCase().contains('إصدار')) {
          data['Issuing Date'] = datePattern.firstMatch(text)!.group(0)!;
        } else if (text.toLowerCase().contains('expiry') ||
            text.toLowerCase().contains('انتهاء')) {
          data['Expiry Date'] = datePattern.firstMatch(text)!.group(0)!;
        }
      }

      // Name patterns (English and Arabic)
      if (text.contains('Name:') ||
          text.contains('الإسم:') ||
          text.contains('الاسم:')) {
        String name = text
            .replaceAll('Name:', '')
            .replaceAll('الإسم:', '')
            .replaceAll('الاسم:', '')
            .trim();
        if (name.isNotEmpty) {
          data['Name'] = name;
        }
      } else if (text.contains('Name') &&
          !text.contains('ID Number') &&
          text.length > 5) {
        // Fallback: if text contains "Name" but not "ID Number" and is long enough
        String name = text.replaceAll('Name', '').trim();
        if (name.isNotEmpty && name.length > 2) {
          data['Name'] = name;
        }
      }

      // Nationality patterns
      if (text.contains('Nationality:') || text.contains('الجنسية:')) {
        String nationality = text
            .replaceAll('Nationality:', '')
            .replaceAll('الجنسية:', '')
            .trim();
        if (nationality.isNotEmpty) {
          data['Nationality'] = nationality;
        }
      } else if (text.contains('Nationality') && text.length > 10) {
        // Fallback: if text contains "Nationality" and is long enough
        String nationality = text.replaceAll('Nationality', '').trim();
        if (nationality.isNotEmpty && nationality.length > 2) {
          data['Nationality'] = nationality;
        }
      }

      // Sex/Gender patterns
      if (text.contains('Sex:') ||
          text.contains('الجنس') ||
          text.contains('M') ||
          text.contains('F')) {
        if (text.contains('Sex:')) {
          String sex = text.replaceAll('Sex:', '').trim();
          if (sex.isNotEmpty) {
            data['Sex'] = sex;
          }
        } else if (text.contains('M') && !text.contains('MRZ')) {
          data['Sex'] = 'M';
        } else if (text.contains('F') && !text.contains('MRZ')) {
          data['Sex'] = 'F';
        }
      }

      // UAE specific patterns
      if (text.contains('UNITED ARAB EMIRATES') ||
          text.contains('الإمارات العربية المتحدة')) {
        data['Country'] = 'United Arab Emirates';
      }
    } else if (side == 'back') {
      // Card Number patterns
      RegExp cardNumberPattern = RegExp(r'\d{9}');
      if (cardNumberPattern.hasMatch(text) && text.contains('Card Number') ||
          text.contains('رقم البطاقة')) {
        data['Card Number'] = cardNumberPattern.firstMatch(text)!.group(0)!;
      }

      // Occupation patterns
      if (text.contains('Occupation:') || text.contains('المهنة:')) {
        String occupation =
            text.replaceAll('Occupation:', '').replaceAll('المهنة:', '').trim();
        if (occupation.isNotEmpty) {
          data['Occupation'] = occupation;
        }
      }

      // Employer patterns
      if (text.contains('Employer:') || text.contains('صاحب العمل:')) {
        String employer = text
            .replaceAll('Employer:', '')
            .replaceAll('صاحب العمل:', '')
            .trim();
        if (employer.isNotEmpty) {
          data['Employer'] = employer;
        }
      }

      // Issuing Place patterns
      if (text.contains('Issuing Place:') || text.contains('مكان الإصدار:')) {
        String issuingPlace = text
            .replaceAll('Issuing Place:', '')
            .replaceAll('مكان الإصدار:', '')
            .trim();
        if (issuingPlace.isNotEmpty) {
          data['Issuing Place'] = issuingPlace;
        }
      }

      // Address patterns
      if (text.contains('Address:') || text.contains('العنوان:')) {
        String address =
            text.replaceAll('Address:', '').replaceAll('العنوان:', '').trim();
        if (address.isNotEmpty) {
          data['Address'] = address;
        }
      }

      // Blood Type patterns
      if (text.contains('Blood Type:') || text.contains('فصيلة الدم:')) {
        String bloodType = text
            .replaceAll('Blood Type:', '')
            .replaceAll('فصيلة الدم:', '')
            .trim();
        if (bloodType.isNotEmpty) {
          data['Blood Type'] = bloodType;
        }
      }

      // Emergency Contact patterns
      if (text.contains('Emergency Contact:') ||
          text.contains('رقم الطوارئ:')) {
        String emergencyContact = text
            .replaceAll('Emergency Contact:', '')
            .replaceAll('رقم الطوارئ:', '')
            .trim();
        if (emergencyContact.isNotEmpty) {
          data['Emergency Contact'] = emergencyContact;
        }
      }

      // Phone number patterns
      RegExp phonePattern = RegExp(r'\+971-\d{2}-\d{7}');
      if (phonePattern.hasMatch(text) &&
          !data.containsKey('Emergency Contact')) {
        data['Emergency Contact'] = phonePattern.firstMatch(text)!.group(0)!;
      }

      // QR Code patterns
      if (text.contains('QR Code:') || text.contains('[QR Code Data]')) {
        data['QR Code'] = 'Detected';
      }
    }
  }

  Widget _buildDataField(String label, String field, String initialValue) {
    TextEditingController controller;
    switch (field) {
      case 'firstName':
        controller = firstNameController;
        break;
      case 'lastName':
        controller = lastNameController;
        break;
      case 'eidNo':
        controller = eidNoController;
        break;
      case 'dob':
        controller = dobController;
        break;
      case 'nationality':
        controller = nationalityController;
        break;
      case 'gender':
        controller = genderController;
        break;
      case 'address':
        controller = addressController;
        break;
      case 'cardNumber':
        controller = cardNumberController;
        break;
      case 'occupation':
        controller = occupationController;
        break;
      case 'employer':
        controller = employerController;
        break;
      case 'issuingPlace':
        controller = issuingPlaceController;
        break;
      case 'bloodType':
        controller = bloodTypeController;
        break;
      case 'emergencyContact':
        controller = emergencyContactController;
        break;
      default:
        controller = TextEditingController();
    }

    // Set initial value if controller is empty
    if (controller.text.isEmpty && initialValue.isNotEmpty) {
      controller.text = initialValue;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    eidNoController.dispose();
    dobController.dispose();
    nationalityController.dispose();
    genderController.dispose();
    addressController.dispose();
    cardNumberController.dispose();
    occupationController.dispose();
    employerController.dispose();
    issuingPlaceController.dispose();
    bloodTypeController.dispose();
    emergencyContactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Numero UNO')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Initializing camera...'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  // Fallback: allow upload even if camera fails
                  setState(() {
                    _isInitialized = true;
                  });
                },
                child: const Text('Skip Camera (Upload Only)'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.nfc, size: 28),
            const SizedBox(width: 10),
            const Text('numero UNO'),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('How to Use'),
                    content: const Text(
                      '1. Scan or upload both front and back sides of the Emirates ID\n'
                      '2. Ensure good lighting and clear text\n'
                      '3. Use "Scan Front" and "Scan Back" buttons for camera capture\n'
                      '4. Use "Upload Front" and "Upload Back" to select from gallery\n'
                      '5. View results to see extracted data from both sides\n'
                      '6. Upload complete data to Frappe system',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview section
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _controller != null && _controller!.value.isInitialized
                    ? CameraPreview(_controller!)
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Camera not available\nUse Upload buttons instead',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Front and Back image previews
          Container(
            height: 120,
            child: Row(
              children: [
                // Front side preview
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: frontImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(frontImagePath!),
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.credit_card, color: Colors.green),
                                SizedBox(height: 8),
                                Text('Front Side',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                ),
                // Back side preview
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: backImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(backImagePath!),
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.credit_card, color: Colors.orange),
                                SizedBox(height: 8),
                                Text('Back Side',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Front side controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isScanning ||
                                _controller == null ||
                                !_controller!.value.isInitialized)
                            ? null
                            : () => _captureAndScan('front'),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(_isScanning
                            ? 'Scanning...'
                            : (_controller == null ||
                                    !_controller!.value.isInitialized)
                                ? 'Camera Unavailable'
                                : 'Scan Front'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isScanning ? null : () => _uploadAndScan('front'),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label:
                            Text(_isScanning ? 'Uploading...' : 'Upload Front'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Back side controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isScanning ||
                                _controller == null ||
                                !_controller!.value.isInitialized)
                            ? null
                            : () => _captureAndScan('back'),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(_isScanning
                            ? 'Scanning...'
                            : (_controller == null ||
                                    !_controller!.value.isInitialized)
                                ? 'Camera Unavailable'
                                : 'Scan Back'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isScanning ? null : () => _uploadAndScan('back'),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label:
                            Text(_isScanning ? 'Uploading...' : 'Upload Back'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Review Data button
                if (extractedDataFront.isNotEmpty ||
                    extractedDataBack.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showDataPreviewDialog(),
                      icon: const Icon(Icons.edit),
                      label: const Text('Review & Edit Extracted Data'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                      ),
                    ),
                  ),

                if (extractedDataFront.isNotEmpty ||
                    extractedDataBack.isNotEmpty)
                  const SizedBox(height: 12),

                // Upload to Frappe button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (firstNameController.text.isNotEmpty &&
                            lastNameController.text.isNotEmpty &&
                            eidNoController.text.isNotEmpty)
                        ? () => _uploadToFrappe()
                        : null,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Upload Complete Data to Frappe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
