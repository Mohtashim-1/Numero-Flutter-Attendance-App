import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import '../models/attendance.dart';
import '../models/student.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_button.dart';
import '../widgets/app_drawer.dart';
import 'add_student_page.dart';

class AttendanceListPage extends StatefulWidget {
  const AttendanceListPage({super.key});

  @override
  State<AttendanceListPage> createState() => _AttendanceListPageState();
}

class _AttendanceListPageState extends State<AttendanceListPage> {
  List<Attendance> attendanceList = [];
  final _databaseService = DatabaseService();
  final _apiService = ApiService();
  
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
    dateController.dispose();
    super.dispose();
  }

  Future<void> initApp() async {
    await checkConnectivity();
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("First launch requires internet to fetch data.")),
      );
      return;
    }
    await loadLocal();
    await syncToServer();
  }

  Future<void> checkConnectivity() async {
    final connectivity = await Connectivity().checkConnectivity();
    setState(() {
      isOnline = connectivity != ConnectivityResult.none;
    });
  }

  Future<void> loadLocal() async {
    try {
      final attendance = await _databaseService.getAllAttendance();
      print('=== LOADING ATTENDANCE ===');
      print('Found ${attendance.length} attendance records');
      for (var att in attendance) {
        print('Attendance: ${att.studentName} - ${att.status} - ${att.createdAt}');
      }
      
      setState(() {
        attendanceList = attendance;
      });
    } catch (e) {
      print('Error loading attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading local data: $e')),
      );
    }
  }

  Future<void> syncToServer() async {
    if (!isOnline) return;

    try {
      final unsyncedAttendance = await _databaseService.getUnsyncedAttendance();
      
      for (final attendance in unsyncedAttendance) {
        final result = await _apiService.createAttendance(attendance);
        if (result['success']) {
          await _databaseService.markAttendanceAsSynced(attendance.id!);
        }
      }

      setState(() {
        lastSyncTime = DateTime.now().toString();
      });
    } catch (e) {
      print('Sync error: $e');
    }
  }

  Future<void> exportToCSV() async {
    try {
      final List<List<dynamic>> csvData = [
        ['Student Name', 'EID No', 'Status', 'Date', 'Time', 'Notes']
      ];

      for (final attendance in attendanceList) {
        csvData.add([
          attendance.studentName,
          attendance.eidNo,
          attendance.status,
          attendance.createdAt.toIso8601String().split('T')[0],
          attendance.createdAt.toIso8601String().split('T')[1].split('.')[0],
          attendance.notes ?? '',
        ]);
      }

      final String csv = const ListToCsvConverter().convert(csvData);
      final Directory directory = await getApplicationDocumentsDirectory();
      final String filePath = path.join(directory.path, 'attendance_export.csv');
      
      final File file = File(filePath);
      await file.writeAsString(csv);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported to: $filePath')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export error: $e')),
      );
    }
  }

  List<Attendance> get filteredAttendance {
    return attendanceList.where((attendance) {
      bool matchesName = studentNameFilter.isEmpty ||
          attendance.studentName.toLowerCase().contains(studentNameFilter.toLowerCase());
      bool matchesId = studentIdFilter.isEmpty ||
          attendance.eidNo.contains(studentIdFilter);
      bool matchesStatus = selectedStatus == 'All' ||
          attendance.status.toLowerCase() == selectedStatus.toLowerCase();
      bool matchesDate = selectedDate == null ||
          attendance.createdAt.year == selectedDate!.year &&
              attendance.createdAt.month == selectedDate!.month &&
              attendance.createdAt.day == selectedDate!.day;

      return matchesName && matchesId && matchesStatus && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Dashboard'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle),
            onPressed: _showMarkAttendanceDialog,
            tooltip: 'Mark Attendance',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: syncToServer,
            tooltip: 'Sync to server',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: exportToCSV,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Filter by Name',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            studentNameFilter = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Filter by EID',
                          prefixIcon: Icon(Icons.credit_card),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            studentIdFilter = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: statuses.map((String status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedStatus = newValue!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: dateController,
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                              dateController.text = picked.toIso8601String().split('T')[0];
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isOnline ? Colors.green.shade100 : Colors.red.shade100,
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (lastSyncTime != null) ...[
                  const Spacer(),
                  Text(
                    'Last sync: ${lastSyncTime!.split(' ')[1].split('.')[0]}',
                    style: TextStyle(
                      color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Attendance List
          Expanded(
            child: filteredAttendance.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No attendance records found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the checkmark icon above to mark attendance',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredAttendance.length,
                    itemBuilder: (context, index) {
                      final attendance = filteredAttendance[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: attendance.status == 'Present'
                                ? Colors.green
                                : attendance.status == 'Absent'
                                    ? Colors.red
                                    : Colors.orange,
                            child: Text(
                              attendance.status[0],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(attendance.studentName),
                          subtitle: Text('EID: ${attendance.eidNo}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                attendance.createdAt.toIso8601String().split('T')[0],
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                attendance.createdAt.toIso8601String().split('T')[1].split('.')[0],
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddStudentPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showMarkAttendanceDialog() async {
    // Get all students from database
    final students = await _databaseService.getAllStudents();
    print('=== CHECKING STUDENTS ===');
    print('Found ${students.length} students in database');
    for (var student in students) {
      print('Student: ${student.firstName} ${student.lastName} - EID: ${student.eidNo}');
    }
    
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students found. Please add students first.')),
      );
      return;
    }

    // Show dialog to select students and mark attendance
    showDialog(
      context: context,
      builder: (context) => MarkAttendanceDialog(
        students: students,
        onAttendanceMarked: () {
          // Refresh the attendance list
          loadLocal();
        },
      ),
    );
  }
}

class MarkAttendanceDialog extends StatefulWidget {
  final List<Student> students;
  final VoidCallback onAttendanceMarked;

  const MarkAttendanceDialog({
    super.key,
    required this.students,
    required this.onAttendanceMarked,
  });

  @override
  State<MarkAttendanceDialog> createState() => _MarkAttendanceDialogState();
}

class _MarkAttendanceDialogState extends State<MarkAttendanceDialog> {
  final Map<String, String> _attendanceStatus = {}; // studentId -> status
  final _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    // Initialize all students as 'present' by default
    for (final student in widget.students) {
      _attendanceStatus[student.id.toString()] = 'present';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mark Attendance'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: widget.students.length,
          itemBuilder: (context, index) {
            final student = widget.students[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text('${student.firstName} ${student.lastName}'),
                subtitle: Text('EID: ${student.eidNo}'),
                trailing: DropdownButton<String>(
                  value: _attendanceStatus[student.id.toString()] ?? 'present',
                  items: const [
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                    DropdownMenuItem(value: 'late', child: Text('Late')),
                  ],
                  onChanged: (String? newValue) {
                    setState(() {
                      _attendanceStatus[student.id.toString()] = newValue!;
                    });
                  },
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveAttendance,
          child: const Text('Save Attendance'),
        ),
      ],
    );
  }

  Future<void> _saveAttendance() async {
    try {
      final now = DateTime.now();
      
      for (final student in widget.students) {
        final status = _attendanceStatus[student.id.toString()] ?? 'present';
        
        final attendance = Attendance(
          studentId: student.id.toString(),
          studentName: '${student.firstName} ${student.lastName}',
          eidNo: student.eidNo,
          status: status,
          createdAt: now,
        );
        
        await _databaseService.insertAttendance(attendance);
      }
      
      Navigator.of(context).pop();
      widget.onAttendanceMarked();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance marked successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving attendance: $e')),
      );
    }
  }
}
