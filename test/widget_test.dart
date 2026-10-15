import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finalproj/firebase_service.dart';
import 'package:finalproj/local_store.dart';
import 'package:finalproj/main.dart';
import 'package:finalproj/maintenance_report.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Firestore permission errors explain role profile requirements', () {
    final message = FirebaseService.signInErrorMessage(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );

    expect(message, contains('rules are deployed'));
    expect(message, contains('users/{UID}'));
    expect(message, contains('"campusUser", "maintenance", or "admin"'));
  });

  test('Firebase role validation recognizes only supported roles', () {
    expect(FirebaseService.supportsRole('campusUser'), isTrue);
    expect(FirebaseService.supportsRole('maintenance'), isTrue);
    expect(FirebaseService.supportsRole('admin'), isTrue);
    expect(FirebaseService.supportsRole('administrator'), isFalse);
    expect(FirebaseService.supportsRole(''), isFalse);
  });

  test('email validation rejects malformed addresses before Firebase auth', () {
    expect(FirebaseService.isValidEmail('staff@campus.edu'), isTrue);
    expect(FirebaseService.isValidEmail(' staff@campus.edu '), isTrue);
    expect(FirebaseService.isValidEmail('staff@campus..edu'), isFalse);
    expect(FirebaseService.isValidEmail('staff@campus'), isFalse);
    expect(FirebaseService.isValidEmail('staff campus.edu'), isFalse);
  });

  test(
    'Firebase Auth errors explain invalid email and account credentials',
    () {
      expect(
        FirebaseService.signInErrorMessage(
          FirebaseException(plugin: 'firebase_auth', code: 'invalid-email'),
        ),
        'Enter a valid email address.',
      );
      expect(
        FirebaseService.signInErrorMessage(
          FirebaseException(
            plugin: 'firebase_auth',
            code: 'invalid-credential',
          ),
        ),
        contains('registered in Firebase Authentication'),
      );
    },
  );

  test('report sync permission errors explain each role visibility rule', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    expect(
      FirebaseService.reportSyncErrorMessage(
        error,
        uid: 'admin-uid',
        role: 'admin',
      ),
      contains('Admins can read all reports.'),
    );
    expect(
      FirebaseService.reportSyncErrorMessage(
        error,
        uid: 'maintenance-uid',
        role: 'maintenance',
      ),
      contains('assignedToUid must equal this UID'),
    );
    expect(
      FirebaseService.reportSyncErrorMessage(
        error,
        uid: 'campus-uid',
        role: 'campusUser',
      ),
      contains('ownerUid must equal this UID'),
    );
  });

  testWidgets('login screen scrolls when the keyboard reduces its height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 760);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          onLogin: (role, displayName, email, password) async {},
          onRegister: (role, displayName, email, password) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('report cards fit narrow screens with long IDs', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final report = MaintenanceReport(
      id: 'FT-2026-12345678901234567890',
      title: 'A long maintenance report title',
      category: 'Plumbing',
      building: 'Main Building',
      room: 'Room 22',
      priority: ReportPriority.medium,
      description: 'Water leak under the sink.',
      reporter: 'alex.morgan@campus.edu',
      createdAt: DateTime.now(),
      status: ReportStatus.pending,
      activities: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [ReportCard(report: report, onTap: () {})],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ReportCard), findsOneWidget);
  });

  testWidgets('dashboard opens report form and submits a valid ticket', (
    tester,
  ) async {
    final store = await LocalStore.load();
    await tester.pumpWidget(MaterialApp(home: MainShell(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('FixTrack'), findsOneWidget);
    expect(find.text('Recent reports'), findsOneWidget);
    expect(find.byKey(const Key('new-report-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-report-button')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what needs attention'), findsOneWidget);

    final formScroll = find
        .descendant(
          of: find.byType(SingleChildScrollView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.ensureVisible(find.byKey(const Key('submit-report-button')));
    await tester.tap(find.byKey(const Key('submit-report-button')));
    await tester.pumpAndSettle();
    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(find.text('Choose a problem category.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('report-title-field')),
      400,
      scrollable: formScroll,
    );
    await tester.enterText(
      find.byKey(const Key('report-title-field')),
      'Broken classroom lamp',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-category-field')),
      400,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(const Key('report-category-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electrical').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('report-building-field')),
      400,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(const Key('report-building-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CCE Building').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('report-description-field')),
      400,
      scrollable: formScroll,
    );
    await tester.enterText(
      find.byKey(const Key('report-description-field')),
      'The lamp above the front row is not working.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('submit-report-button')),
      400,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(const Key('submit-report-button')));
    await tester.pumpAndSettle();

    expect(find.text('Broken classroom lamp'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(store.myReports.first.title, 'Broken classroom lamp');
  });

  testWidgets(
    'report list search has a Material ancestor from both entry points',
    (tester) async {
      final store = await LocalStore.load();
      await tester.pumpWidget(MaterialApp(home: MainShell(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('VIEW ALL →'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(MaterialApp(home: MainShell(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My reports').last);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('maintenance staff can open My reports without a widget error', (
    tester,
  ) async {
    final store = await LocalStore.load();
    await store.updateProfile(
      displayName: 'Maintenance Staff',
      email: 'staff@campus.edu',
      role: UserRole.maintenance,
    );
    await tester.pumpWidget(MaterialApp(home: MainShell(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Assigned maintenance tasks'), findsOneWidget);
    await tester.tap(find.text('My reports').first);
    await tester.pumpAndSettle();

    expect(find.text('Search reports or locations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('report creation rejects blank required fields', () async {
    final store = await LocalStore.load();

    await expectLater(
      () => store.createReport(
        const ReportDraft(
          title: '   ',
          category: 'Electrical',
          building: 'CCE Building',
          room: 'Room 101',
          priority: ReportPriority.medium,
          description: 'Need maintenance attention.',
          reporter: 'alex.morgan@campus.edu',
        ),
      ),
      throwsFormatException,
    );
  });

  test('photo evidence is saved locally with the report', () async {
    final store = await LocalStore.load();
    final photoBytes = Uint8List.fromList([1, 2, 3, 4]);

    final report = await store.createReport(
      ReportDraft(
        title: 'Broken window',
        category: 'Other',
        building: 'Main Building',
        room: 'Room 12',
        priority: ReportPriority.medium,
        description: 'The window is cracked.',
        reporter: store.email,
        photoBytes: photoBytes,
        photoContentType: 'image/jpeg',
      ),
    );

    expect(
      report.photoPath,
      'data:image/jpeg;base64,${base64Encode(photoBytes)}',
    );
    final reloadedStore = await LocalStore.load();
    expect(reloadedStore.myReports.first.photoPath, report.photoPath);
  });

  test('server UTC timestamps are converted to local report time', () {
    final serverTime = DateTime.utc(2026, 10, 8, 4, 30);
    final report = MaintenanceReport.fromJson({
      'id': 'FT-2026-12345678',
      'title': 'Broken window',
      'category': 'Other',
      'building': 'Main Building',
      'room': 'Room 12',
      'priority': 'medium',
      'description': 'The window is cracked.',
      'reporter': 'alex.morgan@campus.edu',
      'createdAt': serverTime.toIso8601String(),
      'status': 'pending',
      'activities': [
        {
          'message': 'Report submitted.',
          'createdAt': serverTime.toIso8601String(),
          'status': 'pending',
        },
      ],
    });

    expect(report.createdAt, serverTime.toLocal());
    expect(report.activities.single.createdAt, serverTime.toLocal());
    expect(
      (report.toJson()['activities'] as List<dynamic>).single['createdAt'],
      serverTime.toLocal().toIso8601String(),
    );
  });

  test(
    'report updates and notification state survive a local reload',
    () async {
      final store = await LocalStore.load();
      await store.markNotificationsRead();
      expect(store.unreadNotificationCount, 0);

      final report = await store.createReport(
        const ReportDraft(
          title: 'Loose lab table',
          category: 'Furniture',
          building: 'Science Building',
          room: 'Laboratory 1',
          priority: ReportPriority.high,
          description: 'The table leg is loose and wobbles.',
          reporter: 'alex.morgan@campus.edu',
        ),
      );
      await store.updateStatus(
        report.id,
        ReportStatus.inProgress,
        assignee: 'J. Santos',
      );

      final restoredStore = await LocalStore.load();
      final restoredReport = restoredStore.reportById(report.id);
      expect(restoredReport?.status, ReportStatus.inProgress);
      expect(restoredReport?.assignee, 'J. Santos');
      expect(restoredStore.unreadNotificationCount, 2);

      await restoredStore.markNotificationsRead();
      expect(restoredStore.unreadNotificationCount, 0);
    },
  );

  test('administrators can reprioritize and assign a report', () async {
    final store = await LocalStore.load();
    await store.updateProfile(
      displayName: 'Campus Administrator',
      email: 'admin@campus.edu',
      role: UserRole.admin,
    );
    final report = await store.createReport(
      const ReportDraft(
        title: 'Broken classroom door',
        category: 'Doors & Windows',
        building: 'Main Building',
        room: 'Room 204',
        priority: ReportPriority.low,
        description: 'The door does not close securely.',
        reporter: 'admin@campus.edu',
      ),
    );

    await store.updateStatus(
      report.id,
      ReportStatus.underReview,
      assignee: 'maintenance@campus.edu',
      priority: ReportPriority.urgent,
    );

    final updated = store.reportById(report.id)!;
    expect(updated.status, ReportStatus.underReview);
    expect(updated.priority, ReportPriority.urgent);
    expect(updated.assignee, 'maintenance@campus.edu');
    expect(updated.assignedToEmail, 'maintenance@campus.edu');
  });
}
