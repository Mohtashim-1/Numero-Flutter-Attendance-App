import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'dart:typed_data';
import '../models/student.dart';
import '../models/attendance.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_button.dart';

class StudentAttendancePage extends StatefulWidget {
  final List<Student> students;
  final DateTime attendanceDate;

  const StudentAttendancePage({
    super.key,
    required this.students,
    required this.attendanceDate,
  });

  @override
  State<StudentAttendancePage> createState() => _StudentAttendancePageState();
}

class _StudentAttendancePageState extends State<StudentAttendancePage> {
  final _databaseService = DatabaseService();
  final _apiService = ApiService();
  final _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );
  final _localAuth = LocalAuthentication();

  int currentStudentIndex = 0;
  String? signaturePath;
  bool fingerprintVerified = false;
  bool isSubmitting = false;

  Student get currentStudent => widget.students[currentStudentIndex];

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  void _nextStudent() {
    if (currentStudentIndex < widget.students.length - 1) {
      setState(() {
        currentStudentIndex++;
        signaturePath = null;
        fingerprintVerified = false;
        _signatureController.clear();
      });
    } else {
      // All students completed
      _showCompletionDialog();
    }
  }

  void _previousStudent() {
    if (currentStudentIndex > 0) {
      setState(() {
        currentStudentIndex--;
        signaturePath = null;
        fingerprintVerified = false;
        _signatureController.clear();
      });
    }
  }

  Future<void> _authenticateFingerprint() async {
    try {
      // Check if biometric authentication is available
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      if (!isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fingerprint authentication not available on this device')),
        );
        return;
      }

      // Check available biometrics
      final List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No biometric authentication methods available')),
        );
        return;
      }

      // Authenticate using fingerprint
      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate with your fingerprint to mark attendance',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        setState(() {
          fingerprintVerified = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fingerprint verified successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fingerprint authentication failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error authenticating fingerprint: $e')),
      );
    }
  }

  Future<void> _saveSignature() async {
    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign first!')),
      );
      return;
    }

    try {
      final Uint8List? signatureData = await _signatureController.toPngBytes();
      if (signatureData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate signature data!')),
        );
        return;
      }
      
      // Save signature to temporary file
      final tempDir = Directory.systemTemp;
      final signatureFile = File('${tempDir.path}/signature_${currentStudent.id}_${DateTime.now().millisecondsSinceEpoch}.png');
      await signatureFile.writeAsBytes(signatureData);
      
      setState(() {
        signaturePath = signatureFile.path;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving signature: $e')),
      );
    }
  }

  Future<void> _submitAttendance() async {
    if (signaturePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign the attendance first!')),
      );
      return;
    }

    if (!fingerprintVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please verify your fingerprint first!')),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      // Create attendance record
      final attendance = Attendance(
        studentId: currentStudent.id.toString(),
        studentName: '${currentStudent.firstName} ${currentStudent.lastName}',
        eidNo: currentStudent.eidNo,
        status: 'present',
        signaturePath: signaturePath,
        photoPath: null, // No photo, using fingerprint instead
        createdAt: widget.attendanceDate,
      );

      // Save to local database
      await _databaseService.insertAttendance(attendance);

      // Try to sync to Frappe
      try {
        final result = await _apiService.createAttendance(attendance);
        if (result['success']) {
          await _databaseService.markAttendanceAsSynced(attendance.id!);
        }
      } catch (e) {
        print('Failed to sync to Frappe: $e');
        // Continue anyway, will sync later
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance submitted successfully!')),
      );

      _nextStudent();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting attendance: $e')),
      );
    } finally {
      setState(() {
        isSubmitting = false;
      });
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Attendance Complete!'),
        content: const Text('All students have completed their attendance.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Student ${currentStudentIndex + 1} of ${widget.students.length}'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Student Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(
                      currentStudent.firstName[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${currentStudent.firstName} ${currentStudent.lastName}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'EID: ${currentStudent.eidNo}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date: ${widget.attendanceDate.day}/${widget.attendanceDate.month}/${widget.attendanceDate.year}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Signature Section
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
                      Icon(Icons.edit, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Digital Signature',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Signature(
                      controller: _signatureController,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          text: 'Clear Signature',
                          onPressed: () => _signatureController.clear(),
                          icon: Icons.clear,
                          backgroundColor: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomButton(
                          text: 'Save Signature',
                          onPressed: _saveSignature,
                          icon: Icons.save,
                        ),
                      ),
                    ],
                  ),
                  if (signaturePath != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Signature saved',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Fingerprint Section
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
                      Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Fingerprint Verification',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: 'Verify Fingerprint',
                    onPressed: _authenticateFingerprint,
                    icon: Icons.fingerprint,
                    width: double.infinity,
                  ),
                  if (fingerprintVerified)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Fingerprint verified',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Navigation Buttons
            Row(
              children: [
                if (currentStudentIndex > 0)
                  Expanded(
                    child: CustomButton(
                      text: 'Previous',
                      onPressed: _previousStudent,
                      icon: Icons.arrow_back,
                      backgroundColor: Colors.grey.shade600,
                    ),
                  ),
                if (currentStudentIndex > 0) const SizedBox(width: 12),
                Expanded(
                  child: CustomButton(
                    text: isSubmitting ? 'Submitting...' : 'Submit & Next',
                    onPressed: isSubmitting ? null : _submitAttendance,
                    icon: Icons.check,
                    isLoading: isSubmitting,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
