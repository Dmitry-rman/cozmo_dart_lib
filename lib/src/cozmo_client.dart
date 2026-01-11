library cozmo_client;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'cozmo_utils.dart';

class _SentPacket {
  final int seq;
  final Uint8List frameData;
  DateTime lastSentTime;
  int retries;
  _SentPacket(this.seq, this.frameData) : lastSentTime = DateTime.now(), retries = 0;
}

class CozmoClient {
  CozmoClient._internal();
  static final CozmoClient _instance = CozmoClient._internal();
  static CozmoClient get instance => _instance;

  late RawDatagramSocket _socket;
  bool _isConnected = false;
  bool _robotReady = false;
  InternetAddress? _cozmoAddress;
  
  Timer? _loopTimer;
  int _seq = 0; 
  int _lastAck = 0;      
  int _lastRemoteAck = 0; 
  
  final Queue<Uint8List> _outboundQueue = Queue<Uint8List>();
  final Map<int, _SentPacket> _inflightPackets = {};
  
  // НАСТРОЙКИ ПРОИЗВОДИТЕЛЬНОСТИ
  // Window 64 = ~2 секунды аудио в полете. Максимальная стабильность.
  static const int _WINDOW_SIZE = 64; 
  // RTO 10ms = Мгновенная реакция на потерю пакета.
  static const int _RTO_MS = 10;
  static const int _MAX_FRAME_PAYLOAD = 900; 

  StreamSubscription<RawSocketEvent>? _recvSubscription;
  
  DateTime _lastSendTime = DateTime.now();
  DateTime? _lastPacketTime;

  bool get isConnected => _isConnected;
  bool get isReady => _robotReady;
  int get outboundQueueLength => _outboundQueue.length;
  int get inflightPacketsCount => _inflightPackets.length;
  DateTime? get lastPacketTime => _lastPacketTime;
  
  // Флаг аудио (для подавления пингов контроллера)
  bool _isAudioPlaying = false;
  bool get isAudioPlaying => _isAudioPlaying;
  void setAudioPlaying(bool playing) => _isAudioPlaying = playing;

