# Student Attendance App with Emirates ID Scanner

A Flutter application for managing student attendance with integrated Emirates ID card scanning functionality using OCR (Optical Character Recognition).

## Features

### Core Attendance Management
- Student attendance tracking
- Signature capture for attendance verification
- Offline/online synchronization
- CSV export functionality
- Filtering and search capabilities

### Emirates ID Scanner (NEW)
- Camera-based Emirates ID card scanning
- **Upload image from gallery** - Select existing photos
- **Emulator-friendly testing** - Works without camera hardware
- OCR text extraction using Google ML Kit
- **Multiple test scenarios** - Test different Emirates ID formats
- Automatic data extraction for:
  - ID Number (784-XXXX-XXXXXXX-X format)
  - Name (English and Arabic)
  - Date of Birth
  - Nationality
  - Sex/Gender
  - Issuing Date
  - Expiry Date
  - Country (United Arab Emirates)

## How to Use Emirates ID Scanner

1. **Access the Scanner**: Tap the QR code scanner icon in the main attendance list screen
2. **Choose Method**:
   - **Camera Scan**: Position the Emirates ID card within the camera frame and tap "Scan ID"
   - **Upload Image**: Tap "Upload Image" to select an existing photo from your gallery
   - **Test Mode**: Use "Test OCR (Sample Data)" for emulator testing
   - **Multiple Scenarios**: Use "Test Multiple Scenarios" to test different ID formats
3. **Ensure Good Quality**: Make sure the text is clearly visible and well-lit
4. **Process**: The app will automatically extract and process the information
5. **View Results**: The extracted information will be displayed in a dialog
6. **Check Console**: All extracted data is also printed to the console for debugging

## Emulator Support

The app is fully compatible with Android emulators and includes several fallback options:

- **Skip Camera Mode**: Allows testing without camera hardware
- **Test OCR**: Sample data testing without real images
- **Multiple Test Scenarios**: Different Emirates ID formats for comprehensive testing
- **Graceful Error Handling**: Informative dialogs when hardware is not available

## Technical Implementation

### Dependencies Added
- `camera: ^0.10.5+9` - Camera functionality
- `google_ml_kit: ^0.16.3` - OCR text recognition
- `permission_handler: ^11.0.1` - Camera and storage permissions
- `image: ^4.1.7` - Image processing
- `image_picker: ^1.0.7` - Gallery image selection

### Android Permissions
The following permissions have been added to `android/app/src/main/AndroidManifest.xml`:
- `android.permission.CAMERA`
- `android.permission.WRITE_EXTERNAL_STORAGE`
- `android.permission.READ_EXTERNAL_STORAGE`
- `android.permission.READ_MEDIA_IMAGES`
- Camera hardware features

### OCR Data Extraction
The app uses regex patterns to extract specific information from Emirates ID cards:
- ID Number: Matches pattern `784-XXXX-XXXXXXX-X`
- Dates: Recognizes DD/MM/YYYY and YYYY-MM-DD formats
- Names: Extracts text after "Name:" or "الإسم:"
- Nationality: Extracts text after "Nationality:" or "الجنسية:"
- Sex: Extracts text after "Sex:" or "الجنس"

### Test Scenarios
The app includes multiple test scenarios for comprehensive testing:
- **Scenario 1**: Standard male Emirates ID
- **Scenario 2**: Female Emirates ID with different name
- **Scenario 3**: Different male Emirates ID with varied data

## Console Output
When scanning an Emirates ID, the app prints:
1. Full extracted text from the image
2. Structured data extracted from the text
3. Test scenario information (when using test mode)
4. Any processing errors or issues

## Getting Started

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Run the app:
   ```bash
   flutter run
   ```

3. Navigate to the Emirates ID scanner using the QR code icon in the app bar

## Notes
- The scanner works best with clear, well-lit images
- Arabic text recognition is supported
- All extracted data is printed to the console for verification
- The app handles camera permissions automatically
- **Emulator Support**: If camera is not available in emulator, use "Upload Image" or "Test OCR" features
- **Fallback Mode**: App includes a fallback mode for testing without camera hardware
- **Test Scenarios**: Multiple Emirates ID formats available for testing
- **Error Handling**: Graceful degradation when hardware is not available
