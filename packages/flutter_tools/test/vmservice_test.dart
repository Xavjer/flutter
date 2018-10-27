// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/vmservice.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:quiver/testing/async.dart';

import 'src/common.dart';
import 'src/context.dart';
import 'src/mocks.dart';

class MockPeer implements rpc.Peer {
  @override
  Future<dynamic> get done async {
    throw 'unexpected call to done';
  }

  @override
  bool get isClosed {
    throw 'unexpected call to isClosed';
  }

  @override
  Future<dynamic> close() async {
    throw 'unexpected call to close()';
  }

  @override
  Future<dynamic> listen() async {
    // this does get called
  }

  @override
  void registerFallback(dynamic callback(rpc.Parameters parameters)) {
    throw 'unexpected call to registerFallback';
  }

  @override
  void registerMethod(String name, Function callback) {
    // this does get called
  }

  @override
  void sendNotification(String method, [ dynamic parameters ]) {
    throw 'unexpected call to sendNotification';
  }

  bool isolatesEnabled = false;

  Future<void> _latch;
  Completer<void> _currentLatchCompleter;

  void tripLatch() {
    final Completer<void> lastCompleter = _currentLatchCompleter;
    _currentLatchCompleter = Completer<void>();
    _latch = _currentLatchCompleter.future;
    lastCompleter?.complete();
  }

  int returnedFromSendRequest = 0;

  @override
  Future<dynamic> sendRequest(String method, [ dynamic parameters ]) async {
    await _latch;
    returnedFromSendRequest += 1;
    if (method == 'getVM') {
      return <String, dynamic>{
        'type': 'VM',
        'name': 'vm',
        'architectureBits': 64,
        'targetCPU': 'x64',
        'hostCPU': '      Intel(R) Xeon(R) CPU    E5-1650 v2 @ 3.50GHz',
        'version': '2.1.0-dev.7.1.flutter-45f9462398 (Fri Oct 19 19:27:56 2018 +0000) on "linux_x64"',
        '_profilerMode': 'Dart',
        '_nativeZoneMemoryUsage': 0,
        'pid': 103707,
        'startTime': 1540426121876,
        '_embedder': 'Flutter',
        '_maxRSS': 312614912,
        '_currentRSS': 33091584,
        'isolates': isolatesEnabled ? <dynamic>[
          <String, dynamic>{
            'type': '@Isolate',
            'fixedId': true,
            'id': 'isolates/242098474',
            'name': 'main.dart:main()',
            'number': 242098474,
          },
        ] : <dynamic>[],
      };
    }
    if (method == 'getIsolate') {
      return <String, dynamic>{
        'type': 'Isolate',
        'fixedId': true,
        'id': 'isolates/242098474',
        'name': 'main.dart:main()',
        'number': 242098474,
        '_originNumber': 242098474,
        'startTime': 1540488745340,
        '_heaps': <String, dynamic>{
          'new': <String, dynamic>{
            'used': 0,
            'capacity': 0,
            'external': 0,
            'collections': 0,
            'time': 0.0,
            'avgCollectionPeriodMillis': 0.0,
          },
          'old': <String, dynamic>{
            'used': 0,
            'capacity': 0,
            'external': 0,
            'collections': 0,
            'time': 0.0,
            'avgCollectionPeriodMillis': 0.0,
          },
        },
      };
    }
    if (method == '_flutter.listViews') {
      return <String, dynamic>{
        'type': 'FlutterViewList',
        'views': <dynamic>[
          <String, dynamic>{
            'type': 'FlutterView',
            'id': '_flutterView/0x4a4c1f8',
            'isolate': <String, dynamic>{
              'type': '@Isolate',
              'fixedId': true,
              'id': 'isolates/242098474',
              'name': 'main.dart:main()',
              'number': 242098474,
            },
          },
        ],
      };
    }
    return null;
  }

  @override
  dynamic withBatch(dynamic callback()) {
    throw 'unexpected call to withBatch';
  }
}

void main() {
  final MockStdio mockStdio = MockStdio();
  group('VMService', () {
    testUsingContext('fails connection eagerly in the connect() method', () async {
      expect(
        VMService.connect(Uri.parse('http://host.invalid:9999/')),
        throwsToolExit(),
      );
    });

    testUsingContext('refreshViews', () {
      FakeAsync().run((FakeAsync time) {
        bool done = false;
        final MockPeer mockPeer = MockPeer();
        expect(mockPeer.returnedFromSendRequest, 0);
        final VMService vmService = VMService(mockPeer, null, null, const Duration(seconds: 1), null, null);
        vmService.getVM().then((void value) { done = true; });
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 0);
        time.flushMicrotasks();
        expect(done, isTrue);
        expect(mockPeer.returnedFromSendRequest, 1);

        done = false;
        mockPeer.tripLatch();
        final Future<void> ready = vmService.refreshViews(waitForViews: true);
        ready.then((void value) { done = true; });
        time.elapse(const Duration(milliseconds: 50)); // the last getVM had no isolates, so it waits 50ms, then calls getVM
        expect(mockPeer.returnedFromSendRequest, 1);

        mockPeer.tripLatch();
        expect(mockPeer.returnedFromSendRequest, 1);
        time.flushMicrotasks(); // here getVM still returns no isolates
        expect(mockPeer.returnedFromSendRequest, 2);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);

        mockPeer.tripLatch();
        expect(mockPeer.returnedFromSendRequest, 2);
        time.flushMicrotasks(); // here getVM still returns no isolates
        expect(mockPeer.returnedFromSendRequest, 3);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);

        mockPeer.tripLatch();
        expect(mockPeer.returnedFromSendRequest, 3);
        time.flushMicrotasks(); // here getVM still returns no isolates
        expect(mockPeer.returnedFromSendRequest, 4);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);

        mockPeer.tripLatch();
        expect(mockPeer.returnedFromSendRequest, 4);
        time.flushMicrotasks(); // here getVM still returns no isolates
        expect(mockPeer.returnedFromSendRequest, 5);
        const String message = 'Flutter is taking longer than expected to report its views. Still trying...\n';
        expect(mockStdio.writtenToStdout.join(''), message);
        expect(mockStdio.writtenToStderr.join(''), '');
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);

        mockPeer.isolatesEnabled = true;
        mockPeer.tripLatch();
        expect(mockPeer.returnedFromSendRequest, 5);
        time.flushMicrotasks(); // now it returns an isolate
        expect(mockPeer.returnedFromSendRequest, 6);
        mockPeer.tripLatch();
        time.flushMicrotasks(); // which gets fetched, as does the flutter view, resulting in the future returning
        expect(mockPeer.returnedFromSendRequest, 8);
        expect(done, isTrue);
        expect(mockStdio.writtenToStdout.join(''), message);
        expect(mockStdio.writtenToStderr.join(''), '');
      });
    }, overrides: <Type, Generator>{
      Logger: () => StdoutLogger(),
      Stdio: () => mockStdio,
    });
  });
}
