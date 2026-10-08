import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';
import 'maintenance_report.dart';

enum UserRole { campusUser, maintenance, admin }

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.campusUser => 'Campus user',
    UserRole.maintenance => 'Maintenance staff',
    UserRole.admin => 'Administrator',
  };
}

class ReportNotification {
  const ReportNotification({
    required this.id,
    required this.reportId,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String reportId;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
}

class LocalStore extends ChangeNotifier {
  LocalStore._(this._preferences);

  static const _reportsKey = 'fixtrack.reports.v1';
  static const _seenNotificationsKey = 'fixtrack.seen_notifications.v1';
  static const _nameKey = 'fixtrack.profile.name';
  static const _emailKey = 'fixtrack.profile.email';
  static const _roleKey = 'fixtrack.profile.role';

  final SharedPreferences _preferences;
  List<MaintenanceReport> _reports = [];
  Set<String> _seenNotifications = {};
  String _displayName = 'Alex Morgan';
  String _email = 'alex.morgan@campus.edu';
  UserRole _role = UserRole.campusUser;
  String? _firebaseUid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;
  String? _firebaseSyncError;

  static Future<LocalStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final store = LocalStore._(preferences);
    await store._loadSavedData();
    return store;
  }

  List<MaintenanceReport> get reports {
    final sorted = List<MaintenanceReport>.of(_reports)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  String get displayName => _displayName;
  String get email => _email;
  UserRole get role => _role;
  bool get isMaintenance => _role != UserRole.campusUser;
  bool get isAdmin => _role == UserRole.admin;
  bool get isMaintenanceStaff => _role == UserRole.maintenance;
  List<MaintenanceReport> get workReports => isMaintenanceStaff
      ? _reports
            .where((report) => report.assignedToUid == _firebaseUid)
            .toList()
      : reports;
  String? get firebaseSyncError => _firebaseSyncError;

  List<ReportNotification> get notifications {
    final result = <ReportNotification>[];
    for (final report in _reports) {
      for (var index = 0; index < report.activities.length; index++) {
        final activity = report.activities[index];
        if (activity.status == null) continue;
        final id = '${report.id}_$index';
        result.add(
          ReportNotification(
            id: id,
            reportId: report.id,
            title: '${report.id} · ${activity.status!.label}',
            message: activity.message,
            createdAt: activity.createdAt,
            isRead: _seenNotifications.contains(id),
          ),
        );
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  int get unreadNotificationCount =>
      notifications.where((notification) => !notification.isRead).length;

  List<MaintenanceReport> get myReports =>
      _reports.where((report) => report.reporter == _email).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _loadSavedData() async {
    _displayName = _preferences.getString(_nameKey) ?? _displayName;
    _email = _preferences.getString(_emailKey) ?? _email;
    final roleName = _preferences.getString(_roleKey);
    if (roleName != null) {
      _role = UserRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => UserRole.campusUser,
      );
    }

    try {
      final encodedReports = _preferences.getString(_reportsKey);
      if (encodedReports == null) {
        _reports = _sampleReports();
        await _persistReports();
      } else {
        _reports = reportsFromJson(encodedReports);
      }
    } on FormatException catch (_) {
      _reports = _sampleReports();
      await _persistReports();
    }

    final seen = _preferences.getStringList(_seenNotificationsKey);
    if (seen != null) {
      _seenNotifications = seen.toSet();
    }
  }

  Future<void> connectFirebaseAccount(FirebaseAccount account) async {
    if (!FirebaseService.supportsRole(account.role)) {
      throw StateError('This account has an unsupported Firebase role.');
    }
    await _reportsSubscription?.cancel();
    _firebaseUid = account.uid;
    _displayName = account.displayName;
    _email = account.email;
    _role = UserRole.values.firstWhere(
      (role) => role.name == account.role,
      orElse: () => UserRole.campusUser,
    );
    _firebaseSyncError = null;
    final savedReports = _preferences.getString('$_reportsKey.${account.uid}');
    if (savedReports != null) {
      _reports = reportsFromJson(savedReports);
    }

    final reports = FirebaseService.firestore.collection('reports');
    final query = switch (_role) {
      UserRole.admin => reports,
      UserRole.maintenance => reports.where(
        'assignedToUid',
        isEqualTo: account.uid,
      ),
      UserRole.campusUser => reports.where('ownerUid', isEqualTo: account.uid),
    };
    final firstSnapshot = Completer<void>();
    _reportsSubscription = query.snapshots().listen(
      (snapshot) {
        final localPhotos = {
          for (final report in _reports)
            if (report.photoPath?.startsWith('data:image/') == true)
              report.id: report.photoPath!,
        };
        _reports = snapshot.docs.map((document) {
          final data = document.data();
          data['id'] = document.id;
          if (data['photoPath'] == null &&
              localPhotos.containsKey(document.id)) {
            data['photoPath'] = localPhotos[document.id];
          }
          return MaintenanceReport.fromJson(data);
        }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _firebaseSyncError = null;
        notifyListeners();
        if (!firstSnapshot.isCompleted) firstSnapshot.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        _firebaseSyncError = FirebaseService.reportSyncErrorMessage(
          error,
          uid: account.uid,
          role: account.role,
        );
        notifyListeners();
        if (!firstSnapshot.isCompleted) {
          firstSnapshot.completeError(error, stackTrace);
        }
      },
    );
    await _persistProfile();
    await firstSnapshot.future;
    notifyListeners();
  }

  Future<void> disconnectFirebaseAccount() async {
    await _reportsSubscription?.cancel();
    _reportsSubscription = null;
    _firebaseUid = null;
    _firebaseSyncError = null;
  }

  Future<List<FirebaseAccount>> pendingMaintenanceRequests() async {
    if (!isAdmin || _firebaseUid == null) {
      throw StateError('Only administrators can review access requests.');
    }
    final snapshot = await FirebaseService.firestore
        .collection('users')
        .where('requestedRole', isEqualTo: 'maintenance')
        .get();
    return snapshot.docs
        .where((document) => document.data()['role'] == 'campusUser')
        .map((document) {
          final data = document.data();
          return FirebaseAccount(
            uid: document.id,
            email: data['email'] as String? ?? '',
            displayName: data['displayName'] as String? ?? 'Maintenance staff',
            role: 'maintenance',
          );
        })
        .toList();
  }

  Future<void> approveMaintenanceRequest(String uid) async {
    if (!isAdmin || _firebaseUid == null) {
      throw StateError('Only administrators can approve access requests.');
    }
    await FirebaseService.firestore.collection('users').doc(uid).update({
      'role': 'maintenance',
      'requestedRole': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    unawaited(_reportsSubscription?.cancel());
    super.dispose();
  }

  Future<void> _persistReports() async {
    final reportsKey = _firebaseUid == null
        ? _reportsKey
        : '$_reportsKey.${_firebaseUid!}';
    final saved = await _preferences
        .setString(reportsKey, reportsToJson(_reports))
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'Saving the report locally timed out. Please try again.',
          ),
        );
    if (!saved) throw StateError('Could not save maintenance reports locally.');
  }

  Future<void> _persistProfile() async {
    final nameSaved = await _preferences.setString(_nameKey, _displayName);
    final emailSaved = await _preferences.setString(_emailKey, _email);
    final roleSaved = await _preferences.setString(_roleKey, _role.name);
    if (!nameSaved || !emailSaved || !roleSaved) {
      throw StateError('Could not save the profile locally.');
    }
  }

  Future<MaintenanceReport> createReport(
    ReportDraft draft,
  ) async {
    final title = draft.title.trim();
    final category = draft.category.trim();
    final building = draft.building.trim();
    final room = draft.room.trim();
    final description = draft.description.trim();
    final reporter = draft.reporter.trim();

    if (title.isEmpty) {
      throw const FormatException('Issue title is required.');
    }
    if (category.isEmpty) {
      throw const FormatException('Problem category is required.');
    }
    if (building.isEmpty) {
      throw const FormatException('Building is required.');
    }
    if (description.isEmpty) {
      throw const FormatException('Description is required.');
    }
    if (reporter.isEmpty) {
      throw const FormatException('Reporter email is required.');
    }

    final now = DateTime.now();
    final reportId =
        'FT-${now.year}-${now.microsecondsSinceEpoch.toString().substring(8)}';
    final firebaseUid = _firebaseUid;
    final photoPath = draft.photoBytes == null
        ? draft.photoPath
        : 'data:${draft.photoContentType ?? 'image/jpeg'};base64,'
              '${base64Encode(draft.photoBytes!)}';
    final report = MaintenanceReport(
      id: reportId,
      title: title,
      category: category,
      building: building,
      room: room,
      priority: draft.priority,
      description: description,
      reporter: reporter,
      createdAt: now,
      status: ReportStatus.pending,
      photoPath: photoPath,
      activities: [
        ReportActivity(
          message: 'Report submitted by ${_displayName.trim()}.',
          createdAt: now,
          status: ReportStatus.pending,
        ),
      ],
    );
    if (firebaseUid != null) {
      await FirebaseService.firestore
          .collection('reports')
          .doc(report.id)
          .set({
            ...report.toJson(),
            'photoPath': null,
            'ownerUid': firebaseUid,
          })
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'Saving the report timed out. Check your connection and your '
              'reports before trying again.',
            ),
          );
    }
    _reports = [report, ..._reports];
    await _persistReports();
    notifyListeners();
    return report;
  }

  Future<void> updateStatus(
    String reportId,
    ReportStatus status, {
    String? assignee,
    ReportPriority? priority,
  }) async {
    final index = _reports.indexWhere((report) => report.id == reportId);
    if (index < 0) throw StateError('Report $reportId no longer exists.');
    final current = _reports[index];
    if (_firebaseUid != null &&
        isMaintenanceStaff &&
        current.assignedToUid != _firebaseUid) {
      throw StateError('You can only update reports assigned to your account.');
    }
    var assigneeName = current.assignee;
    var assignedToUid = current.assignedToUid;
    var assignedToEmail = current.assignedToEmail;
    if ((isAdmin || _firebaseUid == null) && assignee != null) {
      if (assignee.trim().isEmpty) {
        assigneeName = null;
        assignedToUid = null;
        assignedToEmail = null;
      } else if (_firebaseUid != null) {
        final normalizedEmail = assignee.trim().toLowerCase();
        final staff = await FirebaseService.firestore
            .collection('users')
            .where('email', isEqualTo: normalizedEmail)
            .limit(1)
            .get();
        if (staff.docs.isEmpty ||
            staff.docs.first.data()['role'] != 'maintenance') {
          throw const FormatException(
            'Enter the email address of an approved maintenance staff account.',
          );
        }
        assigneeName =
            staff.docs.first.data()['displayName'] as String? ??
            normalizedEmail;
        assignedToUid = staff.docs.first.id;
        assignedToEmail = normalizedEmail;
      } else {
        assigneeName = assignee.trim();
        assignedToUid = null;
        assignedToEmail = assignee.trim();
      }
    }
    final nextPriority = isAdmin || _firebaseUid == null
        ? priority ?? current.priority
        : current.priority;
    if (current.status == status &&
        current.assignee == assigneeName &&
        current.assignedToUid == assignedToUid &&
        current.assignedToEmail == assignedToEmail &&
        current.priority == nextPriority) {
      return;
    }
    final now = DateTime.now();
    final changes = <String>[];
    if (status != current.status) {
      changes.add('Status updated to ${status.label}');
    }
    if (current.priority != nextPriority) {
      changes.add('Priority updated to ${nextPriority.label}');
    }
    if (current.assignee != assigneeName ||
        current.assignedToUid != assignedToUid ||
        current.assignedToEmail != assignedToEmail) {
      changes.add(
        assigneeName == null
            ? 'Assignment cleared'
            : 'Assigned to $assigneeName',
      );
    }
    final updatedReport = MaintenanceReport(
      id: current.id,
      title: current.title,
      category: current.category,
      building: current.building,
      room: current.room,
      priority: nextPriority,
      description: current.description,
      reporter: current.reporter,
      createdAt: current.createdAt,
      status: status,
      activities: [
        ...current.activities,
        ReportActivity(
          message: '${changes.join(' · ')}.',
          createdAt: now,
          status: status,
        ),
      ],
      photoPath: current.photoPath,
      assignee: assigneeName,
      assignedToUid: assignedToUid,
      assignedToEmail: assignedToEmail,
    );
    if (_firebaseUid != null) {
      final reference = FirebaseService.firestore
          .collection('reports')
          .doc(reportId);
      if (isAdmin) {
        await reference.update(updatedReport.toJson());
      } else {
        await reference.update({
          'status': updatedReport.status.name,
          'activities': updatedReport.activities
              .map((activity) => activity.toJson())
              .toList(),
        });
      }
    }
    _reports[index] = updatedReport;
    await _persistReports();
    notifyListeners();
  }

  Future<void> updateProfile({
    required String displayName,
    required String email,
    required UserRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (displayName.trim().isEmpty || normalizedEmail.isEmpty) {
      throw const FormatException('Name and email are required.');
    }
    if (_firebaseUid != null) {
      if (role != _role) {
        throw StateError(
          'Account roles can only be changed by a project administrator.',
        );
      }
      if (normalizedEmail != FirebaseService.auth.currentUser?.email) {
        throw StateError(
          'Change your Firebase Authentication email before updating this profile.',
        );
      }
      await FirebaseService.firestore
          .collection('users')
          .doc(_firebaseUid)
          .update({
            'displayName': displayName.trim(),
            'email': normalizedEmail,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    }
    final previousEmail = _email;
    _displayName = displayName.trim();
    _email = normalizedEmail;
    _role = role;

    if (previousEmail != normalizedEmail) {
      _reports = _reports
          .map(
            (report) => report.reporter == previousEmail
                ? MaintenanceReport(
                    id: report.id,
                    title: report.title,
                    category: report.category,
                    building: report.building,
                    room: report.room,
                    priority: report.priority,
                    description: report.description,
                    reporter: normalizedEmail,
                    createdAt: report.createdAt,
                    status: report.status,
                    activities: report.activities,
                    photoPath: report.photoPath,
                    assignee: report.assignee,
                    assignedToUid: report.assignedToUid,
                    assignedToEmail: report.assignedToEmail,
                  )
                : report,
          )
          .toList();
      await _persistReports();
    }
    await _persistProfile();
    notifyListeners();
  }

  Future<void> markNotificationsRead() async {
    _seenNotifications = notifications
        .map((notification) => notification.id)
        .toSet();
    final saved = await _preferences.setStringList(
      _seenNotificationsKey,
      _seenNotifications.toList(),
    );
    if (!saved) throw StateError('Could not save notification state locally.');
    notifyListeners();
  }

  MaintenanceReport? reportById(String id) {
    for (final report in _reports) {
      if (report.id == id) return report;
    }
    return null;
  }

  List<MaintenanceReport> _sampleReports() {
    final now = DateTime.now();
    MaintenanceReport sample({
      required String id,
      required String title,
      required String category,
      required String building,
      required String room,
      required ReportPriority priority,
      required ReportStatus status,
      required int daysAgo,
      required String description,
      required String reporter,
    }) {
      final created = now.subtract(Duration(days: daysAgo, hours: 2));
      return MaintenanceReport(
        id: id,
        title: title,
        category: category,
        building: building,
        room: room,
        priority: priority,
        description: description,
        reporter: reporter,
        createdAt: created,
        status: status,
        activities: [
          ReportActivity(
            message:
                'Report submitted by ${reporter == _email ? _displayName : 'Campus user'}.',
            createdAt: created,
            status: ReportStatus.pending,
          ),
          if (status != ReportStatus.pending)
            ReportActivity(
              message: 'Status updated to ${status.label}.',
              createdAt: created.add(const Duration(hours: 4)),
              status: status,
            ),
        ],
        assignee: status == ReportStatus.inProgress ? 'J. Santos' : null,
      );
    }

    return [
      sample(
        id: 'FT-2026-1042',
        title: 'Leaking faucet in restroom',
        category: 'Plumbing',
        building: 'CCE Building',
        room: '2nd Floor · Restroom',
        priority: ReportPriority.high,
        status: ReportStatus.inProgress,
        daysAgo: 0,
        description: 'The faucet near the east sinks is leaking continuously.',
        reporter: _email,
      ),
      sample(
        id: 'FT-2026-1038',
        title: 'Broken classroom chair',
        category: 'Furniture',
        building: 'Main Building',
        room: 'Room 204',
        priority: ReportPriority.medium,
        status: ReportStatus.underReview,
        daysAgo: 1,
        description: 'One of the chairs has a loose back and is unsafe to use.',
        reporter: _email,
      ),
      sample(
        id: 'FT-2026-1031',
        title: 'Light flickering in hallway',
        category: 'Electrical',
        building: 'Library',
        room: '3rd Floor Hallway',
        priority: ReportPriority.low,
        status: ReportStatus.resolved,
        daysAgo: 3,
        description:
            'The ceiling light flickers intermittently near the study area.',
        reporter: 'sam.lee@campus.edu',
      ),
      sample(
        id: 'FT-2026-1026',
        title: 'Damaged power outlet',
        category: 'Electrical',
        building: 'CCE Building',
        room: 'Laboratory 2',
        priority: ReportPriority.urgent,
        status: ReportStatus.pending,
        daysAgo: 2,
        description:
            'The outlet cover is cracked and exposed wiring is visible.',
        reporter: 'jamie.cruz@campus.edu',
      ),
    ];
  }
}
