# FixTrack

FixTrack is a Flutter campus-facility maintenance reporting app. Campus users
can submit and track reports with a location, priority, description, and optional
photo. Administrators can review all reports, reprioritize them, assign them to
approved maintenance accounts, and approve maintenance access requests.
Maintenance staff see only reports assigned to their account and can update
their progress.

## Run the app

From this directory, run:

```sh
flutter pub get
flutter run
```

The app is configured for the `fixtrack-campus-app` Firebase project on Android
and Web. Enable Email/Password sign-in in Firebase Authentication, create the
Cloud Firestore database, and enable Firebase Storage before using cloud
features. On a platform where Firebase has not been configured, the app can
still be used in local demo mode; local data is not shared between devices.

## Roles and first-time setup

- Campus accounts can register and submit reports immediately.
- Maintenance access is requested at registration. An administrator approves
  the request from the administrator dashboard.
- Admin access is never self-requested or self-granted. A project owner must
  create the account in Firebase Authentication, then create its Firestore
  profile at `users/{authentication UID}` with `role: "admin"`. Use the
  account's Authentication UID, and do this only for a trusted account.
- If admin sign-in shows `cloud_firestore/permission-denied`, ask the Firebase
  project owner to deploy the Firestore rules (see below) and confirm the
  signed-in account's `users/{UID}` profile has `role: "admin"`.
- An administrator assigns a report using the email address of an approved
  maintenance account. Maintenance staff sign in using the **Maintenance**
  login and see their assigned queue. Until assignment, reports are visible to
  the reporting campus account and administrators; after assignment, the
  assigned maintenance account can also read and update that report.

## Deploy Firebase rules

Install and sign in to the Firebase CLI, then run these commands from this
directory:

```sh
firebase login
firebase deploy --only firestore:rules,storage
```

The deployment uses `firestore.rules` and `storage.rules`. New photo evidence
is stored only in the app's local report data and is not uploaded to Firebase
or shared with other devices. Keep photos at or below 3 MB so they fit in the
device's local storage. Firebase Storage is used only to display photos from
older reports that were uploaded by a previous version of the app.

Existing locally saved reports are not migrated to Firestore, and a photo path
saved by an older app version is still device-local. Locally stored photo
evidence is saved with the report and remains available on that device.
