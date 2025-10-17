import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../models/student.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_button.dart';

class AddStudentPage extends StatefulWidget {
  const AddStudentPage({super.key});

  @override
  State<AddStudentPage> createState() => _AddStudentPageState();
}

class _AddStudentPageState extends State<AddStudentPage> {
  final _formKey = GlobalKey<FormState>();
  final _databaseService = DatabaseService();
  final _apiService = ApiService();
  final _cameraService = CameraService();

  // Controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController eidNoController = TextEditingController();
  final TextEditingController nationalityController = TextEditingController();
  final TextEditingController genderController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController cardNumberController = TextEditingController();
  final TextEditingController occupationController = TextEditingController();
  final TextEditingController employerController = TextEditingController();
  final TextEditingController issuingPlaceController = TextEditingController();
  final TextEditingController bloodTypeController = TextEditingController();
  final TextEditingController emergencyContactController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  String selectedContactType = 'Without Email';
  String selectedModeOfPayment = 'Cash';
  String? selectedCustomer;
  String selectedDocumentType = 'Emirates ID'; // New: Document type selection

  // Customer list fetched from Frappe
  List<String> customers = [];
  bool isLoadingCustomers = false;
  bool isOnline = false;
  bool isSubmitting = false;
  
  // Document scanning (Emirates ID or Passport)
  String? frontCardImagePath;
  String? backCardImagePath;
  String? extractedPhotoPath;
  bool isScanning = false;

  final List<String> contactTypes = ['Email', 'Without Email'];
  final List<String> modesOfPayment = ['Cash', 'Card', 'Bank Transfer'];
  final List<String> bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<String> genders = ['Male', 'Female'];
  final List<String> documentTypes = ['Emirates ID', 'Passport']; // New: Document types

  @override
  void initState() {
    super.initState();
    checkConnectivity();
    _loadCustomers();
  }

