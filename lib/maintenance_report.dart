import 'dart:convert';
import 'dart:typed_data';

enum ReportStatus { pending, underReview, inProgress, resolved, rejected }

extension ReportStatusLabel on ReportStatus {
  String get label => switch (this) {
    ReportStatus.pending => 'Pending',
    ReportStatus.underReview => 'Under Review',
    ReportStatus.inProgress => 'In Progress',
    ReportStatus.resolved => 'Resolved',
    ReportStatus.rejected => 'Rejected / Invalid',
  };
}

enum ReportPriority { low, medium, high, urgent }

extension ReportPriorityLabel on ReportPriority {
  String get label => switch (this) {
    ReportPriority.low => 'Low',
    ReportPriority.medium => 'Medium',
    ReportPriority.high => 'High',
    ReportPriority.urgent => 'Urgent',
  };
}

class ReportActivity {
  const ReportActivity({
    required this.message,
    required this.createdAt,
    this.status,
  });

  final String message;
  final DateTime createdAt;
  final ReportStatus? status;

  Map<String, Object?> toJson() => {
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'status': status?.name,
  };

  factory ReportActivity.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    return ReportActivity(
      message: json['message'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: statusName == null
          ? null
          : ReportStatus.values.firstWhere(
              (value) => value.name == statusName,
              orElse: () => ReportStatus.pending,
            ),
    );
  }
}

class MaintenanceReport {
  const MaintenanceReport({
    required this.id,
    required this.title,
    required this.category,
    required this.building,
    required this.room,
    required this.priority,
    required this.description,
    required this.reporter,
    required this.createdAt,
    required this.status,
    required this.activities,
    this.photoPath,
    this.assignee,
    this.assignedToUid,
    this.assignedToEmail,
  });

  final String id;
  final String title;
  final String category;
  final String building;
  final String room;
  final ReportPriority priority;
  final String description;
  final String reporter;
  final DateTime createdAt;
  final ReportStatus status;
  final List<ReportActivity> activities;
  final String? photoPath;
  final String? assignee;
  final String? assignedToUid;
  final String? assignedToEmail;

  String get location => room.isEmpty ? building : '$building · $room';

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'building': building,
    'room': room,
    'priority': priority.name,
    'description': description,
    'reporter': reporter,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'activities': activities.map((activity) => activity.toJson()).toList(),
    'photoPath': photoPath,
    'assignee': assignee,
    'assignedToUid': assignedToUid,
    'assignedToEmail': assignedToEmail,
  };

  factory MaintenanceReport.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'pending';
    final priorityName = json['priority'] as String? ?? 'medium';
    return MaintenanceReport(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'Other',
      building: json['building'] as String? ?? '',
      room: json['room'] as String? ?? '',
      priority: ReportPriority.values.firstWhere(
        (value) => value.name == priorityName,
        orElse: () => ReportPriority.medium,
      ),
      description: json['description'] as String? ?? '',
      reporter: json['reporter'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: ReportStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => ReportStatus.pending,
      ),
      activities: (json['activities'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ReportActivity.fromJson)
          .toList(),
      photoPath: json['photoPath'] as String?,
      assignee: json['assignee'] as String?,
      assignedToUid: json['assignedToUid'] as String?,
      assignedToEmail: json['assignedToEmail'] as String?,
    );
  }
}

class ReportDraft {
  const ReportDraft({
    required this.title,
    required this.category,
    required this.building,
    required this.room,
    required this.priority,
    required this.description,
    required this.reporter,
    this.photoPath,
    this.photoBytes,
    this.photoContentType,
  });

  final String title;
  final String category;
  final String building;
  final String room;
  final ReportPriority priority;
  final String description;
  final String reporter;
  final String? photoPath;
  final Uint8List? photoBytes;
  final String? photoContentType;
}

String reportsToJson(List<MaintenanceReport> reports) =>
    jsonEncode(reports.map((report) => report.toJson()).toList());

List<MaintenanceReport> reportsFromJson(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Saved reports must be a JSON list.');
  }
  return decoded
      .whereType<Map<String, dynamic>>()
      .map(MaintenanceReport.fromJson)
      .toList();
}
