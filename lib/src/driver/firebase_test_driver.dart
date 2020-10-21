import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:convert/convert.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

class FirebaseTestDriver {
  FirebaseTestDriver({
    @required this.basePath,
    @required FirebaseDatabase db,
    this.deviceId,
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
  static final Logger _logger = Logger('FirebaseTestDriver');

  final String basePath;
  final String deviceId;

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
      _setCurrentStatus(
          _enabled ? TestDeviceStatus.available : TestDeviceStatus.offline);
      _applyStatusChange();
    }
  }

  void dispose() {
    enabled = false;

    _connectionPingTimer?.cancel();
    _connectionPingTimer = null;

    _setCurrentStatus(TestDeviceStatus.offline);

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
      _setCurrentStatus(TestDeviceStatus.available);
      _pingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
        var testDeviceInfo = await TestDeviceInfo.initialize(null);
        await _db
            .reference()
            .child(basePath)
            .child('devices')
            .child(_getDeviceId(testDeviceInfo))
            .set(
              DrivableDevice(
                driverId: _driver?.id,
                driverName: _driver?.name,
                id: _getDeviceId(testDeviceInfo),
                secret: _secret,
                status: _testController.runningTest == true
                    ? TestDeviceStatus.running
                    : _currentStatus,
                testDeviceInfo: testDeviceInfo,
              ).toJson(),
            );
      });

      _subscriptions.add(await _db
          .reference()
          .child(basePath)
          .child('connections')
          .child(_getDeviceId(testDeviceInfo))
          .onValue
          .listen((event) async {
        if (_driver == null) {
          var map = event.snapshot.value;

          for (var entry in (map?.entries ?? [])) {
            try {
              var driver = ExternalTestDriver.fromDynamic(entry.value);
              if (driver.validateSignature(_secret)) {
                var timestamp = driver.pingTime;
                if (DateTime.now().millisecondsSinceEpoch -
                        timestamp.millisecondsSinceEpoch <=
                    _pingTimeout.inMilliseconds) {
                  await _connect(driver);

                  break;
                }
              }
            } catch (e) {
              // no-op; bad request
            }
          }
        }
      }));
    } else {
      _driver = null;

      await _db
          .reference()
          .child(basePath)
          .child('connections')
          .child(_getDeviceId(testDeviceInfo))
          .child('requests')
          .remove();

      await _db
          .reference()
          .child(basePath)
          .child('devices')
          .child(_getDeviceId(testDeviceInfo))
          .remove();
    }

    _statusStreamController?.add(_currentStatus);
  }

  Future<void> _connect(ExternalTestDriver driver) async {
    var testDeviceInfo = await TestDeviceInfo.initialize(null);
    _setCurrentStatus(TestDeviceStatus.connected);
    _driver = driver;
    _connectionPingTimer?.cancel();
    _connectionPingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      var now = DateTime.now();

      if (_driver == null) {
        await _disconnect();
      } else {
        try {
          if (!_driver.validateSignature(_secret) ||
              now.millisecondsSinceEpoch -
                      _driver.pingTime.millisecondsSinceEpoch >
                  _pingTimeout.inMilliseconds) {
            await _disconnect();
          }
        } catch (e) {
          await _disconnect();
        }
      }
    });

    _subscriptions.add(_db
        .reference()
        .child(basePath)
        .child('connections')
        .child(_getDeviceId(testDeviceInfo))
        .child(driver.id)
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        _driver = ExternalTestDriver.fromDynamic(event.snapshot.value);
      } else {
        _driver = null;
      }

      if (_driver == null) {
        _disconnect();
      }
    }));

    _subscriptions.add(_db
        .reference()
        .child(basePath)
        .child('driver_tests')
        .child(driver.id)
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && _running == false) {
        var request = DriverTestRequest.fromDynamic(event.snapshot.value);
        if (DateTime.now().millisecondsSinceEpoch -
                    request.timestamp.millisecondsSinceEpoch <
                _pingTimeout.inMilliseconds &&
            request.validateSignature(_secret)) {
          _runTests(event.snapshot.key, request);
        }
      }
    }));
  }

  Future<void> _disconnect() async {
    _connectionPingTimer?.cancel();
    _connectionPingTimer = null;
    _driver = null;
    _setCurrentStatus(TestDeviceStatus.available);
    await _applyStatusChange();
  }

  String _getDeviceId(TestDeviceInfo testDeviceInfo) =>
      deviceId ?? testDeviceInfo.id;

  Future<void> _runTests(
    String driverId,
    DriverTestRequest request,
  ) async {
    try {
      _running = true;
      var testDeviceInfo = await TestDeviceInfo.initialize(null);

      var tests = <Test>[];
      for (var test in request.tests) {
        if (test != null) {
          tests.add(test);
          await _db
              .reference()
              .child(basePath)
              .child('driven_test')
              .child(driverId)
              .child('status')
              .child(_getDeviceId(testDeviceInfo))
              .child(hex.encode(utf8.encode(test.id)))
              .set(
                DrivenTestStatus.fromTest(
                  deviceInfo: testDeviceInfo,
                  driverId: driverId,
                  test: test,
                  pending: true,
                ).toJson(),
              );
        }
      }

      for (var test in tests) {
        if (test != null) {
          await _db
              .reference()
              .child(basePath)
              .child('driven_test')
              .child(driverId)
              .child('status')
              .child(_getDeviceId(testDeviceInfo))
              .child(hex.encode(utf8.encode(test.id)))
              .set(
                DrivenTestStatus.fromTest(
                  deviceInfo: testDeviceInfo,
                  driverId: driverId,
                  running: true,
                  test: test,
                ).toJson(),
              );

          var total = test.steps.length;
          var current = 0.0;
          var report = TestReport(
            deviceInfo: testDeviceInfo,
            id: test.id,
            name: test.name,
            suiteName: test.suiteName,
            version: test.version,
          );
          var subscription = report.stepStream.listen(
            (step) {
              current += 1;
              _db
                  .reference()
                  .child(basePath)
                  .child('driven_test')
                  .child(driverId)
                  .child('status')
                  .child(_getDeviceId(testDeviceInfo))
                  .child(hex.encode(utf8.encode(test.id)))
                  .set(
                    DrivenTestStatus.fromTest(
                      deviceInfo: testDeviceInfo,
                      driverId: driverId,
                      progress: min(1, current / max(total, 1)),
                      running: true,
                      status: step.id,
                      test: test,
                    ).toJson(),
                  );
            },
          );

          try {
            await _testController.execute(
              name: test.name,
              report: report,
              reset: true,
              steps: test.steps,
              submitReport: true,
              suiteName: test.suiteName,
              version: test.version,
            );
          } finally {
            await subscription.cancel();
          }
          await _db
              .reference()
              .child(basePath)
              .child('driven_test')
              .child(driverId)
              .child('status')
              .child(_getDeviceId(testDeviceInfo))
              .child(hex.encode(utf8.encode(test.id)))
              .set(
                DrivenTestStatus.fromTest(
                  complete: true,
                  deviceInfo: testDeviceInfo,
                  driverId: driverId,
                  progress: 1.0,
                  test: test,
                  testPassed: report.success == true,
                ).toJson(),
              );
          await _db
              .reference()
              .child(basePath)
              .child('driven_test')
              .child(driverId)
              .child('reports')
              .child(_getDeviceId(testDeviceInfo))
              .child(hex.encode(utf8.encode(test.id)))
              .set(report.toJson());
        }
      }
    } finally {
      _running = false;
      _setCurrentStatus(_driver == null ? 'available' : 'connected');
    }
  }

  void _setCurrentStatus(String status) {
    _currentStatus = status;
    _statusStreamController.add(status);
    _logger.finer('[FirebaseTestDriver] -- status: [$status]');
  }
}
