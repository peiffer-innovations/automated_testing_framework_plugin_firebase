# automated_testing_framework_plugin_firebase

## Table of Contents

* [Introduction](#introduction)
* [Quick Start](#quick-start)
* [Additional Test Steps](https://github.com/peiffer-innovations/automated_testing_framework_plugin_firebase/blob/main/documentation/STEPS.md)
* [Supported Platforms](#supported-platforms)


## Introduction

The first step in the process is to make sure your app is setup and registered with Google's Firestore console and the appropriate files have been added to your application's manifests.  For a great guide on this process, see [https://firebase.flutter.dev/docs/overview](https://firebase.flutter.dev/docs/overview).

In addition to Firestore this also supports Firebase Storage for the screenshots.  If you would like to utilize that, follow the Firebase Storage instructions in the previous link.

As a note, the example app is a fully functioning app on Firestore and Firebase Storage, but you must add in your own project.  You don't get to use mine at my cost...  :)


## Quick Start

In addition to the Firestore and Firebase Storage metadata files, the example also requires a file under `assets/login.json` that follows this structure:

```
{
  "username": "username-goes-here",
  "password": "password-goes-here"
}
```

This is used to log in to Firebase using the email / password mode and is designed to encourage good test behavior by starting with an authenticated mode rather than a "world read / world write" mode that can be dangerous for your data.

Once that file, plus the Firestore metadata files, is provided you should have a working example that can read, write, and report out tests.


## Supported Platforms

This has been tested on Android and iOS.
