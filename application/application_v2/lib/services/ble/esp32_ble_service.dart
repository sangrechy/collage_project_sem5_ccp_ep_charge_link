import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../config/esp32_ble_config.dart';
import '../../models/charging_sample.dart';
import '../../models/device_status.dart';
import '../../models/energy_data.dart';
import '../../models/history_sample.dart';
import '../../models/live_data_sample.dart';
import '../../models/power_data.dart';
import '../../models/temperature_data.dart';
import 'esp32_service.dart';

/// Real BLE implementation of [Esp32Service], talking to the physical
/// CHARGE LINK ESP32 over the protocol documented in apis.txt:
///
///   Service UUID       7f4a0001-...-123456789001
///   COMMAND (write)     7f4a0002-...-123456789001
///   RESPONSE (notify)   7f4a0003-...-123456789001
///   LIVE DATA (notify)  7f4a0004-...-123456789001
///   HISTORY (notify)    7f4a0005-...-123456789001
///
/// NOTE: the original v1 `esp32_ble_service.dart` reference file was not
/// available when this was written, so this is a fresh implementation
/// built strictly from apis.txt's documented request/response format.
class Esp32BleService implements Esp32Service {
  Esp32BleService();

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

  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<LiveDataSample> _liveDataController =
      StreamController<LiveDataSample>.broadcast();

