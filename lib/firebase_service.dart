import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

class FirebaseAccount {
  const FirebaseAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
  });

  final String uid;
  final String email;
  final String displayName;
  final String role;
}

class FirebaseService {
  static bool _initialized = false;
  static const _supportedRoles = {'campusUser', 'maintenance', 'admin'};

  static bool get isReady => _initialized;

  static bool supportsRole(String role) => _supportedRoles.contains(role);

  static bool isValidEmail(String email) => RegExp(
    r"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$",
    caseSensitive: false,
  ).hasMatch(email.trim());

  static String get setupMessage {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return 'Firebase is configured for Android and Web only. Run '
          '`flutterfire configure --project=fixtrack-campus-app '
          '--platforms=android,ios,web` to add this platform.';
    }
    return 'Firebase is not initialized. Check the Firebase configuration '
        'and try restarting the app.';
  }

  static String signInErrorMessage(Object error) {
    if (error is FirebaseException && error.plugin == 'firebase_auth') {
      return switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'The email or password is incorrect. Make sure you use an account '
              'registered in Firebase Authentication.',
        'user-disabled' => 'This Firebase Authentication account is disabled.',
        _ => error.message ?? error.toString(),
      };
    }
    if (error is FirebaseException &&
        error.plugin == 'cloud_firestore' &&
        error.code == 'permission-denied') {
      return 'Firestore denied access while loading this account. Confirm '
          'the rules are deployed and this account has a users/{UID} profile '
          'whose role matches its access: "campusUser", "maintenance", or '
          '"admin".';
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }

  static String reportSyncErrorMessage(
    Object error, {
    required String uid,
    required String role,
  }) {
    if (error is FirebaseException &&
        error.plugin == 'cloud_firestore' &&
        error.code == 'permission-denied') {
      final access = switch (role) {
        'admin' => 'Admins can read all reports.',
        'maintenance' =>
          'Maintenance can read only reports assigned to this account '
              '(assignedToUid must equal this UID).',
        'campusUser' =>
          'Campus users can read only reports they submitted '
              '(ownerUid must equal this UID).',
        _ => 'This account has an unsupported role.',
      };
      return 'Firestore denied the $role report query. Confirm the deployed '
          'rules and users/$uid role. $access';
    }
    return 'Could not sync reports with Firebase: $error';
  }

  static Future<void> initializeIfConfigured() async {
    if (_initialized) return;
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.projectId.trim().isEmpty) return;

    await Firebase.initializeApp(options: options);
    _initialized = true;
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;

  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static FirebaseStorage get storage => FirebaseStorage.instance;

  static Future<FirebaseAccount> signIn({
    required String email,
    required String password,
    required String requestedRole,
  }) async {
    if (!isReady) {
      throw StateError('Firebase is not initialized on this platform.');
    }
    if (!supportsRole(requestedRole)) {
      throw ArgumentError.value(requestedRole, 'requestedRole');
    }

    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = credential.user;
    if (user == null || user.email == null) {
      throw StateError(
        'Firebase Authentication did not return a user account.',
      );
    }

    final userRef = firestore.collection('users').doc(user.uid);
    late final DocumentSnapshot<Map<String, dynamic>> userSnapshot;
    try {
      userSnapshot = await userRef.get();
    } on FirebaseException catch (error) {
      await auth.signOut();
      throw StateError(signInErrorMessage(error));
    }
    final profile = userSnapshot.data();
    if (profile == null) {
      if (requestedRole != 'campusUser') {
        await auth.signOut();
        throw StateError(
          requestedRole == 'admin'
              ? 'This account has no assigned admin role. Ask the Firebase project owner to assign it.'
              : 'This account has no maintenance profile or approved maintenance access request.',
        );
      }
      final displayName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email!.split('@').first;
      try {
        await userRef.set({
          'displayName': displayName,
          'email': user.email!.toLowerCase(),
          'role': 'campusUser',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        await auth.signOut();
        throw StateError(signInErrorMessage(error));
      }
      return FirebaseAccount(
        uid: user.uid,
        email: user.email!.toLowerCase(),
        displayName: displayName,
        role: 'campusUser',
      );
    }

    final role = profile['role'];
    if (role is! String || !supportsRole(role)) {
      await auth.signOut();
      throw StateError(
        'This account has no supported Firebase role. Ask the project owner '
        'to set its users/${user.uid} profile role to campusUser, maintenance, or admin.',
      );
    }
    if (role != requestedRole) {
      await auth.signOut();
      throw StateError(
        profile['requestedRole'] == 'maintenance'
            ? 'This account is waiting for admin approval.'
            : role == 'maintenance'
            ? 'This account is assigned to Maintenance. Select the Maintenance login.'
            : role == 'admin'
            ? 'This account is assigned to Admin. Select the Admin login.'
            : 'This account is assigned to Campus user. Select the Campus user login.',
      );
    }

    return FirebaseAccount(
      uid: user.uid,
      email: user.email!.toLowerCase(),
      displayName:
          profile['displayName'] as String? ??
          user.displayName ??
          user.email!.split('@').first,
      role: role,
    );
  }

  static Future<FirebaseAccount> register({
    required String displayName,
    required String email,
    required String password,
    required String requestedRole,
  }) async {
    if (!isReady) {
      throw StateError('Firebase is not initialized on this platform.');
    }
    if (requestedRole != 'campusUser' && requestedRole != 'maintenance') {
      throw ArgumentError.value(requestedRole, 'requestedRole');
    }

    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = credential.user;
    if (user == null || user.email == null) {
      throw StateError(
        'Firebase Authentication did not return the newly created account.',
      );
    }

    final name = displayName.trim();
    await user.updateDisplayName(name);
    try {
      await firestore.collection('users').doc(user.uid).set({
        'displayName': name,
        'email': user.email!.toLowerCase(),
        'role': 'campusUser',
        'requestedRole': requestedRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await user.delete();
      rethrow;
    }

    final account = FirebaseAccount(
      uid: user.uid,
      email: user.email!.toLowerCase(),
      displayName: name,
      role: 'campusUser',
    );
    if (requestedRole == 'maintenance') {
      await auth.signOut();
    }
    return account;
  }
}
