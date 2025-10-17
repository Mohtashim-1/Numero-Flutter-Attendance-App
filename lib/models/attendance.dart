class Attendance {
  final int? id;
  final String studentId;
  final String studentName;
  final String eidNo;
  final String status; // 'present', 'absent', 'late'
  final String? notes;
  final String? signaturePath;
  final String? photoPath;
  final bool synced;
  final DateTime createdAt;

  Attendance({
    this.id,
    required this.studentId,
    required this.studentName,
    required this.eidNo,
    required this.status,
    this.notes,
    this.signaturePath,
    this.photoPath,
    this.synced = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'student_name': studentName,
      'eid_no': eidNo,
      'status': status,
      'notes': notes,
      'signature_path': signaturePath,
      'photo_path': photoPath,
      'synced': synced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toFrappePayload() {
    return {
      'doctype': 'Attendance',
      'student': studentId,
      'student_name': studentName,
      'eid_no': eidNo,
      'attendance_date': createdAt.toIso8601String().split('T')[0],
      'status': status,
      'notes': notes,
      'signature_path': signaturePath,
      'photo_path': photoPath,
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'],
      studentId: map['student_id'] ?? '',
      studentName: map['student_name'] ?? '',
      eidNo: map['eid_no'] ?? '',
      status: map['status'] ?? 'present',
      notes: map['notes'],
      signaturePath: map['signature_path'],
      photoPath: map['photo_path'],
      synced: (map['synced'] ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Attendance copyWith({
    int? id,
    String? studentId,
    String? studentName,
    String? eidNo,
    String? status,
    String? notes,
    String? signaturePath,
    String? photoPath,
    bool? synced,
    DateTime? createdAt,
  }) {
    return Attendance(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      eidNo: eidNo ?? this.eidNo,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      signaturePath: signaturePath ?? this.signaturePath,
      photoPath: photoPath ?? this.photoPath,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
