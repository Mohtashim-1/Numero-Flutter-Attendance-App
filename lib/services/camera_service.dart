import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  List<CameraDescription>? get cameras => _cameras;

  Future<bool> initialize() async {
    try {
      // Check camera permission
      final permission = await Permission.camera.request();
      if (permission != PermissionStatus.granted) {
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return false;
      }

      // Initialize camera controller
      _controller = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Camera initialization error: $e');
      return false;
    }
  }

  Future<File?> capturePhoto() async {
    if (!_isInitialized || _controller == null) {
      return null;
    }

    try {
      final XFile photo = await _controller!.takePicture();
      return File(photo.path);
    } catch (e) {
      print('Photo capture error: $e');
      return null;
    }
  }

  Future<String?> savePhoto(File photoFile, String fileName) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String photoDir = path.join(appDir.path, 'photos');
      
      // Create photos directory if it doesn't exist
      await Directory(photoDir).create(recursive: true);
      
      final String filePath = path.join(photoDir, '$fileName.jpg');
      final File savedFile = await photoFile.copy(filePath);
      
      return savedFile.path;
    } catch (e) {
      print('Photo save error: $e');
      return null;
    }
  }

  Future<String?> processEmiratesId(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer();
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      // Look for Emirates ID number pattern
      final RegExp eidPattern = RegExp(r'\b784-\d{4}-\d{7}-\d{1}\b');
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final String text = line.text;
          final Match? match = eidPattern.firstMatch(text);
          if (match != null) {
            await textRecognizer.close();
            return match.group(0);
          }
        }
      }
      
      await textRecognizer.close();
      return null;
    } catch (e) {
      print('Emirates ID processing error: $e');
      return null;
    }
  }

  Future<Map<String, String>?> extractStudentData(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer();
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      Map<String, String> extractedData = {};
      
      // Look for Emirates ID number
      final RegExp eidPattern = RegExp(r'\b784-\d{4}-\d{7}-\d{1}\b');
      String? eidNumber;
      
      // Look for name patterns - more flexible to catch Arabic/English names
      final RegExp namePattern = RegExp(r'[A-Z][a-zA-Z]+ [A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*');
      String? fullName;
      String? firstName;
      String? lastName;
      bool nameFound = false; // Track if we found a proper name
      
      // Look for nationality
      final RegExp nationalityPattern = RegExp(r'(UAE|UNITED ARAB EMIRATES|EMIRATI)', caseSensitive: false);
      String? nationality;
      
      // Look for gender
      final RegExp genderPattern = RegExp(r'(MALE|FEMALE|M|F)', caseSensitive: false);
      String? gender;
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final String text = line.text;
          print('OCR Text: $text'); // Debug logging
          
          // Check for Emirates ID
          final Match? eidMatch = eidPattern.firstMatch(text);
          if (eidMatch != null) {
            eidNumber = eidMatch.group(0);
          }
          
          // Check for name - look for "Name:" pattern first (highest priority)
          if (text.toLowerCase().contains('name:')) {
            String nameText = text.substring(text.toLowerCase().indexOf('name:') + 5).trim();
            print('Found Name text: "$nameText"');
            if (nameText.isNotEmpty) {
              // Filter out nationality and common non-name words
              if (!nameText.toUpperCase().contains('UNITED') && 
                  !nameText.toUpperCase().contains('ARAB') &&
                  !nameText.toUpperCase().contains('EMIRATES') &&
                  !nameText.toUpperCase().contains('UAE') &&
                  nameText.length > 3) {
                fullName = nameText;
                nameFound = true;
                print('Setting fullName to: $fullName (from Name: pattern)');
                // Split into first and last name
                List<String> nameParts = nameText.split(' ');
                if (nameParts.length >= 2) {
                  firstName = nameParts[0];
                  lastName = nameParts.sublist(1).join(' ');
                  print('Split names - First: $firstName, Last: $lastName');
                }
              } else {
                print('Name text filtered out: $nameText');
              }
            }
          } else if (!nameFound) {
            // Fallback to regex pattern for other name formats (only if no Name: found)
            final Match? nameMatch = namePattern.firstMatch(text);
            if (nameMatch != null) {
              String potentialName = nameMatch.group(0) ?? '';
              print('Regex found potential name: "$potentialName"');
              // Filter out nationality and common non-name words
              if (!potentialName.toUpperCase().contains('UNITED') && 
                  !potentialName.toUpperCase().contains('ARAB') &&
                  !potentialName.toUpperCase().contains('EMIRATES') &&
                  !potentialName.toUpperCase().contains('UAE') &&
                  potentialName.length > 3) {
                fullName = potentialName;
                nameFound = true;
                print('Setting fullName to: $fullName (from regex)');
                // Split into first and last name
                List<String> nameParts = potentialName.split(' ');
                if (nameParts.length >= 2) {
                  firstName = nameParts[0];
                  lastName = nameParts.sublist(1).join(' ');
                  print('Split names - First: $firstName, Last: $lastName');
                }
              } else {
                print('Potential name filtered out: $potentialName');
              }
            }
          }
          
          // Check for nationality
          final Match? nationalityMatch = nationalityPattern.firstMatch(text);
          if (nationalityMatch != null) {
            nationality = nationalityMatch.group(0)?.toUpperCase();
          }
          
          // Check for gender
          final Match? genderMatch = genderPattern.firstMatch(text);
          if (genderMatch != null) {
            gender = genderMatch.group(0)?.toUpperCase();
          }
        }
      }
      
      if (eidNumber != null) {
        extractedData['eid_no'] = eidNumber;
      }
      
      print('Final extraction - firstName: $firstName, lastName: $lastName, fullName: $fullName');
      
      if (firstName != null && lastName != null) {
        print('Using firstName and lastName');
        extractedData['first_name'] = firstName;
        extractedData['last_name'] = lastName;
      } else if (fullName != null) {
        print('Using fullName: $fullName');
        final nameParts = fullName.split(' ');
        if (nameParts.length >= 2) {
          print('Split First Name: ${nameParts[0]}');
          print('Split Last Name: ${nameParts.sublist(1).join(' ')}');
          extractedData['first_name'] = nameParts[0];
          extractedData['last_name'] = nameParts.sublist(1).join(' ');
        }
      } else {
        print('No name extracted!');
      }
      
      if (nationality != null) {
        extractedData['nationality'] = nationality;
      }
      
      if (gender != null) {
        extractedData['gender'] = gender;
      }
      
      await textRecognizer.close();
      
      return extractedData.isNotEmpty ? extractedData : null;
    } catch (e) {
      print('Student data extraction error: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    _isInitialized = false;
  }

  Future<String?> pickImageFromGallery() async {
    try {
      // Check photos permission (for Android 13+)
      final permission = await Permission.photos.request();
      if (permission != PermissionStatus.granted) {
        // Fallback to storage permission for older Android versions
        final storagePermission = await Permission.storage.request();
        if (storagePermission != PermissionStatus.granted) {
          return null;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        return image.path;
      }
      return null;
    } catch (e) {
      print('Gallery picker error: $e');
      return null;
    }
  }

  // Take picture using camera
  Future<String?> takePicture() async {
    try {
      print('=== TAKING PICTURE WITH CAMERA ===');
      
      if (!_isInitialized || _controller == null) {
        print('Camera not initialized');
        return null;
      }

      final XFile image = await _controller!.takePicture();
      print('Picture taken: ${image.path}');
      return image.path;
    } catch (e) {
      print('Error taking picture: $e');
      return null;
    }
  }

  // Extract photo from Emirates ID card
  Future<String?> extractPhotoFromEmiratesID(File imageFile) async {
    try {
      print('=== EXTRACTING PHOTO FROM EMIRATES ID ===');
      
      // Read the image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        print('Failed to decode image');
        return null;
      }

      print('Image dimensions: ${image.width}x${image.height}');

      // Use face detection to find the photo area
      final faceDetector = GoogleMlKit.vision.faceDetector();
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await faceDetector.processImage(inputImage);

      print('Found ${faces.length} faces');

      if (faces.isNotEmpty) {
        // Get the largest face (likely the main photo)
        final largestFace = faces.reduce((a, b) => 
          (a.boundingBox.width * a.boundingBox.height) > 
          (b.boundingBox.width * b.boundingBox.height) ? a : b
        );

        print('Largest face bounding box: ${largestFace.boundingBox}');

        // Add some padding around the face
        final padding = 20.0;
        final left = (largestFace.boundingBox.left - padding).clamp(0.0, image.width.toDouble()).toInt();
        final top = (largestFace.boundingBox.top - padding).clamp(0.0, image.height.toDouble()).toInt();
        final right = (largestFace.boundingBox.right + padding).clamp(0.0, image.width.toDouble()).toInt();
        final bottom = (largestFace.boundingBox.bottom + padding).clamp(0.0, image.height.toDouble()).toInt();

        // Crop the image to the face area
        final croppedImage = img.copyCrop(
          image,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
        );

        // Make it square (common for ID photos)
        final size = (croppedImage.width > croppedImage.height) ? croppedImage.height : croppedImage.width;
        final squareImage = img.copyResizeCropSquare(croppedImage, size: size);

        // Save the cropped photo
        final tempDir = await getTemporaryDirectory();
        final photoPath = path.join(tempDir.path, 'emirates_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
        
        final photoFile = File(photoPath);
        await photoFile.writeAsBytes(img.encodeJpg(squareImage, quality: 85));

        print('Photo extracted and saved to: $photoPath');
        print('Photo dimensions: ${squareImage.width}x${squareImage.height}');

        await faceDetector.close();
        return photoPath;
      } else {
        print('No faces detected, trying alternative method...');
        
        // Alternative method: Look for photo in typical Emirates ID position (top-right area)
        final photoWidth = (image.width * 0.25).toInt(); // 25% of image width
        final photoHeight = (image.height * 0.3).toInt(); // 30% of image height
        final photoX = image.width - photoWidth - 20; // Right side with margin
        final photoY = 20; // Top with margin

        final croppedImage = img.copyCrop(
          image,
          x: photoX,
          y: photoY,
          width: photoWidth,
          height: photoHeight,
        );

        // Save the cropped photo
        final tempDir = await getTemporaryDirectory();
        final photoPath = path.join(tempDir.path, 'emirates_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
        
        final photoFile = File(photoPath);
        await photoFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 85));

        print('Photo extracted using alternative method: $photoPath');
        print('Photo dimensions: ${croppedImage.width}x${croppedImage.height}');

        await faceDetector.close();
        return photoPath;
      }
    } catch (e) {
      print('Photo extraction error: $e');
      return null;
    }
  }

  // Extract student data from passport document
  Future<Map<String, String>?> extractPassportData(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer();
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      Map<String, String> extractedData = {};
      
      // Look for passport number patterns
      final RegExp passportPattern = RegExp(r'[A-Z]{1,2}\d{6,9}');
      String? passportNumber;
      
      // Look for name patterns - passport specific
      final RegExp namePattern = RegExp(r'[A-Z][a-zA-Z]+ [A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*');
      String? fullName;
      String? firstName;
      String? lastName;
      
      // Look for nationality
      final RegExp nationalityPattern = RegExp(r'(PAKISTAN|INDIA|BANGLADESH|PHILIPPINES|NEPAL|SRI LANKA|UNITED ARAB EMIRATES|UAE|AMERICAN|BRITISH|CANADIAN|AUSTRALIAN)', caseSensitive: false);
      String? nationality;
      
      // Look for gender
      final RegExp genderPattern = RegExp(r'(MALE|FEMALE|M|F)', caseSensitive: false);
      String? gender;
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final String text = line.text;
          print('Passport OCR Text: $text');
          
          // Check for passport number
          final Match? passportMatch = passportPattern.firstMatch(text);
          if (passportMatch != null) {
            passportNumber = passportMatch.group(0);
          }
          
          // Check for name - look for "Name:" pattern first
          if (text.toLowerCase().contains('name')) {
            String nameText = text;
            // Extract name after "Name" or "Name:"
            if (text.toLowerCase().contains('name:')) {
              nameText = text.substring(text.toLowerCase().indexOf('name:') + 5).trim();
            } else if (text.toLowerCase().contains('name ')) {
              nameText = text.substring(text.toLowerCase().indexOf('name ') + 5).trim();
            }
            
            print('Found Name text: "$nameText"');
            if (nameText.isNotEmpty && nameText.length > 3) {
              // Filter out common non-name words
              if (!nameText.toUpperCase().contains('UNITED') && 
                  !nameText.toUpperCase().contains('ARAB') &&
                  !nameText.toUpperCase().contains('EMIRATES') &&
                  !nameText.toUpperCase().contains('UAE') &&
                  !nameText.toUpperCase().contains('FEDERAL') &&
                  !nameText.toUpperCase().contains('AUTHORITY') &&
                  !nameText.toUpperCase().contains('IDENTITY') &&
                  !nameText.toUpperCase().contains('CUSTOMS') &&
                  !nameText.toUpperCase().contains('PORT') &&
                  !nameText.toUpperCase().contains('SECURITY') &&
                  !nameText.toUpperCase().contains('RESIDENT') &&
                  !nameText.toUpperCase().contains('CARD') &&
                  !nameText.toUpperCase().contains('SIGNATURE') &&
                  !nameText.toUpperCase().contains('NUMBER') &&
                  !nameText.toUpperCase().contains('BIRTH') &&
                  !nameText.toUpperCase().contains('ISSUING') &&
                  !nameText.toUpperCase().contains('EXPIRY') &&
                  !nameText.toUpperCase().contains('DATE') &&
                  !nameText.toUpperCase().contains('SEX') &&
                  !nameText.toUpperCase().contains('NATIONALITY')) {
                
                fullName = nameText;
                print('Setting fullName to: $fullName (from passport)');
                
                // Split name into first and last
                final nameParts = nameText.split(' ');
                if (nameParts.length >= 2) {
                  firstName = nameParts[0];
                  lastName = nameParts.sublist(1).join(' ');
                  print('Split names - First: $firstName, Last: $lastName');
                }
              }
            }
          }
          
          // Check for nationality
          final Match? nationalityMatch = nationalityPattern.firstMatch(text);
          if (nationalityMatch != null) {
            nationality = nationalityMatch.group(0);
          }
          
          // Check for gender
          final Match? genderMatch = genderPattern.firstMatch(text);
          if (genderMatch != null) {
            String genderText = genderMatch.group(0)!;
            if (genderText.toUpperCase() == 'M') {
              gender = 'Male';
            } else if (genderText.toUpperCase() == 'F') {
              gender = 'Female';
            } else {
              gender = genderText;
            }
          }
        }
      }
      
      // Use the extracted data
      if (fullName != null) {
        extractedData['firstName'] = firstName ?? fullName.split(' ')[0];
        extractedData['lastName'] = lastName ?? fullName.split(' ').sublist(1).join(' ');
        print('Using firstName and lastName');
      }
      
      if (nationality != null) {
        extractedData['nationality'] = nationality;
      }
      
      if (gender != null) {
        extractedData['gender'] = gender;
      }
      
      if (passportNumber != null) {
        extractedData['eidNo'] = passportNumber; // Using eidNo field for passport number
      }
      
      print('Final passport extraction - firstName: ${extractedData['firstName']}, lastName: ${extractedData['lastName']}, nationality: ${extractedData['nationality']}, gender: ${extractedData['gender']}, passportNo: ${extractedData['eidNo']}');
      
      await textRecognizer.close();
      return extractedData.isNotEmpty ? extractedData : null;
    } catch (e) {
      print('Passport data extraction error: $e');
      return null;
    }
  }

  // Extract photo from passport document
  Future<String?> extractPhotoFromPassport(File imageFile) async {
    try {
      print('=== EXTRACTING PHOTO FROM PASSPORT ===');

      // Read the image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        print('Failed to decode passport image');
        return null;
      }

      print('Passport image dimensions: ${image.width}x${image.height}');

      // Use face detection to find the photo area
      final faceDetector = GoogleMlKit.vision.faceDetector();
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await faceDetector.processImage(inputImage);

      print('Found ${faces.length} faces in passport');

      if (faces.isNotEmpty) {
        // Get the largest face (likely the main photo)
        final largestFace = faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >
          (b.boundingBox.width * b.boundingBox.height) ? a : b
        );

        print('Largest face bounding box: ${largestFace.boundingBox}');

        // Add some padding around the face
        final padding = 15.0;
        final left = (largestFace.boundingBox.left - padding).clamp(0.0, image.width.toDouble()).toInt();
        final top = (largestFace.boundingBox.top - padding).clamp(0.0, image.height.toDouble()).toInt();
        final right = (largestFace.boundingBox.right + padding).clamp(0.0, image.width.toDouble()).toInt();
        final bottom = (largestFace.boundingBox.bottom + padding).clamp(0.0, image.height.toDouble()).toInt();

        // Crop the image to the face area
        final croppedImage = img.copyCrop(
          image,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
        );

        // Make it square (common for passport photos)
        final size = (croppedImage.width > croppedImage.height) ? croppedImage.height : croppedImage.width;
        final squareImage = img.copyResizeCropSquare(croppedImage, size: size);

        // Save the cropped photo
        final tempDir = await getTemporaryDirectory();
        final photoPath = path.join(tempDir.path, 'passport_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final photoFile = File(photoPath);
        await photoFile.writeAsBytes(img.encodeJpg(squareImage, quality: 85));

        print('Passport photo extracted and saved to: $photoPath');
        print('Photo dimensions: ${squareImage.width}x${squareImage.height}');

        await faceDetector.close();
        return photoPath;
      } else {
        print('No faces detected in passport, trying alternative method...');

        // Alternative method: Look for photo in typical passport position (left side)
        final photoWidth = (image.width * 0.3).toInt(); // 30% of image width
        final photoHeight = (image.height * 0.4).toInt(); // 40% of image height
        final photoX = 20; // Left side with margin
        final photoY = (image.height * 0.1).toInt(); // Top 10% with margin

        final croppedImage = img.copyCrop(
          image,
          x: photoX,
          y: photoY,
          width: photoWidth,
          height: photoHeight,
        );

        // Save the cropped photo
        final tempDir = await getTemporaryDirectory();
        final photoPath = path.join(tempDir.path, 'passport_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final photoFile = File(photoPath);
        await photoFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 85));

        print('Passport photo extracted using alternative method: $photoPath');
        print('Photo dimensions: ${croppedImage.width}x${croppedImage.height}');

        await faceDetector.close();
        return photoPath;
      }
    } catch (e) {
      print('Passport photo extraction error: $e');
      return null;
    }
  }
}
