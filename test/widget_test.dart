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
