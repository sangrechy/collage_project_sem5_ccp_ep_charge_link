import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../models/device_status.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/session_data.dart';
import '../../models/discovered_ble_device.dart';
import 'esp32_ble_config.dart';
import 'esp32_service.dart';

class Esp32BleService implements Esp32Service {
  Esp32BleService() {
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _currentState == BleConnectionState.scanning) {
        _emit(BleConnectionState.disconnected);
      }
    });
  }

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _responseChar;
  BluetoothCharacteristic? _liveDataChar;
  BluetoothCharacteristic? _historyChar;

  StreamSubscription<List<int>>? _responseSub;
  StreamSubscription<List<int>>? _liveDataSub;
  StreamSubscription<List<int>>? _historySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;

  BleConnectionState _currentState = BleConnectionState.disconnected;

  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<LiveDataSample> _liveDataController =
      StreamController<LiveDataSample>.broadcast();

  final Map<String, DiscoveredBleDevice> _discoveredMap = {};
  final StreamController<List<DiscoveredBleDevice>> _discoveredController =
      StreamController<List<DiscoveredBleDevice>>.broadcast();

  int _requestId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};

  final Map<int, List<HistorySample>> _historyBuffers = {};
  final Map<int, Completer<List<HistorySample>>> _historyCompleters = {};
  final Map<int, int> _historyExpectedChunks = {};
  final Map<int, int> _historyReceivedChunks = {};

  @override
  Stream<BleConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<LiveDataSample> get liveDataStream => _liveDataController.stream;

  @override
  Stream<List<DiscoveredBleDevice>> get discoveredDevicesStream => _discoveredController.stream;

  @override
  List<DiscoveredBleDevice> get discoveredDevices {
    final list = _discoveredMap.values.toList();
    list.sort((a, b) {
      if (a.isChargeLink && !b.isChargeLink) return -1;
      if (!a.isChargeLink && b.isChargeLink) return 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  @override
  String? get connectedDeviceName => _device?.platformName.isNotEmpty == true
      ? _device!.platformName
      : _discoveredMap[_device?.remoteId.str]?.name ?? 'Charge Link';

  @override
  String? get connectedDeviceId => _device?.remoteId.str;

  void _emit(BleConnectionState s) {
    _currentState = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _emitDiscovered() {
    if (!_discoveredController.isClosed) {
      _discoveredController.add(discoveredDevices);
    }
  }

  @override
  Future<void> startScan() async {
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);

    // Check Bluetooth adapter state and prompt to turn on if off
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
        await Future.delayed(const Duration(milliseconds: 600));
        adapterState = await FlutterBluePlus.adapterState.first;
      } catch (_) {}
    }

    if (adapterState != BluetoothAdapterState.on) {
      _emit(BleConnectionState.bluetoothOff);
      return;
    }

    _emit(BleConnectionState.scanning);
    _discoveredMap.clear();

    // Query bonded/paired devices already recognized by Android OS
    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final b in bonded) {
        final dev = DiscoveredBleDevice.fromBluetoothDevice(
          b,
          targetServiceUuid: Esp32BleConfig.serviceUuid,
        );
        _discoveredMap[dev.id] = dev;
      }
    } catch (_) {}

    // Query currently connected system devices
    try {
      final connected = await FlutterBluePlus.systemDevices([]);
      for (final c in connected) {
        final dev = DiscoveredBleDevice.fromBluetoothDevice(
          c,
          targetServiceUuid: Esp32BleConfig.serviceUuid,
        );
        _discoveredMap[dev.id] = dev;
      }
    } catch (_) {}

    _emitDiscovered();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      bool foundTarget = false;
      for (final r in results) {
        final dev = DiscoveredBleDevice.fromScanResult(
          r,
          targetServiceUuid: Esp32BleConfig.serviceUuid,
        );
        _discoveredMap[dev.id] = dev;

        if (dev.isChargeLink && !foundTarget && _device == null) {
          _device = dev.device;
          foundTarget = true;
          _emit(BleConnectionState.deviceFound);
        }
      }
      _emitDiscovered();
    }, onError: (_) {});

    // Start scan without requiring GPS Location services:
    // androidCheckLocationServices: false -> prevents failure on Android 12+ with Location toggle off
    // androidUsesFineLocation: false -> pairs with neverForLocation in AndroidManifest.xml
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: false,
      androidCheckLocationServices: false,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  @override
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  Future<void> connectToDevice(DiscoveredBleDevice device) async {
    _device = device.device;
    await stopScan();
    await connect();
  }

  @override
  Future<void> connect() async {
    final device = _device;
    if (device == null) {
      _emit(BleConnectionState.connectionFailed);
      throw StateError('No device selected. Scan and choose your Charge Link device.');
    }

    _emit(BleConnectionState.connecting);

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: Esp32BleConfig.connectTimeout,
        autoConnect: false,
      );

      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _cleanupAfterDisconnect();
          _emit(BleConnectionState.disconnected);
        }
      });

      final services = await device.discoverServices();
      final targetCleanUuid = Esp32BleConfig.serviceUuid.replaceAll('-', '').toLowerCase();
      final service = services.firstWhere(
        (s) => s.uuid.str.replaceAll('-', '').toLowerCase() == targetCleanUuid,
        orElse: () => throw StateError('CHARGE LINK service ($targetCleanUuid) not found.'),
      );

      _commandChar = _findChar(service, Esp32BleConfig.commandCharacteristicUuid, 'COMMAND');
      _responseChar = _findChar(service, Esp32BleConfig.responseCharacteristicUuid, 'RESPONSE');
      _liveDataChar = _findChar(service, Esp32BleConfig.liveDataCharacteristicUuid, 'LIVE DATA');
      _historyChar = _findChar(service, Esp32BleConfig.historyCharacteristicUuid, 'HISTORY');

      await _subscribe();
      _emit(BleConnectionState.connected);
    } catch (e) {
      _emit(BleConnectionState.connectionFailed);
      rethrow;
    }
  }

  BluetoothCharacteristic _findChar(BluetoothService service, String uuid, String label) {
    final clean = uuid.replaceAll('-', '').toLowerCase();
    return service.characteristics.firstWhere(
      (c) => c.uuid.str.replaceAll('-', '').toLowerCase() == clean,
      orElse: () => throw StateError('$label characteristic not found.'),
    );
  }

  Future<void> _subscribe() async {
    await _responseSub?.cancel();
    await _liveDataSub?.cancel();
    await _historySub?.cancel();

    await _responseChar!.setNotifyValue(true);
    _responseSub = _responseChar!.lastValueStream.listen(_onResponse);

    await _liveDataChar!.setNotifyValue(true);
    _liveDataSub = _liveDataChar!.lastValueStream.listen(_onLiveData);

    await _historyChar!.setNotifyValue(true);
    _historySub = _historyChar!.lastValueStream.listen(_onHistory);
  }

  void _onResponse(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final id = (json['id'] as num?)?.toInt();
      if (id == null) return;

      final completer = _pendingRequests.remove(id);
      if (completer == null || completer.isCompleted) return;

      if (json['success'] == true) {
        completer.complete(Map<String, dynamic>.from(json['data'] as Map? ?? {}));
      } else {
        final message = (json['error'] is Map)
            ? (json['error']['message']?.toString() ?? 'ESP32 error')
            : 'ESP32 error';
        completer.completeError(Exception(message));
      }
    } catch (_) {}
  }

  void _onLiveData(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final sample = LiveDataSample.tryParse(json);
      if (sample != null && !_liveDataController.isClosed) {
        _liveDataController.add(sample);
      }
    } catch (_) {}
  }

  void _onHistory(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (json['type'] != 'history') return;

      final requestId = (json['request_id'] as num?)?.toInt() ?? 0;
      final totalChunks = (json['total_chunks'] as num?)?.toInt() ?? 1;
      final rawSamples = json['samples'] as List? ?? [];

      final buffer = _historyBuffers.putIfAbsent(requestId, () => []);
      for (final s in rawSamples) {
        if (s is Map) {
          final sample = HistorySample.tryParse(Map<String, dynamic>.from(s));
          if (sample != null) buffer.add(sample);
        }
      }

      _historyExpectedChunks[requestId] = totalChunks;
      _historyReceivedChunks.update(requestId, (v) => v + 1, ifAbsent: () => 1);

      final received = _historyReceivedChunks[requestId] ?? 0;
      if (received >= totalChunks) {
        final completer = _historyCompleters.remove(requestId);
        _historyExpectedChunks.remove(requestId);
        _historyReceivedChunks.remove(requestId);
        final samples = _historyBuffers.remove(requestId) ?? [];
        if (completer != null && !completer.isCompleted) {
          completer.complete(samples);
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _sendCommand(String command, {Map<String, dynamic>? params}) async {
    final commandChar = _commandChar;
    if (commandChar == null) {
      throw StateError('Not connected to CHARGE LINK.');
    }

    final id = ++_requestId;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final payload = <String, dynamic>{
      'id': id,
      'command': command,
      ...?params,
    };

    try {
      await commandChar.write(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        withoutResponse: false,
      );
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }

    return completer.future.timeout(
      Esp32BleConfig.commandTimeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('No response for command "$command"');
      },
    );
  }

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    final data = await _sendCommand('get_status');
    return DeviceStatus.fromJson(data);
  }

  @override
  Future<SessionData> getSession() async {
    final data = await _sendCommand('get_session');
    return SessionData.fromJson(data);
  }

  @override
  Future<void> clearSession() async {
    await _sendCommand('clear_session');
  }

  @override
  Future<bool> getChargingState() async {
    final data = await _sendCommand('get_charging_state');
    return data['charging'] as bool? ?? false;
  }

  @override
  Future<int> getChargingLimit() async {
    final data = await _sendCommand('get_charging_limit');
    // Firmware returns {"percentage": 80}
    return (data['percentage'] as num?)?.toInt() ??
        (data['charging_limit'] as num?)?.toInt() ??
        80;
  }

  @override
  Future<void> setChargingLimit(int percentage) async {
    await _sendCommand('set_charging_limit', params: {'percentage': percentage});
  }

  @override
  Future<void> startCharging() async {
    await _sendCommand('start_charging');
  }

  @override
  Future<void> stopCharging() async {
    await _sendCommand('stop_charging');
  }

  @override
  Future<List<HistorySample>> getHistory({int limit = 100}) async {
    final id = ++_requestId;
    final completer = Completer<List<HistorySample>>();
    _historyCompleters[id] = completer;
    _historyBuffers[id] = [];

    final commandChar = _commandChar;
    if (commandChar == null) {
      throw StateError('Not connected to CHARGE LINK.');
    }

    final payload = <String, dynamic>{
      'id': id,
      'command': 'get_history',
      'limit': limit,
    };

    try {
      await commandChar.write(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        withoutResponse: false,
      );
    } catch (e) {
      _historyCompleters.remove(id);
      _historyBuffers.remove(id);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        final buffer = _historyBuffers.remove(id) ?? [];
        _historyCompleters.remove(id);
        _historyExpectedChunks.remove(id);
        _historyReceivedChunks.remove(id);
        return buffer;
      },
    );
  }

  @override
  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (_) {}
    _cleanupAfterDisconnect();
    _emit(BleConnectionState.disconnected);
  }

  void _cleanupAfterDisconnect() {
    _responseSub?.cancel();
    _liveDataSub?.cancel();
    _historySub?.cancel();
    _commandChar = null;
    _responseChar = null;
    _liveDataChar = null;
    _historyChar = null;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Disconnected during request'));
      }
    }
    _pendingRequests.clear();
  }

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _liveDataController.close();
    _discoveredController.close();
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _connectionSub?.cancel();
  }
}