  // Load customers from Frappe
  Future<void> _loadCustomers() async {
    print('=== LOADING CUSTOMERS ===');
    setState(() {
      isLoadingCustomers = true;
    });

    try {
      final result = await ApiService().getCustomers();
      print('Customer API Result: $result');
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;
        final customerList = data['data'] as List<dynamic>;
        print('Customer List: $customerList');
        
        setState(() {
          customers = customerList.map((customer) {
            final customerName = customer['customer_name'] as String? ?? customer['name'] as String;
            return customerName.trim();
          }).toList();
          isLoadingCustomers = false;
        });
        print('Loaded ${customers.length} customers');
      } else {
        print('Customer API Error: ${result['error']}');
        setState(() {
          isLoadingCustomers = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load customers: ${result['error']}')),
          );
        }
      }
    } catch (e) {
      print('Customer Loading Exception: $e');
      setState(() {
        isLoadingCustomers = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading customers: $e')),
        );
      }
    }
  }

  Future<void> checkConnectivity() async {
    final connectivity = await Connectivity().checkConnectivity();
    setState(() {
      isOnline = connectivity != ConnectivityResult.none;
    });
  }

  Future<void> scanEmiratesId() async {
    // Show options for front or back card
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan Emirates ID',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Front Card',
                    onPressed: () {
                      Navigator.pop(context);
                      scanEmiratesIDFront();
                    },
                    icon: Icons.credit_card,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'Back Card',
                    onPressed: () {
                      Navigator.pop(context);
                      scanEmiratesIDBack();
                    },
                    icon: Icons.credit_card,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Both Cards',
              onPressed: () {
                Navigator.pop(context);
                scanBothCards();
              },
              icon: Icons.credit_card,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> scanEmiratesIDFront() async {
    // Show options for camera or gallery
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Front Card - Select Source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Camera',
                    onPressed: () {
                      Navigator.pop(context);
                      _captureFrontCard();
                    },
                    icon: Icons.camera_alt,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'Gallery',
                    onPressed: () {
                      Navigator.pop(context);
                      _uploadFrontCard();
                    },
                    icon: Icons.photo_library,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureFrontCard() async {
    try {
      setState(() => isScanning = true);
      final initialized = await _cameraService.initialize();
      if (!initialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize camera')),
        );
        return;
      }

      final photo = await _cameraService.capturePhoto();
      if (photo != null) {
        await _processFrontCardImage(photo.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing front card: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _uploadFrontCard() async {
    try {
      setState(() => isScanning = true);
      final imagePath = await _cameraService.pickImageFromGallery();
      if (imagePath != null) {
        await _processFrontCardImage(imagePath);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading front card: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _processFrontCardImage(String imagePath) async {
    setState(() => frontCardImagePath = imagePath);
    final extractedData = await _cameraService.extractStudentData(File(imagePath));
    if (extractedData != null) {
      setState(() {
        firstNameController.text = extractedData['first_name'] ?? '';
        lastNameController.text = extractedData['last_name'] ?? '';
        eidNoController.text = extractedData['eid_no'] ?? '';
        nationalityController.text = extractedData['nationality'] ?? '';
        genderController.text = extractedData['gender'] ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Front card data extracted successfully!')),
      );
    }
    
    // Extract photo from the Emirates ID
    final photoPath = await _cameraService.extractPhotoFromEmiratesID(File(imagePath));
    if (photoPath != null) {
      setState(() {
        extractedPhotoPath = photoPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo extracted from Emirates ID!')),
      );
    }
  }

  Future<void> scanEmiratesIDBack() async {
    // Show options for camera or gallery
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Back Card - Select Source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Camera',
                    onPressed: () {
                      Navigator.pop(context);
                      _captureBackCard();
                    },
                    icon: Icons.camera_alt,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'Gallery',
                    onPressed: () {
                      Navigator.pop(context);
                      _uploadBackCard();
                    },
                    icon: Icons.photo_library,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureBackCard() async {
    try {
      setState(() => isScanning = true);
      final initialized = await _cameraService.initialize();
      if (!initialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize camera')),
        );
        return;
      }

      final photo = await _cameraService.capturePhoto();
      if (photo != null) {
        await _processBackCardImage(photo.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing back card: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _uploadBackCard() async {
    try {
      setState(() => isScanning = true);
      final imagePath = await _cameraService.pickImageFromGallery();
      if (imagePath != null) {
        await _processBackCardImage(imagePath);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading back card: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _processBackCardImage(String imagePath) async {
    setState(() => backCardImagePath = imagePath);
    final extractedData = await _cameraService.extractStudentData(File(imagePath));
    if (extractedData != null) {
      setState(() {
        addressController.text = extractedData['address'] ?? '';
        cardNumberController.text = extractedData['card_number'] ?? '';
        issuingPlaceController.text = extractedData['issuing_place'] ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Back card data extracted successfully!')),
      );
    }
  }

  Future<void> scanBothCards() async {
    // First scan front card
    await scanEmiratesIDFront();
    if (mounted) {
      // Wait a moment then scan back card
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        await scanEmiratesIDBack();
      }
    }
  }

  // Passport scanning methods
  Future<void> scanPassport() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan Passport',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Camera',
                    onPressed: () {
                      Navigator.pop(context);
                      _capturePassport();
                    },
                    icon: Icons.camera_alt,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'Gallery',
                    onPressed: () {
                      Navigator.pop(context);
                      _pickPassportFromGallery();
                    },
                    icon: Icons.photo_library,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capturePassport() async {
    try {
      setState(() => isScanning = true);
      
      final imagePath = await _cameraService.takePicture();
      if (imagePath != null) {
        await _processPassportImage(imagePath);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing passport: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _pickPassportFromGallery() async {
    try {
      setState(() => isScanning = true);
      
      final imagePath = await _cameraService.pickImageFromGallery();
      if (imagePath != null) {
        await _processPassportImage(imagePath);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking passport from gallery: $e')),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _processPassportImage(String imagePath) async {
    setState(() {
      frontCardImagePath = imagePath;
      backCardImagePath = null; // Passport is single-sided
    });

    // Extract data from passport using OCR
    final extractedData = await _cameraService.extractPassportData(File(imagePath));
    
    if (extractedData != null && extractedData.isNotEmpty) {
      // Update form fields with extracted data
      if (extractedData['firstName'] != null) {
        firstNameController.text = extractedData['firstName']!;
      }
      if (extractedData['lastName'] != null) {
        lastNameController.text = extractedData['lastName']!;
      }
      if (extractedData['nationality'] != null) {
        nationalityController.text = extractedData['nationality']!;
      }
      if (extractedData['gender'] != null) {
        genderController.text = extractedData['gender']!;
      }
      if (extractedData['eidNo'] != null) {
        eidNoController.text = extractedData['eidNo']!;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passport data extracted successfully!')),
      );
    }
    
    // Extract photo from the passport
    final photoPath = await _cameraService.extractPhotoFromPassport(File(imagePath));
    if (photoPath != null) {
      setState(() {
        extractedPhotoPath = photoPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo extracted from passport!')),
      );
    }
  }

  Future<void> submitStudent() async {
    if (!_formKey.currentState!.validate()) {
      print('Form validation failed');
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final student = Student(
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        nationality: nationalityController.text.trim(),
        gender: genderController.text.trim(),
        eidNo: eidNoController.text.trim(),
        address: addressController.text.trim(),
        cardNumber: cardNumberController.text.trim(),
        occupation: occupationController.text.trim(),
        employer: employerController.text.trim(),
        issuingPlace: issuingPlaceController.text.trim(),
        bloodType: bloodTypeController.text.trim(),
        emergencyContact: emergencyContactController.text.trim(),
        email: emailController.text.trim(),
        contactType: selectedContactType,
        modeOfPayment: selectedModeOfPayment,
        customer: selectedCustomer,
        frontCardImagePath: frontCardImagePath,
        backCardImagePath: backCardImagePath,
        extractedPhotoPath: extractedPhotoPath,
        createdAt: DateTime.now(),
      );

      print('=== FORM SUBMISSION DEBUG ===');
      print('Student Data:');
      print('First Name: ${student.firstName}');
      print('Last Name: ${student.lastName}');
      print('EID No: ${student.eidNo}');
      print('Gender: ${student.gender}');
      print('Nationality: ${student.nationality}');
      print('Customer: ${student.customer}');
      print('Contact Type: ${student.contactType}');
      print('Mode of Payment: ${student.modeOfPayment}');
      print('Is Online: $isOnline');

      // Save to local database
      await _databaseService.insertStudent(student);

      // Try to sync to server if online
      if (isOnline) {
        print('Attempting to sync to server...');
        try {
          final result = await _apiService.createStudent(student);
          print('API Result: $result');
          if (!result['success']) {
            print('API Error: ${result['error']}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved locally. Sync failed: ${result['error']}')),
            );
          } else {
            print('Student synced successfully!');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Student added successfully!')),
            );
          }
        } catch (e) {
          print('Sync Exception: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved locally. Sync error: $e')),
          );
        }
      } else {
        print('Offline - saving locally only');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student saved locally. Will sync when online.')),
        );
      }

      // Reset form after successful submission
      _resetForm();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving student: $e')),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  // Reset form after successful submission
  void _resetForm() {
    _formKey.currentState?.reset();
    firstNameController.clear();
    lastNameController.clear();
    eidNoController.clear();
    nationalityController.clear();
    genderController.clear();
    addressController.clear();
    cardNumberController.clear();
    occupationController.clear();
    employerController.clear();
    issuingPlaceController.clear();
    bloodTypeController.clear();
    emergencyContactController.clear();
    emailController.clear();
    
    setState(() {
      selectedContactType = 'Without Email';
      selectedModeOfPayment = 'Cash';
      selectedCustomer = null;
      selectedDocumentType = 'Emirates ID'; // Reset to default
      frontCardImagePath = null;
      backCardImagePath = null;
      extractedPhotoPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Student'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: scanEmiratesId,
            tooltip: 'Scan Emirates ID',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      color: isOnline ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isOnline ? 'Online - Will sync to server' : 'Offline - Will save locally',
                      style: TextStyle(
                        color: isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Document Type Selection
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
                        Icon(Icons.assignment, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Document Type',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      value: selectedDocumentType,
                      decoration: const InputDecoration(
                        labelText: 'Select Document Type *',
                        border: OutlineInputBorder(),
                      ),
                      items: documentTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedDocumentType = newValue!;
                          // Clear previous scans when changing document type
                          frontCardImagePath = null;
                          backCardImagePath = null;
                          extractedPhotoPath = null;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a document type';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Document Scanning Section
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
                        Icon(
                          selectedDocumentType == 'Emirates ID' 
                            ? Icons.credit_card 
                            : Icons.airplane_ticket,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedDocumentType} Scanning',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Scan buttons - Dynamic based on document type
                    if (selectedDocumentType == 'Emirates ID') ...[
                      Row(
                        children: [
                          Expanded(
                            child: CustomButton(
                              text: 'Front Card',
                              onPressed: isScanning ? null : scanEmiratesIDFront,
                              icon: Icons.credit_card,
                              isLoading: isScanning,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomButton(
                              text: 'Back Card',
                              onPressed: isScanning ? null : scanEmiratesIDBack,
                              icon: Icons.credit_card,
                              isLoading: isScanning,
                            ),
                          ),
                        ],
                      ),
                    ] else if (selectedDocumentType == 'Passport') ...[
                      CustomButton(
                        text: 'Scan Passport',
                        onPressed: isScanning ? null : scanPassport,
                        icon: Icons.airplane_ticket,
                        isLoading: isScanning,
                        width: double.infinity,
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Scanned images preview
                    if (frontCardImagePath != null || backCardImagePath != null) ...[
                      Text(
                        selectedDocumentType == 'Emirates ID' 
                          ? 'Scanned Cards:' 
                          : 'Scanned Document:',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (frontCardImagePath != null) ...[
                            Expanded(
                              child: Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.primaryColor),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(frontCardImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            if (selectedDocumentType == 'Emirates ID' && backCardImagePath != null)
                              const SizedBox(width: 8),
                          ],
                          if (selectedDocumentType == 'Emirates ID' && backCardImagePath != null) ...[
                            Expanded(
                              child: Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.primaryColor),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(backCardImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (frontCardImagePath != null)
                            Expanded(
                              child: Text(
                                selectedDocumentType == 'Emirates ID' 
                                  ? 'Front Card ✓' 
                                  : 'Document ✓',
                                style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (selectedDocumentType == 'Emirates ID' && backCardImagePath != null)
                            Expanded(
                              child: Text(
                                'Back Card ✓',
                                style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Photo Preview Section
              if (extractedPhotoPath != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Extracted Photo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(extractedPhotoPath!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Photo extracted from Emirates ID',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Personal Information
              const Text(
                'Personal Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'First name is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Last name is required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: eidNoController,
                      decoration: InputDecoration(
                        labelText: selectedDocumentType == 'Emirates ID' 
                          ? 'Emirates ID *' 
                          : 'Passport Number *',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return selectedDocumentType == 'Emirates ID' 
                            ? 'Emirates ID is required'
                            : 'Passport Number is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: genderController.text.isEmpty || !genders.contains(genderController.text) 
                          ? null 
                          : genderController.text,
                      decoration: const InputDecoration(
                        labelText: 'Gender *',
                        border: OutlineInputBorder(),
                      ),
                      items: genders.map((String gender) {
                        return DropdownMenuItem<String>(
                          value: gender,
                          child: Text(gender),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          genderController.text = newValue ?? '';
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Gender is required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: nationalityController,
                      decoration: const InputDecoration(
                        labelText: 'Nationality *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nationality is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: bloodTypeController.text.isEmpty ? null : bloodTypeController.text,
                      decoration: const InputDecoration(
                        labelText: 'Blood Type',
                        border: OutlineInputBorder(),
                      ),
                      items: bloodTypes.map((String bloodType) {
                        return DropdownMenuItem<String>(
                          value: bloodType,
                          child: Text(bloodType),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          bloodTypeController.text = newValue ?? '';
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Contact Information
              const Text(
                'Contact Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: selectedContactType == 'Email' ? 'Email *' : 'Email',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (selectedContactType == 'Email') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required when Contact Type is Email';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                            return 'Please enter a valid email address';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: emergencyContactController,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Contact',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Professional Information
              const Text(
                'Professional Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: occupationController,
                      decoration: const InputDecoration(
                        labelText: 'Occupation',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: employerController,
                      decoration: const InputDecoration(
                        labelText: 'Employer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: cardNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Card Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: issuingPlaceController,
                      decoration: const InputDecoration(
                        labelText: 'Issuing Place',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Additional Information
              const Text(
                'Additional Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedContactType,
                      decoration: const InputDecoration(
                        labelText: 'Contact Type',
                        border: OutlineInputBorder(),
                      ),
                      items: contactTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedContactType = newValue!;
                        });
                        // Trigger form validation to update email field validation
                        _formKey.currentState?.validate();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedModeOfPayment,
                      decoration: const InputDecoration(
                        labelText: 'Mode of Payment',
                        border: OutlineInputBorder(),
                      ),
                      items: modesOfPayment.map((String mode) {
                        return DropdownMenuItem<String>(
                          value: mode,
                          child: Text(mode),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedModeOfPayment = newValue!;
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: selectedCustomer,
                decoration: InputDecoration(
                  labelText: 'Customer *',
                  border: const OutlineInputBorder(),
                  suffixIcon: isLoadingCustomers 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                ),
                items: isLoadingCustomers 
                  ? [const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Loading customers...'),
                    )]
                  : customers.isEmpty
                    ? [const DropdownMenuItem<String>(
                        value: null,
                        child: Text('No customers found'),
                      )]
                    : customers.map((String customer) {
                        return DropdownMenuItem<String>(
                          value: customer,
                          child: Text(
                            customer,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                onChanged: isLoadingCustomers || customers.isEmpty 
                  ? null 
                  : (String? newValue) {
                      setState(() {
                        selectedCustomer = newValue;
                      });
                    },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a customer';
                  }
                  return null;
                },
                isExpanded: true,
                menuMaxHeight: 200,
              ),

              const SizedBox(height: 30),

              // Submit Button
              CustomButton(
                text: 'Add Student',
                onPressed: isSubmitting ? null : submitStudent,
                isLoading: isSubmitting,
                icon: Icons.person_add,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    eidNoController.dispose();
    nationalityController.dispose();
    genderController.dispose();
    addressController.dispose();
    cardNumberController.dispose();
    occupationController.dispose();
    employerController.dispose();
    issuingPlaceController.dispose();
    bloodTypeController.dispose();
    emergencyContactController.dispose();
    emailController.dispose();
    _cameraService.dispose();
    super.dispose();
  }
}
