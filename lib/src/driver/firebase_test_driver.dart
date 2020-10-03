import 'dart:async';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:meta/meta.dart';

class FirebaseTestDriver {
  FirebaseTestDriver({
    @required this.basePath,
    @required FirebaseDatabase db,
    bool enabled = true,
    Duration pingTimeout,
    @required String secret,
    @required TestController testController,
  })  : assert(basePath?.isNotEmpty == true),
        assert(db != null),
        assert(testController != null),
        _db = db,
        _pingTimeout = pingTimeout ?? Duration(seconds: 60),
        _secret = secret,
        _testController = testController {
    this.enabled = enabled;
    _applyStatusChange();
  }

  final String basePath;
  final FirebaseDatabase _db;
  final Duration _pingTimeout;
  final String _secret;
  final List<StreamSubscription> _subscriptions = [];
  final TestController _testController;

  Timer _connectionPingTimer;
  String _currentStatus;
  ExternalTestDriver _driver;
  bool _enabled;
  StreamController<String> _statusStreamController =
      StreamController<String>.broadcast();
  Timer _pingTimer;
  bool _running = false;

  String get currentStatus => _currentStatus;
  bool get enabled => _enabled;

  Stream<String> get statusStream => _statusStreamController?.stream;

  set enabled(bool enabled) {
    assert(enabled != null);

    if (_enabled != enabled) {
      _enabled = enabled;
      _currentStatus = _enabled ? 'connecting' : 'disconnecting';
      _statusStreamController?.add(_currentStatus);
      _applyStatusChange();
    }
  }

  void dispose() {
    enabled = false;

    _connectionPingTimer?.cancel();
    _connectionPingTimer = null;

    _currentStatus = 'disposed';

    _pingTimer?.cancel();
    _pingTimer = null;

    _statusStreamController?.add(_currentStatus);
    _statusStreamController?.close();
    _statusStreamController = null;

    _subscriptions.forEach((element) => element.cancel());
    _subscriptions.clear();
  }

  Future<void> _applyStatusChange() async {
    var testDeviceInfo = await TestDeviceInfo.initialize(null);

    _subscriptions.forEach((element) => element.cancel());
    _subscriptions.clear();

    _pingTimer?.cancel();
    _connectionPingTimer?.cancel();
    _connectionPingTimer = null;
    if (enabled == true) {
      _currentStatus = 'waiting';
      _pingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
        await _db
            .reference()
            .child(basePath)
            .child('devices')
            .child(testDeviceInfo.id)
            .set(
              DrivableDevice(
                secret: _secret,
                testDeviceInfo: testDeviceInfo,
              ).toJson(),
            );
      });

      _subscriptions.add(await _db
          .reference()
          .child(basePath)
          .child('connections')
          .child(testDeviceInfo.id)
          .child('requests')
          .onValue
          .listen((event) {
        if (_driver == null) {
          _listenForConnectionRequest(testDeviceInfo, event.snapshot.value);
        }
      }));
    } else {
      _driver = null;

      await _db
          .reference()
          .child(basePath)
          .child('connections')
          .child(testDeviceInfo.id)
          .child('requests')
          .remove();

      await _db
          .reference()
          .child(basePath)
          .child('devices')
          .child(testDeviceInfo.id)
          .remove();
    }

    _statusStreamController?.add(_currentStatus);
  }

  void _connect(ExternalTestDriver driver) {
    _driver = driver;
    _connectionPingTimer?.cancel();
    _connectionPingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      var now = DateTime.now();
      if (_driver == null ||
          now.millisecondsSinceEpoch - _driver.pingTime.millisecondsSinceEpoch >
              _pingTimeout.inMilliseconds) {
        _disconnect();
      }
    });

    _subscriptions.add(_db
        .reference()
        .child(basePath)
        .child('drivers')
        .child(driver.id)
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && _running == false) {
        _runTests(event.snapshot.value);
      }
    }));
  }

  Future<void> _disconnect() async {
    _connectionPingTimer?.cancel();
    var testDeviceInfo = await TestDeviceInfo.initialize(null);
    _driver = null;
    await _db
        .reference()
        .child(basePath)
        .child('connections')
        .child(testDeviceInfo.id)
        .child('current')
        .remove();
    _currentStatus = 'waiting';
    await _applyStatusChange();
  }

  Future<void> _listenForConnectionRequest(
    TestDeviceInfo testDeviceInfo,
    dynamic data,
  ) async {
    if (data != null) {
      await Future.forEach(data.entries, (entry) async {
        if (entry.value == true) {
          var snapshot =
              await _db.reference().child(basePath).child('drivers').once();

          if (snapshot.value != null) {
            var driver = ExternalTestDriver.fromDynamic(snapshot.value);

            var now = DateTime.now().millisecondsSinceEpoch;
            if (now - driver.pingTime.millisecondsSinceEpoch <
                    _pingTimeout.inMilliseconds &&
                driver.validateSignature(_secret)) {
              await _connect(driver);
            }
          }
        }
      });
    }
  }

  Future<void> _runTests(dynamic data) async {
    try {
      _running = true;
      var testDeviceInfo = await TestDeviceInfo.initialize(null);

      _currentStatus = 'running';
      _statusStreamController?.add(_currentStatus);

      await _db
          .reference()
          .child(basePath)
          .child('reports')
          .child(_driver.id)
          .child(testDeviceInfo.id)
          .remove();
      await _db
          .reference()
          .child(basePath)
          .child('status')
          .child(_driver.id)
          .child(testDeviceInfo.id)
          .remove();

      var tests = <Test>[];
      for (var map in data.values) {
        var test = Test.fromDynamic(map);
        if (test != null) {
          tests.add(test);
          await _db
              .reference()
              .child(basePath)
              .child('status')
              .child(_driver.id)
              .child(testDeviceInfo.id)
              .child(test.id)
              .set('pending');
        }
      }

      for (var test in tests) {
        if (test != null) {
          await _db
              .reference()
              .child(basePath)
              .child('status')
              .child(_driver.id)
              .child(testDeviceInfo.id)
              .child(test.id)
              .set('running');
          var report = await _testController.execute(
            name: test.name,
            reset: true,
            steps: test.steps,
            submitReport: true,
            suiteName: test.suiteName,
            version: test.version,
          );
          await _db
              .reference()
              .child(basePath)
              .child('status')
              .child(_driver.id)
              .child(testDeviceInfo.id)
              .child(test.id)
              .set('complete');
          await _db
              .reference()
              .child(basePath)
              .child('reports')
              .child(_driver.id)
              .child(testDeviceInfo.id)
              .child(test.id)
              .set(report.toJson());
        }
      }
    } finally {
      _running = false;
    }
  }
}