  Future<String?> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isConnected) return 'Already connected';
    try {
      print('🔌 Connecting to Cozmo...');
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket.broadcastEnabled = false;
      _cozmoAddress = InternetAddress(COZMO_IP);
      _resetState();
      _startReceiveLoop();
      _loopTimer?.cancel();
      // Тикер 5мс
      _loopTimer = Timer.periodic(const Duration(milliseconds: 5), _tick);
      await _sendConnectPacket();
      print('⏳ Waiting for handshake...');
      final start = DateTime.now();
      while (!_robotReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().difference(start) > timeout) {
          disconnect();
          return 'Timeout waiting for robot';
        }
      }
      _isConnected = true;
      print('✅ Connected (Low Level)');
      return null;
    } catch (e) {
      disconnect();
      return e.toString();
    }
  }

  void _resetState() {
    _seq = 0; _lastAck = 0; _lastRemoteAck = 0;
    _robotReady = false;
    _outboundQueue.clear(); _inflightPackets.clear();
    _lastSendTime = DateTime.now();
    _lastPacketTime = null;
    _isAudioPlaying = false;
  }

  Future<void> disconnect() async {
    _loopTimer?.cancel();
    _loopTimer = null;
    if (!_isConnected) return;
    try {
      await _stopReceiveLoop();
      await _sendDisconnectPacket();
      _socket.close();
    } catch (_) {} 
    finally {
      _isConnected = false;
      _robotReady = false;
      print('👋 Disconnected');
    }
  }

  void sendCommand(int commandId, List<int> data) {
    final w = ByteWriter();
    w.writeUint8(commandId);
    w.writeBytes(data);
    _outboundQueue.add(w.toUint8List());
    // Пытаемся отправить сразу (снижает латентность)
    if (_inflightPackets.length < _WINDOW_SIZE) _tick(null);
  }

  void sendRawPacket(List<int> packet) {
    _outboundQueue.add(Uint8List.fromList(packet));
    if (_inflightPackets.length < _WINDOW_SIZE) _tick(null);
  }

  void _tick(Timer? t) {
    if (!_isConnected) return;
    final now = DateTime.now();

    // 1. Clean Acked
    _inflightPackets.removeWhere((seq, pkt) {
       if (seq == _lastRemoteAck) return true;
       int dist = _getSeqDistance(seq, _lastRemoteAck);
       return dist > 0 && dist < 30000; 
    });

    // 2. Retransmit (Aggressive)
    if (_inflightPackets.isNotEmpty) {
      for (var pkt in _inflightPackets.values) {
        if (now.difference(pkt.lastSentTime).inMilliseconds > _RTO_MS) {
          _sendRaw(pkt.frameData);
          pkt.lastSentTime = now;
          pkt.retries++;
          // Не выходим, проверяем все потерянные пакеты сразу!
        }
      }
    }

    // 3. Send New (Unlimited Burst)
    // Убрали лимит burst. Шлем пока есть место в окне.
    while (_inflightPackets.length < _WINDOW_SIZE && _outboundQueue.isNotEmpty) {
      List<Uint8List> batch = [];
      int currentSize = 0;
      
      while (_outboundQueue.isNotEmpty) {
        final next = _outboundQueue.first;
        if (currentSize + next.length + 3 > _MAX_FRAME_PAYLOAD) break;
        batch.add(_outboundQueue.removeFirst());
        currentSize += next.length + 3;
      }
      
      if (batch.isNotEmpty) {
        _sendReliableFrame(batch);
      } else {
        break; // Если пакет слишком большой (теоретически невозможно для аудио), прерываем
      }
    }

    // 4. Keep-Alive
    if (now.difference(_lastSendTime).inMilliseconds > 1000) _sendPing();
  }

  void _sendReliableFrame(List<Uint8List> payloads) {
    _seq = (_seq + 1) & 0xFFFF; if (_seq == 0) _seq = 1;
    final frame = _encodeFrame(payloads, seq: _seq, ack: _lastAck);
    _inflightPackets[_seq] = _SentPacket(_seq, frame);
    _sendRaw(frame);
  }

  void _sendPing() {
    final w = ByteWriter();
    w.writeBytes(FRAME_ID); w.writeUint8(0x0b);
    w.writeUint16(0); w.writeUint16(0); w.writeUint16(_lastAck); 
    w.writeFloat64(DateTime.now().millisecondsSinceEpoch.toDouble());
    w.writeUint32(0); w.writeUint32(0); w.writeUint8(0);
    _sendRaw(w.toUint8List());
  }

  void _sendRaw(Uint8List data) {
    try {
      _socket.send(data, _cozmoAddress!, COZMO_PORT);
      _lastSendTime = DateTime.now();
    } catch (e) { }
  }
  
  /// Отправляет пакет напрямую, минуя надежный протокол
  void sendRaw(List<int> data) {
    final payload = Uint8List.fromList(data);
    _sendRaw(payload);
  }

  void _startReceiveLoop() {
    _recvSubscription = _socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final d = _socket.receive();
        if (d != null) _handlePacket(d.data);
      }
    });
  }

  Future<void> _stopReceiveLoop() async {
    await _recvSubscription?.cancel();
    _recvSubscription = null;
  }

  void _handlePacket(Uint8List data) {
    if (data.length < 15) return;
    if (data[0] != 0x43 || data[1] != 0x4F || data[2] != 0x5A) return;
    _lastPacketTime = DateTime.now();
    try {
      final type = data[7];
      final seq = data[10] | (data[11] << 8);
      final ack = data[12] | (data[13] << 8);
      _lastAck = seq;
      if (_isSeqNewer(ack, _lastRemoteAck)) {
        _lastRemoteAck = ack;
      }
      if (type == 0x07) {
        _parsePackets(data, 14);
      } else if (type == 0x09) {
        _parsePackets(data, 14);
      } else if (type == 0x0b) {
        _handlePingFrame(data);
      }
    } catch (_) {
      // Ignore packet parsing errors
    }
  }

  void _parsePackets(Uint8List data, int offset) {
    int pos = offset;
    while (pos < data.length) {
      if (pos + 2 > data.length) break;
      final type = data[pos++];
      final len = data[pos] | (data[pos+1] << 8);
      pos += 2;
      if (pos + len > data.length) break;
      if (type == 0x04 && len > 0) {
        final cmdId = data[pos];
        if (cmdId == 0xc9 || cmdId == 0xee) _robotReady = true;
      }
      pos += len;
    }
  }

  void _handlePingFrame(Uint8List data) {
    if (data.length < 14) return;
    double t = 0; int c = 0; int l = 0;
    try {
      if (data.length >= 30) {
        final r = ByteReader(data, 14);
        t = r.readFloat64(); c = r.readUint32(); l = r.readUint32();
      }
    } catch (_) {}
    final w = ByteWriter();
    w.writeBytes(FRAME_ID); w.writeUint8(0x0b);
    w.writeUint16(0); w.writeUint16(0); w.writeUint16(_lastAck); 
    w.writeFloat64(t); w.writeUint32(c); w.writeUint32(l); w.writeUint8(0);
    _sendRaw(w.toUint8List());
  }

  Uint8List _encodeFrame(List<Uint8List> packets, {required int seq, required int ack}) {
    final w = ByteWriter();
    w.writeBytes(FRAME_ID); w.writeUint8(0x07);
    w.writeUint16(seq); w.writeUint16(seq); w.writeUint16(ack);
    for (var p in packets) {
      w.writeUint8(0x04); w.writeUint16(p.length); w.writeBytes(p);
    }
    return w.toUint8List();
  }
  
  int _getSeqDistance(int from, int to) {
    int diff = to - from;
    if (diff < -32768) diff += 65536;
    if (diff > 32768) diff -= 65536;
    return diff;
  }
  bool _isSeqNewer(int a, int b) => ((a - b) & 0xFFFF) < 0x8000 && a != b;

  Future<void> _sendConnectPacket() async {
    final w = ByteWriter();
    w.writeBytes(FRAME_ID); w.writeUint8(0x01); w.writeUint16(1); w.writeUint16(1); w.writeUint16(1);
    _sendRaw(w.toUint8List());
  }
  Future<void> _sendDisconnectPacket() async {
    final w = ByteWriter();
    w.writeBytes(FRAME_ID); w.writeUint8(0x04); w.writeUint16(1); w.writeUint16(1); w.writeUint16(1); w.writeUint8(0);
    _sendRaw(w.toUint8List());
  }
}