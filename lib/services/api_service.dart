import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';
import '../models/student.dart';
import '../models/attendance.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Authorization': apiToken,
  };

  // Login
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/method/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'usr': username, 'pwd': password},
      ).timeout(const Duration(seconds: 20));

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200 && result['message'] == 'Logged In') {
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Login failed';
        return {'success': false, 'error': message};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Create Student
  Future<Map<String, dynamic>> createStudent(Student student) async {
    try {
      print('=== STUDENT CREATION DEBUG ===');
      
      // First create the student without photo
      final payload = student.toFrappePayload();
      
      print('API URL: $baseUrl/api/resource/Student');
      print('Headers: $_headers');
      print('Payload: ${jsonEncode(payload)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/resource/Student'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      print('Response Status Code: ${response.statusCode}');
      print('Response Headers: ${response.headers}');
      print('Response Body: ${response.body}');

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
        print('Parsed Response: $result');
      } catch (e) {
        print('JSON Parse Error: $e');
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200) {
        print('Student created successfully!');
        
        // Now upload photo and attach it to the student
        if (student.extractedPhotoPath != null) {
          print('Uploading photo file...');
          final photoFile = File(student.extractedPhotoPath!);
          final fileName = 'student_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          
          // Try Base64 upload first
          var uploadResult = await uploadFile(photoFile, fileName);
          
          // If Base64 fails, try multipart upload
          if (!uploadResult['success']) {
            print('Base64 upload failed, trying multipart upload...');
            uploadResult = await uploadFileMultipart(photoFile, fileName);
          }
          
          if (uploadResult['success']) {
            final photoFileUrl = uploadResult['file_url'];
            print('Photo uploaded successfully: $photoFileUrl');
            
            // Update student with photo URL
            final studentName = result['data']?['name'] as String?;
            if (studentName != null) {
              await _attachPhotoToStudent(studentName, photoFileUrl);
            }
          } else {
            print('Both upload methods failed: ${uploadResult['error']}');
            // Continue without photo rather than failing completely
          }
        }
        
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to create student';
        print('API Error: $message');
        return {'success': false, 'error': message};
      }
    } catch (e) {
      print('Exception in createStudent: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Attach photo to student document
  Future<void> _attachPhotoToStudent(String studentName, String photoFileUrl) async {
    try {
      print('=== ATTACHING PHOTO TO STUDENT ===');
      print('Student Name: $studentName');
      print('Photo URL: $photoFileUrl');
      
      final payload = {
        'doctype': 'Student',
        'name': studentName,
        'custom_photo': photoFileUrl,
      };
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/resource/Student/$studentName'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));
      
      print('Photo attachment response: ${response.statusCode}');
      print('Photo attachment body: ${response.body}');
      
      if (response.statusCode == 200) {
        print('Photo attached successfully to student!');
      } else {
        print('Failed to attach photo to student');
      }
    } catch (e) {
      print('Error attaching photo to student: $e');
    }
  }

  // Create Customer
  Future<Map<String, dynamic>> createCustomer(String customerName) async {
    try {
      final payload = {
        'doctype': 'Customer',
        'customer_name': customerName,
        'customer_type': 'Individual',
        'customer_group': 'All Customer Groups',
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/resource/Customer'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200) {
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to create customer';
        return {'success': false, 'error': message};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Create Attendance
  Future<Map<String, dynamic>> createAttendance(Attendance attendance) async {
    try {
      final payload = attendance.toFrappePayload();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/resource/Attendance'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200) {
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to create attendance';
        return {'success': false, 'error': message};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get Students
  Future<Map<String, dynamic>> getStudents() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/resource/Student?fields=["name","first_name","last_name","custom_eid_no"]'),
        headers: _headers,
      ).timeout(const Duration(seconds: 20));

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200) {
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to fetch students';
        return {'success': false, 'error': message};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get Customers
  Future<Map<String, dynamic>> getCustomers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/resource/Customer?fields=["name","customer_name"]&limit_page_length=100'),
        headers: _headers,
      ).timeout(const Duration(seconds: 20));

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid response format: $e');
      }

      if (response.statusCode == 200) {
        return {'success': true, 'data': result};
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to fetch customers';
        return {'success': false, 'error': message};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Test Connection
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/method/ping'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Upload file to Frappe
  Future<Map<String, dynamic>> uploadFile(File file, String fileName) async {
    try {
      print('=== UPLOADING FILE TO FRAPPE ===');
      print('File path: ${file.path}');
      print('File name: $fileName');

      // Read file as bytes
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      
      print('File size: ${bytes.length} bytes');
      print('Base64 length: ${base64String.length} characters');

      // Try different Frappe upload formats
      final payload = {
        'cmd': 'upload_file',
        'filename': fileName,
        'content_base64': base64String,
        'is_private': true,
        'folder': 'Home/Attachments',
      };

      print('Upload URL: $baseUrl/api/method/upload_file');
      print('Payload keys: ${payload.keys.toList()}');

      final response = await http.post(
        Uri.parse('$baseUrl/api/method/upload_file'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      print('Upload Response Status: ${response.statusCode}');
      print('Upload Response Headers: ${response.headers}');
      print('Upload Response Body: ${response.body}');

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
        print('Parsed Upload Response: $result');
      } catch (e) {
        print('Upload JSON Parse Error: $e');
        throw Exception('Invalid upload response format: $e');
      }

      if (response.statusCode == 200) {
        // Try different response structures
        String? fileUrl;
        
        if (result['message'] is Map) {
          fileUrl = result['message']?['file_url'] as String?;
        } else if (result['message'] is String) {
          fileUrl = result['message'] as String?;
        } else if (result['data'] != null) {
          fileUrl = result['data']?['file_url'] as String?;
        }
        
        if (fileUrl != null) {
          print('File uploaded successfully: $fileUrl');
          return {'success': true, 'file_url': fileUrl};
        } else {
          print('No file_url found in response structure');
          print('Available keys: ${result.keys.toList()}');
          return {'success': false, 'error': 'No file URL returned. Response: $result'};
        }
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to upload file';
        print('Upload Error: $message');
        return {'success': false, 'error': message};
      }
    } catch (e) {
      print('File upload exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Alternative upload method using multipart form data
  Future<Map<String, dynamic>> uploadFileMultipart(File file, String fileName) async {
    try {
      print('=== UPLOADING FILE TO FRAPPE (MULTIPART) ===');
      print('File path: ${file.path}');
      print('File name: $fileName');

      final bytes = await file.readAsBytes();
      print('File size: ${bytes.length} bytes');

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/method/upload_file'),
      );

      // Add headers
      request.headers.addAll(_headers);

      // Add file
      request.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          bytes.length,
          filename: fileName,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      // Add other fields
      request.fields['filename'] = fileName;
      request.fields['is_private'] = 'true';
      request.fields['folder'] = 'Home/Attachments';

      print('Sending multipart request...');
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      print('Multipart Upload Response Status: ${response.statusCode}');
      print('Multipart Upload Response Body: ${response.body}');

      final body = response.body;
      Map<String, dynamic>? result;
      
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
        print('Parsed Multipart Upload Response: $result');
      } catch (e) {
        print('Multipart Upload JSON Parse Error: $e');
        throw Exception('Invalid multipart upload response format: $e');
      }

      if (response.statusCode == 200) {
        String? fileUrl;
        
        if (result['message'] is Map) {
          fileUrl = result['message']?['file_url'] as String?;
        } else if (result['message'] is String) {
          fileUrl = result['message'] as String?;
        } else if (result['data'] != null) {
          fileUrl = result['data']?['file_url'] as String?;
        }
        
        if (fileUrl != null) {
          print('File uploaded successfully via multipart: $fileUrl');
          return {'success': true, 'file_url': fileUrl};
        } else {
          print('No file_url found in multipart response structure');
          print('Available keys: ${result.keys.toList()}');
          return {'success': false, 'error': 'No file URL returned. Response: $result'};
        }
      } else {
        final message = result['message']?.toString() ?? 
                       result['exc']?.toString() ?? 
                       'Failed to upload file via multipart';
        print('Multipart Upload Error: $message');
        return {'success': false, 'error': message};
      }
    } catch (e) {
      print('Multipart file upload exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
