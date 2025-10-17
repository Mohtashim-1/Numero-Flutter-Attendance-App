import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_button.dart';
import 'student_attendance_page.dart';

class InstructorAttendancePage extends StatefulWidget {
  const InstructorAttendancePage({super.key});

  @override
  State<InstructorAttendancePage> createState() => _InstructorAttendancePageState();
}

class _InstructorAttendancePageState extends State<InstructorAttendancePage> {
  final _databaseService = DatabaseService();
  final _apiService = ApiService();
  
  List<Student> students = [];
  bool isLoading = true;
  String selectedDate = '';
  DateTime? attendanceDate;

  @override
  void initState() {
    super.initState();
    attendanceDate = DateTime.now();
    selectedDate = _formatDate(attendanceDate!);
    _loadStudents();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _loadStudents() async {
    setState(() {
      isLoading = true;
    });

    try {
      final studentsList = await _databaseService.getAllStudents();
      setState(() {
        students = studentsList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading students: $e')),
      );
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: attendanceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (picked != null && picked != attendanceDate) {
      setState(() {
        attendanceDate = picked;
        selectedDate = _formatDate(picked);
      });
    }
  }

  void _startAttendanceSession() {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students found. Please add students first.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAttendancePage(
          students: students,
          attendanceDate: attendanceDate!,
        ),
      ),
    ).then((_) {
      // Refresh the page when returning from attendance session
      _loadStudents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Instructor Dashboard'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Selection
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Attendance Date',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedDate,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      CustomButton(
                        text: 'Select Date',
                        onPressed: _selectDate,
                        icon: Icons.edit_calendar,
                        width: 120,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Students Count
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: AppTheme.primaryColor, size: 32),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Students',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${students.length}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Start Attendance Button
            CustomButton(
              text: 'Start Attendance Session',
              onPressed: _startAttendanceSession,
              icon: Icons.play_arrow,
              width: double.infinity,
              isLoading: isLoading,
            ),

            const SizedBox(height: 20),

            // Students List
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (students.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No students found',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add students first to start attendance',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Students List',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryColor,
                                child: Text(
                                  student.firstName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text('${student.firstName} ${student.lastName}'),
                              subtitle: Text('EID: ${student.eidNo}'),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