  int _requestId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};

  // Buffers for reassembling multi-chunk history responses, keyed by
  // request id.
  final Map<int, List<HistorySample>> _historyBuffers = {};
  final Map<int, Completer<List<HistorySample>>> _historyCompleters = {};
  final Map<int, int> _historyExpectedChunks = {};
  final Map<int, int> _historyReceivedChunks = {};

  @override
  Stream<BleConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<LiveDataSample> get liveDataStream => _liveDataController.stream;

  void _emit(BleConnectionState s) {
    if (!_stateController.isClosed) _stateController.add(s);
  }

  @override
  Future<void> startScan() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _emit(BleConnectionState.bluetoothOff);
      return;
    }

    _emit(BleConnectionState.scanning);

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final matchesName = r.device.platformName == Esp32BleConfig.deviceName;
        final matchesAddress = r.device.remoteId.str.toLowerCase() ==
            Esp32BleConfig.deviceAddress.toLowerCase();
        if (matchesName || matchesAddress) {
          _device = r.device;
          _emit(BleConnectionState.deviceFound);
          stopScan();
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withNames: [Esp32BleConfig.deviceName],
      timeout: const Duration(seconds: 10),
    );
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  Future<void> connect() async {
    final device = _device;
    if (device == null) {
      _emit(BleConnectionState.connectionFailed);
      throw StateError(
        'No device found. Call startScan() and wait for deviceFound first.',
      );
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
      final service = services.firstWhere(
        (s) =>
            s.uuid.str.toLowerCase() ==
            Esp32BleConfig.serviceUuid.toLowerCase(),
        orElse: () => throw StateError('CHARGE LINK service not found.'),
      );

      _commandChar = _findChar(
        service,
        Esp32BleConfig.commandCharacteristicUuid,
        'COMMAND',
      );
      _responseChar = _findChar(
        service,
        Esp32BleConfig.responseCharacteristicUuid,
        'RESPONSE',
      );
      _liveDataChar = _findChar(
        service,
        Esp32BleConfig.liveDataCharacteristicUuid,
        'LIVE DATA',
      );
      _historyChar = _findChar(
        service,
        Esp32BleConfig.historyCharacteristicUuid,
        'HISTORY',
      );

      await _subscribe();

      _emit(BleConnectionState.connected);
    } catch (e) {
      _emit(BleConnectionState.connectionFailed);
      rethrow;
    }
  }

  BluetoothCharacteristic _findChar(
    BluetoothService service,
    String uuid,
    String label,
  ) {
    return service.characteristics.firstWhere(
      (c) => c.uuid.str.toLowerCase() == uuid.toLowerCase(),
      orElse: () => throw StateError('$label characteristic not found.'),
    );
  }

  Future<void> _subscribe() async {
    // Cancel any previous subscriptions defensively, to guarantee we never
    // hold duplicate BLE notification listeners after a reconnect.
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
        completer.complete(
          Map<String, dynamic>.from(json['data'] as Map? ?? {}),
        );
      } else {
        final message = (json['error'] is Map)
            ? (json['error']['message']?.toString() ?? 'Unknown ESP32 error')
            : 'Unknown ESP32 error';
        completer.completeError(Esp32CommandException(message));
      }
    } catch (_) {
      // Malformed JSON from the device must never crash the app.
    }
  }

  void _onLiveData(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final sample = LiveDataSample.tryParse(json);
      if (sample != null && !_liveDataController.isClosed) {
        _liveDataController.add(sample);
      }
    } catch (_) {
      // Ignore malformed / unrelated packets.
    }
  }

  void _onHistory(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final chunk = _parseHistoryChunk(json);
      if (chunk == null) return;

      final buffer = _historyBuffers.putIfAbsent(chunk.requestId, () => []);
      buffer.addAll(chunk.samples);

      _historyExpectedChunks[chunk.requestId] = chunk.totalChunks;
      _historyReceivedChunks.update(
        chunk.requestId,
        (v) => v + 1,
        ifAbsent: () => 1,
      );

      final received = _historyReceivedChunks[chunk.requestId] ?? 0;
      final expected = _historyExpectedChunks[chunk.requestId] ?? 1;

      if (received >= expected) {
        final completer = _historyCompleters.remove(chunk.requestId);
        _historyExpectedChunks.remove(chunk.requestId);
        _historyReceivedChunks.remove(chunk.requestId);
        final samples = _historyBuffers.remove(chunk.requestId) ?? [];
        if (completer != null && !completer.isCompleted) {
          completer.complete(samples);
        }
      }
    } catch (_) {
      // Ignore malformed / unrelated packets.
    }
  }

  _HistoryChunkInternal? _parseHistoryChunk(Map<String, dynamic> json) {
    if (json['type'] != 'history') return null;
    final rawSamples = json['samples'];
    if (rawSamples is! List) return null;

    final samples = <HistorySample>[];
    for (final s in rawSamples) {
      if (s is Map) {
        final parsed = HistorySample.tryParse(Map<String, dynamic>.from(s));
        if (parsed != null) samples.add(parsed);
      }
    }

    return _HistoryChunkInternal(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      totalChunks: (json['total_chunks'] as num?)?.toInt() ?? 1,
      samples: samples,
    );
  }

  Future<Map<String, dynamic>> _sendCommand(
    String command, {
    Map<String, dynamic>? params,
  }) async {
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
        throw TimeoutException('No response for "$command"');
      },
    );
  }

  @override
  Future<DeviceStatus> getDeviceStatus() async {
    final data = await _sendCommand('get_status');
    return DeviceStatus.fromJson(data);
  }

  @override
  Future<PowerData> getPowerData() async {
    final data = await _sendCommand('get_power');
    return PowerData.fromJson(data);
  }

  @override
  Future<bool> getChargingState() async {
    final data = await _sendCommand('get_charging_state');
    return data['charging'] as bool? ?? false;
  }

  @override
  Future<int> getChargingLimit() async {
    final data = await _sendCommand('get_charging_limit');
    return (data['charging_limit'] as num?)?.toInt() ?? 100;
  }

  @override
  Future<void> setChargingLimit(int percentage) async {
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError('Charging limit must be between 0 and 100.');
    }
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
  Future<ChargingSample> getChargingSample() async {
    final data = await _sendCommand('get_sample');
    return ChargingSample.fromJson(data);
  }

  @override
  Future<TemperatureData> getTemperature() async {
    final data = await _sendCommand('get_temperature');
    return TemperatureData.fromJson(data);
  }

  @override
  Future<EnergyData> getEnergyData() async {
    final data = await _sendCommand('get_energy');
    return EnergyData.fromJson(data);
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

    final payload = {
      'id': id,
      'command': 'get_history',
      'limit': limit,
    };

    await commandChar.write(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      withoutResponse: false,
    );

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _historyCompleters.remove(id);
        final partial = _historyBuffers.remove(id) ?? [];
        _historyExpectedChunks.remove(id);
        _historyReceivedChunks.remove(id);
        return partial;
      },
    );
  }

  void _cleanupAfterDisconnect() {
    _responseSub?.cancel();
    _liveDataSub?.cancel();
    _historySub?.cancel();
    _responseSub = null;
    _liveDataSub = null;
    _historySub = null;

    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('CHARGE LINK disconnected.'));
      }
    }
    _pendingRequests.clear();

    for (final c in _historyCompleters.values) {
      if (!c.isCompleted) c.complete(const []);
    }
    _historyCompleters.clear();
    _historyBuffers.clear();
    _historyExpectedChunks.clear();
    _historyReceivedChunks.clear();
  }

  @override
  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    _cleanupAfterDisconnect();
    try {
      await _device?.disconnect();
    } catch (_) {
      // Already disconnected — nothing more to do.
    }
    _emit(BleConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _liveDataController.close();
  }
}

class _HistoryChunkInternal {
  const _HistoryChunkInternal({
    required this.requestId,
    required this.totalChunks,
    required this.samples,
  });

  final int requestId;
  final int totalChunks;
  final List<HistorySample> samples;
}

class Esp32CommandException implements Exception {
  Esp32CommandException(this.message);
  final String message;

  @override
  String toString() => 'Esp32CommandException: $message';
}



