import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError(
      'Firebase options are not configured for this platform. '
      'Run flutterfire configure to add it.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDJRMG_4AXl9jpEbY064jrrtgzK0EXijwQ',
    appId: '1:650400661710:android:6cf103570d744c0581509f',
    messagingSenderId: '650400661710',
    projectId: 'fixtrack-campus-app',
    storageBucket: 'fixtrack-campus-app.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDJRMG_4AXl9jpEbY064jrrtgzK0EXijwQ',
    appId: '1:650400661710:web:08cb531764fe57a681509f',
    messagingSenderId: '650400661710',
    projectId: 'fixtrack-campus-app',
    authDomain: 'fixtrack-campus-app.firebaseapp.com',
    storageBucket: 'fixtrack-campus-app.firebasestorage.app',
    measurementId: 'G-M3HB9LFXZZ',
  );
}
