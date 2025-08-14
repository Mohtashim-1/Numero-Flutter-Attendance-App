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

class EmiratesIDScanPage extends StatefulWidget {
  @override
  _EmiratesIDScanPageState createState() => _EmiratesIDScanPageState();
}

class _EmiratesIDScanPageState extends State<EmiratesIDScanPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isScanning = false;
  Map<String, String> extractedData = {};
  final ImagePicker _picker = ImagePicker();

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

  Future<void> _captureAndScan() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final image = await _controller!.takePicture();
      await _processImage(image.path);
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

  Future<void> _uploadAndScan() async {
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
          await _processImage(image.path);
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

  void _showEmulatorFallbackDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Emulator Detected'),
          content: const Text(
            'Image picker is not available in emulator.\n\n'
            'Please use "Test OCR (Sample Data)" to test the OCR functionality, '
            'or run the app on a physical device for full camera and gallery features.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testOCRWithSampleData();
              },
              child: const Text('Test OCR Now'),
            ),
          ],
        );
      },
    );
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

  Future<void> _processImage(String imagePath) async {
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
          _extractEmiratesIDData(lineText, data);
        }
      }

      print('Full extracted text:');
      print(fullText);
      print('\nExtracted Emirates ID data:');
      data.forEach((key, value) {
        print('$key: $value');
      });

      setState(() {
        extractedData = data;
      });

      textRecognizer.close();

      // Show results dialog
      _showResultsDialog(data, fullText);
    } catch (e) {
      print('Error processing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    }
  }

  void _testOCRWithSampleData() {
    // Test function with sample Emirates ID data
    Map<String, String> testData = {};
    String sampleText = '''
UNITED ARAB EMIRATES
FEDERAL AUTHORITY FOR IDENTITY & CITIZENSHIP
Identity Card

Name: Hamad Salem Naser
الإسم: حمد سالم ناصر
ID Number: 784-1234-1134567-1
رقم الهوية: 784-1234-1134567-1
Date of Birth: 29/09/2004
تاريخ الميلاد: 29/09/2004
Nationality: United Arab Emirates
الجنسية: الإمارات العربية المتحدة
Sex: M
الجنس: ذكر
Issuing Date: 08/08/2021
تاريخ الإصدار: 08/08/2021
Expiry Date: 20/09/2029
تاريخ الإنتهاء: 20/09/2029
''';

    // Process each line
    for (String line in sampleText.split('\n')) {
      _extractEmiratesIDData(line, testData);
    }

    print('=== TEST OCR WITH SAMPLE DATA ===');
    print('Sample text:');
    print(sampleText);
    print('\nExtracted data:');
    testData.forEach((key, value) {
      print('$key: $value');
    });

    setState(() {
      extractedData = testData;
    });

    _showResultsDialog(testData, sampleText);
  }

  void _testMultipleScenarios() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Test Different Emirates ID Scenarios'),
          content: const Text(
            'Choose a test scenario to simulate different Emirates ID formats:',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testScenario1();
              },
              child: const Text('Scenario 1: Standard ID'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testScenario2();
              },
              child: const Text('Scenario 2: Different Name'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testScenario3();
              },
              child: const Text('Scenario 3: Female ID'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _testScenario1() {
    Map<String, String> testData = {};
    String sampleText = '''
UNITED ARAB EMIRATES
FEDERAL AUTHORITY FOR IDENTITY & CITIZENSHIP
Identity Card

Name: Ahmed Mohammed Al Mansouri
الإسم: أحمد محمد المنصوري
ID Number: 784-1985-1234567-8
رقم الهوية: 784-1985-1234567-8
Date of Birth: 15/03/1985
تاريخ الميلاد: 15/03/1985
Nationality: United Arab Emirates
الجنسية: الإمارات العربية المتحدة
Sex: M
الجنس: ذكر
Issuing Date: 12/01/2020
تاريخ الإصدار: 12/01/2020
Expiry Date: 11/01/2030
تاريخ الإنتهاء: 11/01/2030
''';

    _processTestData(testData, sampleText, 'Scenario 1: Standard Male ID');
  }

  void _testScenario2() {
    Map<String, String> testData = {};
    String sampleText = '''
UNITED ARAB EMIRATES
FEDERAL AUTHORITY FOR IDENTITY & CITIZENSHIP
Identity Card

Name: Fatima Zahra Al Qassimi
الإسم: فاطمة الزهراء القاسمي
ID Number: 784-1990-9876543-2
رقم الهوية: 784-1990-9876543-2
Date of Birth: 22/07/1990
تاريخ الميلاد: 22/07/1990
Nationality: United Arab Emirates
الجنسية: الإمارات العربية المتحدة
Sex: F
الجنس: أنثى
Issuing Date: 05/06/2019
تاريخ الإصدار: 05/06/2019
Expiry Date: 04/06/2029
تاريخ الإنتهاء: 04/06/2029
''';

    _processTestData(testData, sampleText, 'Scenario 2: Female ID');
  }

  void _testScenario3() {
    Map<String, String> testData = {};
    String sampleText = '''
UNITED ARAB EMIRATES
FEDERAL AUTHORITY FOR IDENTITY & CITIZENSHIP
Identity Card

Name: Omar Khalid Al Falasi
الإسم: عمر خالد الفلاسي
ID Number: 784-1978-5555555-5
رقم الهوية: 784-1978-5555555-5
Date of Birth: 08/12/1978
تاريخ الميلاد: 08/12/1978
Nationality: United Arab Emirates
الجنسية: الإمارات العربية المتحدة
Sex: M
الجنس: ذكر
Issuing Date: 20/03/2018
تاريخ الإصدار: 20/03/2018
Expiry Date: 19/03/2028
تاريخ الإنتهاء: 19/03/2028
''';

    _processTestData(testData, sampleText, 'Scenario 3: Different Male ID');
  }

  void _processTestData(
      Map<String, String> testData, String sampleText, String scenarioName) {
    // Process each line
    for (String line in sampleText.split('\n')) {
      _extractEmiratesIDData(line, testData);
    }

    print('=== $scenarioName ===');
    print('Sample text:');
    print(sampleText);
    print('\nExtracted data:');
    testData.forEach((key, value) {
      print('$key: $value');
    });

    setState(() {
      extractedData = testData;
    });

    _showResultsDialog(testData, sampleText);
  }

  Future<void> _uploadToFrappe(Map<String, String> data) async {
    try {
      setState(() {
        _isScanning = true;
      });

      // Prepare the data for Frappe
      String firstName = '';
      String lastName = '';
      String nationality = '';
      String gender = '';
      String eidNo = '';

      // Extract data from the scanned Emirates ID
      if (data.containsKey('Name')) {
        String fullName = data['Name']!;
        List<String> nameParts = fullName.split(' ');
        if (nameParts.length >= 2) {
          firstName = nameParts[0];
          lastName = nameParts.sublist(1).join(' ');
        } else {
          firstName = fullName;
        }
      }

      if (data.containsKey('Nationality')) {
        nationality = data['Nationality']!;
      }

      if (data.containsKey('Sex')) {
        gender = data['Sex']!;
      }

      if (data.containsKey('ID Number')) {
        eidNo = data['ID Number']!;
      }

      // Create the request payload
      Map<String, dynamic> payload = {
        'doctype': 'Student',
        'first_name': firstName,
        'last_name': lastName,
        'nationality': nationality,
        'gender': gender,
        'custom_eid_no': eidNo,
      };

      print('Uploading to Frappe with payload: $payload');

      // Make the API call to Frappe
      final response = await http.post(
        Uri.parse('$baseUrl/api/resource/Student'),
        headers: {
          'Authorization': apiToken,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      print('Frappe response status: ${response.statusCode}');
      print('Frappe response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully uploaded to Frappe! Student ID: ${responseData['data']['name'] ?? 'N/A'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(
            'Failed to upload to Frappe: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error uploading to Frappe: $e');
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

  void _extractEmiratesIDData(String text, Map<String, String> data) {
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
    if (text.contains('Name:') || text.contains('الإسم:')) {
      String name =
          text.replaceAll('Name:', '').replaceAll('الإسم:', '').trim();
      if (name.isNotEmpty) {
        data['Name'] = name;
      }
    }

    // Nationality patterns
    if (text.contains('Nationality:') || text.contains('الجنسية:')) {
      String nationality =
          text.replaceAll('Nationality:', '').replaceAll('الجنسية:', '').trim();
      if (nationality.isNotEmpty) {
        data['Nationality'] = nationality;
      }
    }

    // Sex/Gender patterns
    if (text.contains('Sex:') || text.contains('الجنس')) {
      String sex = text.replaceAll('Sex:', '').replaceAll('الجنس', '').trim();
      if (sex.isNotEmpty) {
        data['Sex'] = sex;
      }
    }

    // UAE specific patterns
    if (text.contains('UNITED ARAB EMIRATES') ||
        text.contains('الإمارات العربية المتحدة')) {
      data['Country'] = 'United Arab Emirates';
    }
  }

  void _showResultsDialog(Map<String, String> data, String fullText) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Emirates ID Scan Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Extracted Information:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...data.entries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${entry.key}: ${entry.value}'),
                    )),
                const SizedBox(height: 20),
                const Text('Full Text:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(fullText, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Emirates ID Scanner')),
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
        title: const Text('Emirates ID Scanner'),
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
                      '1. Position the Emirates ID card within the camera frame\n'
                      '2. Ensure good lighting and clear text\n'
                      '3. Tap "Scan ID" to capture with camera OR "Upload Image" to select from gallery\n'
                      '4. The app will extract and display the information\n'
                      '5. View results to see extracted data and full text',
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
          Expanded(
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
                                'Camera not available\nUse Upload Image instead',
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
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isScanning ||
                                _controller == null ||
                                !_controller!.value.isInitialized)
                            ? null
                            : _captureAndScan,
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
                                : 'Scan ID'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _uploadAndScan,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label:
                            Text(_isScanning ? 'Uploading...' : 'Upload Image'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (extractedData.isNotEmpty)
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showResultsDialog(extractedData, ''),
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Results'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _uploadToFrappe(extractedData),
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Upload to Frappe'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
