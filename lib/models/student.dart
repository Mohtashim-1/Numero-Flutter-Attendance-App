class Student {
  final int? id;
  final String firstName;
  final String lastName;
  final String nationality;
  final String gender;
  final String eidNo;
  final String address;
  final String cardNumber;
  final String occupation;
  final String employer;
  final String issuingPlace;
  final String bloodType;
  final String emergencyContact;
  final String email;
  final String contactType;
  final String modeOfPayment;
  final String? customer;
  final String? customerName;
  final String? employerName;
  final String? signaturePath;
  final String? photoPath;
  final String? frontCardImagePath;
  final String? backCardImagePath;
  final String? extractedPhotoPath;
  final DateTime createdAt;

  Student({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.nationality,
    required this.gender,
    required this.eidNo,
    required this.address,
    required this.cardNumber,
    required this.occupation,
    required this.employer,
    required this.issuingPlace,
    required this.bloodType,
    required this.emergencyContact,
    required this.email,
    required this.contactType,
    required this.modeOfPayment,
    this.customer,
    this.customerName,
    this.employerName,
    this.signaturePath,
    this.photoPath,
    this.frontCardImagePath,
    this.backCardImagePath,
    this.extractedPhotoPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'nationality': nationality,
      'gender': gender,
      'eid_no': eidNo,
      'address': address,
      'card_number': cardNumber,
      'occupation': occupation,
      'employer': employer,
      'issuing_place': issuingPlace,
      'blood_type': bloodType,
      'emergency_contact': emergencyContact,
      'email': email,
      'contact_type': contactType,
      'mode_of_payment': modeOfPayment,
      'customer': customer,
      'customer_name': customerName,
      'employer_name': employerName,
      'signature_path': signaturePath,
      'photo_path': photoPath,
      'front_card_image_path': frontCardImagePath,
      'back_card_image_path': backCardImagePath,
      'extracted_photo_path': extractedPhotoPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toFrappePayload() {
    return {
      'doctype': 'Student',
      'first_name': firstName,
      'last_name': lastName,
      'nationality': nationality,
      'gender': gender,
      'custom_eid_no': eidNo,
      'custom_address': address,
      'custom_card_number': cardNumber,
      'custom_occupation': occupation,
      'custom_employer': employer,
      'custom_issuing_place': issuingPlace,
      'custom_blood_type': bloodType,
      'custom_emergency_contact': emergencyContact,
      'student_email_id': email,
      'custom_contact_type': contactType,
      'custom_mode_of_payment': modeOfPayment,
      'customer': customer?.trim(),
      'customer_name': customer?.trim(),
      if (employerName != null) 'custom_employer_name': employerName,
      if (frontCardImagePath != null) 'custom_front_card_image': frontCardImagePath,
      if (backCardImagePath != null) 'custom_back_card_image': backCardImagePath,
      if (extractedPhotoPath != null) 'custom_photo': extractedPhotoPath,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      nationality: map['nationality'] ?? '',
      gender: map['gender'] ?? '',
      eidNo: map['eid_no'] ?? '',
      address: map['address'] ?? '',
      cardNumber: map['card_number'] ?? '',
      occupation: map['occupation'] ?? '',
      employer: map['employer'] ?? '',
      issuingPlace: map['issuing_place'] ?? '',
      bloodType: map['blood_type'] ?? '',
      emergencyContact: map['emergency_contact'] ?? '',
      email: map['email'] ?? '',
      contactType: map['contact_type'] ?? '',
      modeOfPayment: map['mode_of_payment'] ?? '',
      customer: map['customer'],
      customerName: map['customer_name'],
      employerName: map['employer_name'],
      signaturePath: map['signature_path'],
      photoPath: map['photo_path'],
      frontCardImagePath: map['front_card_image_path'],
      backCardImagePath: map['back_card_image_path'],
      extractedPhotoPath: map['extracted_photo_path'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Student copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? nationality,
    String? gender,
    String? eidNo,
    String? address,
    String? cardNumber,
    String? occupation,
    String? employer,
    String? issuingPlace,
    String? bloodType,
    String? emergencyContact,
    String? email,
    String? contactType,
    String? modeOfPayment,
    String? customer,
    String? customerName,
    String? employerName,
    String? signaturePath,
    String? photoPath,
    String? frontCardImagePath,
    String? backCardImagePath,
    String? extractedPhotoPath,
    DateTime? createdAt,
  }) {
    return Student(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      nationality: nationality ?? this.nationality,
      gender: gender ?? this.gender,
      eidNo: eidNo ?? this.eidNo,
      address: address ?? this.address,
      cardNumber: cardNumber ?? this.cardNumber,
      occupation: occupation ?? this.occupation,
      employer: employer ?? this.employer,
      issuingPlace: issuingPlace ?? this.issuingPlace,
      bloodType: bloodType ?? this.bloodType,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      email: email ?? this.email,
      contactType: contactType ?? this.contactType,
      modeOfPayment: modeOfPayment ?? this.modeOfPayment,
      customer: customer ?? this.customer,
      customerName: customerName ?? this.customerName,
      employerName: employerName ?? this.employerName,
      signaturePath: signaturePath ?? this.signaturePath,
      photoPath: photoPath ?? this.photoPath,
      frontCardImagePath: frontCardImagePath ?? this.frontCardImagePath,
      backCardImagePath: backCardImagePath ?? this.backCardImagePath,
      extractedPhotoPath: extractedPhotoPath ?? this.extractedPhotoPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
