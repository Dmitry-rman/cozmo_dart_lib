# Практическое руководство по реализации пакетной архитектуры Cozmo

## 📋 Содержание

1. [Настройка среды разработки](#настройка-среды-разработки)
2. [Реализация сетевого слоя](#реализация-сетевого-слоя)
3. [Создание AnimationController](#создание-animationcontroller)
4. [Аудио подсистема](#аудио-подсистема)
5. [Обработка изображений](#обработка-изображений)
6. [Интеграция и тестирование](#интеграция-и-тестирование)

---

## Настройка среды разработки

### 1. Структура проекта

Рекомендуемая структура проекта для работы с Cozmo:

```
lib/
├── cozmo/
│   ├── core/
│   │   ├── connection.dart          # UDP соединение
│   │   ├── protocol.dart            # Протокол фреймов
│   │   └── packets.dart            # Определения пакетов
│   ├── audio/
│   │   ├── audio_encoder.dart       # Кодирование аудио
│   │   ├── audio_player.dart        # Воспроизведение
│   │   └── ulaw_encoder.dart      # u-law кодек
│   ├── video/
│   │   ├── image_encoder.dart      # RLE кодирование
│   │   ├── simple_image.dart       # Простые изображения
│   │   └── image_cache.dart       # Кэширование
│   ├── animation/
│   │   ├── animation_controller.dart # Координация
│   │   ├── emotion_player.dart      # Эмоции
│   │   └── trigger_system.dart     # Триггеры анимаций
│   └── client.dart               # Основной клиент
└── examples/
    ├── basic_audio.dart            # Пример воспроизведения
    ├── image_display.dart          # Пример изображений
    └── combined_scene.dart         # Комплексная сцена
```

### 2. Зависимости

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Для работы с аудио
  flutter_sound: ^9.2.13
  path_provider: ^2.1.1
  
  # Для работы с изображениями
  flutter_image: ^4.1.5
  
  # Для сетевого взаимодействия
  udp: ^5.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
```

---

## Реализация сетевого слоя

### 1. Базовый UDP клиент

```dart
// lib/cozmo/core/connection.dart
import 'dart:io';
import 'dart:typed_data';

class CozmoConnection {
  late RawDatagramSocket _socket;
  InternetAddress? _cozmoAddress;
  bool _isConnected = false;
  
  final StreamController<Uint8List> _incomingController = 
      StreamController<Uint8List>.broadcast();
  
  Stream<Uint8List> get incoming => _incomingController.stream;
  
  Future<String?> connect({String? cozmoIP}) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket.broadcastEnabled = true;
      _socket.multicastHops = 1;
      
      _cozmoAddress = cozmoIP != null 
          ? InternetAddress(cozmoIP)
          : await _discoverCozmo();
      
      if (_cozmoAddress == null) {
        return 'Cozmo не найден в сети';
      }
      
      // Запуск прослушивания входящих пакетов
      _socket.listen(_onDataReceived);
      
      // Отправка RESET для инициализации соединения
      await _sendReset();
      
      _isConnected = true;
      return null;
    } catch (e) {
      return 'Ошибка подключения: $e';
    }
  }
  
  void _onDataReceived(RawDatagram? datagram) {
    if (datagram != null && datagram.address == _cozmoAddress) {
      _incomingController.add(datagram.data);
    }
  }
  
  Future<InternetAddress?> _discoverCozmo() async {
    // Сканирование сети для поиска Cozmo
    for (int i = 1; i <= 255; i++) {
      final testIP = InternetAddress('172.31.1.$i');
      // Попытка подключения...
      // В реальной реализации здесь был бы ping или другая проверка
    }
    return InternetAddress('172.31.1.1'); // По умолчанию
  }
  
  Future<void> _sendReset() async {
    final resetFrame = _createResetFrame();
    _sendRaw(resetFrame);
  }
  
  List<int> _createResetFrame() {
    final data = <int>[];
    
    // FRAME_ID (7 байт): "COZ\x03RE\x01"
    data.addAll([0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01]);
    
    // Frame Type: RESET (0x01)
    data.add(0x01);
    
    // Sequence numbers (все +1)
    data.addAll([0x01, 0x00]);  // first_seq
    data.addAll([0x01, 0x00]);  // seq
    data.addAll([0x01, 0x00]);  // ack
    
    return data;
  }
  
  void _sendRaw(List<int> data) {
    if (_isConnected && _cozmoAddress != null) {
      _socket.send(data, _cozmoAddress!, 5551);
    }
  }
  
  void disconnect() {
    if (_isConnected) {
      // Отправка FIN для корректного завершения
      final finFrame = _createFinFrame();
      _sendRaw(finFrame);
      
      _socket.close();
      _isConnected = false;
    }
  }
  
  List<int> _createFinFrame() {
    final data = <int>[];
    
    // FRAME_ID
    data.addAll([0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01]);
    
    // Frame Type: FIN (0x03)
    data.add(0x03);
    
    // Sequence numbers
    data.addAll([0x01, 0x00]);  // first_seq
    data.addAll([0x01, 0x00]);  // seq
    data.addAll([0x01, 0x00]);  // ack
    
    return data;
  }
}
```

### 2. Надёжный UDP слой

```dart
// lib/cozmo/core/protocol.dart
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

class ReliableProtocol {
  final CozmoConnection _connection;
  final Map<int, InFlightPacket> _inflightPackets = {};
  final Queue<PacketData> _outboundQueue = Queue();
  
  int _nextSequence = 0;
  int _lastRemoteAck = -1;
  Timer? _tickTimer;
  
  static const int _WINDOW_SIZE = 32;
  static const int _RTO_MS = 25;
  static const int _TICK_INTERVAL_MS = 5;
  
  ReliableProtocol(this._connection) {
    _connection.incoming.listen(_handleIncomingPacket);
    _startTickTimer();
  }
  
  void _startTickTimer() {
    _tickTimer = Timer.periodic(
      Duration(milliseconds: _TICK_INTERVAL_MS),
      _tick,
    );
  }
  
  void _tick(Timer timer) {
    // 1. Удалить подтвержденные пакеты
    _removeAcknowledgedPackets();
    
    // 2. Ретранслировать потерянные
    _retransmitLostPackets();
    
    // 3. Отправить новые пакеты
    _sendNewPackets();
    
    // 4. Отправить PING если нужно
    _sendPingIfNeeded();
  }
  
  void _removeAcknowledgedPackets() {
    _inflightPackets.removeWhere((seq, packet) =>
        _getSeqDistance(seq, _lastRemoteAck) <= 0);
  }
  
  void _retransmitLostPackets() {
    final now = DateTime.now();
    
    for (final entry in _inflightPackets.entries) {
      final packet = entry.value;
      
      if (now.difference(packet.lastSentTime).inMilliseconds > _RTO_MS) {
        _sendRawFrame(packet.frameData);
        packet.lastSentTime = now;
        packet.retries++;
        
        print('🔄 Retransmitting packet ${entry.key} (retry ${packet.retries})');
        return; // Отправили один пакет, выходим
      }
    }
  }
  
  void _sendNewPackets() {
    while (_inflightPackets.length < _WINDOW_SIZE && _outboundQueue.isNotEmpty) {
      final packetData = _outboundQueue.removeFirst();
      _sendReliableFrame(packetData);
    }
  }
  
  void _sendPingIfNeeded() {
    final now = DateTime.now();
    
    if (_lastPacketSentTime != null &&
        now.difference(_lastPacketSentTime!).inMilliseconds > 1000) {
      _sendPing();
    }
  }
  
  void _sendReliableFrame(PacketData packetData) {
    final frameData = _createEngineFrame(packetData);
    _sendRawFrame(frameData);
    
    // Сохранить для ретрансляции
    _inflightPackets[_nextSequence] = InFlightPacket(
      frameData: frameData,
      lastSentTime: DateTime.now(),
      retries: 0,
    );
    
    _nextSequence = (_nextSequence + 1) % 0x10000;
    _lastPacketSentTime = DateTime.now();
  }
  
  List<int> _createEngineFrame(PacketData packetData) {
    final writer = ByteWriter();
    
    // FRAME_ID
    writer.writeBytes([0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01]);
    
    // Frame Type: ENGINE (0x07)
    writer.writeUint8(0x07);
    
    // Sequence numbers (закодированные с +1)
    writer.writeUint16((_nextSequence + 1) % 0x10000);
    writer.writeUint16((_nextSequence + 1) % 0x10000);
    writer.writeUint16((_lastRemoteAck + 1) % 0x10000);
    
    // Packet payload
    writer.writeBytes(packetData.toBytes());
    
    return writer.toBytes();
  }
  
  void _sendRawFrame(List<int> frameData) {
    _connection._sendRaw(frameData);
  }
  
  void _handleIncomingPacket(Uint8List data) {
    if (data.length < 14) return; // Минимальный размер фрейма
    
    final frameType = data[7];
    
    if (frameType == 0x09) { // ROBOT frame
      _handleRobotFrame(data);
    } else if (frameType == 0x0b) { // PING frame
      _handlePingFrame(data);
    }
  }
  
  void _handleRobotFrame(Uint8List data) {
    if (data.length < 16) return;
    
    // Извлечь sequence numbers
    final ack = _extractSeq(data, 12);
    
    if (ack != _lastRemoteAck) {
      _lastRemoteAck = ack;
      print('📨 Received ACK: $ack');
    }
    
    // Обработать пакеты данных
    final packetType = data[14];
    if (packetType == 0x05) { // EVENT packet
      _handleEventPacket(data);
    }
  }
  
  void _handlePingFrame(Uint8List data) {
    // Обработка PING ответов
    final ack = _extractSeq(data, 12);
    if (ack != _lastRemoteAck) {
      _lastRemoteAck = ack;
      print('🏓 PING ACK: $ack');
    }
  }
  
  int _extractSeq(Uint8List data, int offset) {
    return (data[offset + 1] << 8) | data[offset] - 1; // -1 для декодирования
  }
  
  int _getSeqDistance(int seq1, int seq2) {
    int distance = seq1 - seq2;
    if (distance > 0x8000) distance -= 0x10000;
    if (distance < -0x8000) distance += 0x10000;
    return distance;
  }
  
  Future<void> sendCommand(int commandId, List<int> payload) async {
    final packetData = CommandPacket(
      type: 0x04, // COMMAND
      commandId: commandId,
      payload: payload,
    );
    
    _outboundQueue.add(packetData);
  }
  
  void dispose() {
    _tickTimer?.cancel();
    _connection.disconnect();
  }
}

class PacketData {
  final int type;
  final int commandId;
  final List<int> payload;
  
  PacketData({
    required this.type,
    required this.commandId,
    required this.payload,
  });
  
  List<int> toBytes() {
    final writer = ByteWriter();
    writer.writeUint8(type);
    writer.writeUint16(payload.length + 1); // +1 для commandId
    writer.writeUint8(commandId);
    writer.writeBytes(payload);
    return writer.toBytes();
  }
}

class CommandPacket extends PacketData {
  CommandPacket({required int commandId, required List<int> payload})
      : super(type: 0x04, commandId: commandId, payload: payload);
}

class InFlightPacket {
  List<int> frameData;
  DateTime lastSentTime;
  int retries;
  
  InFlightPacket({
    required this.frameData,
    required this.lastSentTime,
    required this.retries,
  });
}
```

---

## Создание AnimationController

### 1. Базовый контроллер

### Реализация Audio Takeover в pycozmo

**AnimationController в pycozmo** (anim_controller.py:166-173):
```python
def _run(self):
    # Enable animation playback and AnimationState events
    pkt = protocol_encoder.EnableAnimationState()
    self.cli.conn.send(pkt)
    
    timer = util.FPSTimer(robot.FRAME_RATE)
    while not self.stop_flag:
        audio_pkt, image_pkt, pkts = self.queue.get()
        
        if self.animations_enabled:
            if audio_pkt:
                if not self.playing_audio:
                    self.playing_audio = True
            else:
                # Вот ключевой момент! Отправка silence когда нет аудио
                audio_pkt = protocol_encoder.OutputSilence()
                if self.playing_audio:
                    self.playing_audio = False
                    self.cli.conn.post_event(event.EvtAudioCompleted, self.cli)
            self.cli.conn.send(audio_pkt)
            
            # Изображения обновляются даже во время аудио!
            if not image_pkt and self.procedural_face_enabled and not self.playing_animation:
                image_pkt = self._get_face_image()
            
            if image_pkt:
                self.cli.conn.send(image_pkt)
                self.last_image_pkt = image_pkt
            else:
                # Если не обновлять, робот перестанет отображать изображение через 30 секунд
                self.cli.conn.send(self.last_image_pkt)
            
            if pkts:
                for pkt in pkts:
                    self.cli.conn.send(pkt)
            
            timer.sleep()
```

**Dart реализация:**
```dart
// lib/cozmo/animation/animation_controller.dart
import 'dart:async';
import 'dart:typed_data';

class CozmoAnimationController {
  final ReliableProtocol _protocol;
  Timer? _tickTimer;
  
  bool _isAudioBusy = false;
  int _tickCounter = 0;
  List<int>? _currentImagePayload;
  
  static const int _TICK_INTERVAL_MS = 33; // ~30 FPS
  static const int _IMAGE_UPDATE_INTERVAL = 30; // Каждые 30 тиков = ~1 сек
  
  CozmoAnimationController(this._protocol) {
    _startTickTimer();
  }
  
  void _startTickTimer() {
    _tickTimer = Timer.periodic(
      Duration(milliseconds: _TICK_INTERVAL_MS),
      _tick,
    );
  }
  
  void _tick(Timer timer) {
    // 1. АУДИО / ТИШИНА
    if (!_isAudioBusy) {
      _protocol.sendCommand(0x8f, []); // OutputSilence
    }
    
    // 2. ЭКРАН (ДАЖЕ ВО ВРЕМЯ АУДИО!)
    if (_tickCounter % _IMAGE_UPDATE_INTERVAL == 0 && _currentImagePayload != null) {
      _protocol.sendCommand(0x20, _currentImagePayload!); // DisplayImage
    }
    
    _tickCounter++;
  }
  
  // Установить текущее изображение для отображения
  void setCurrentImage(List<int> imagePayload) {
    _currentImagePayload = imagePayload;
  }
  
  // Главный метод для аудио-модуля
  void setAudioBusy(bool busy) {
    if (_isAudioBusy != busy) {
      _isAudioBusy = busy;
      print('🎵 Audio state changed: ${busy ? "BUSY" : "FREE"}');
    }
  }
  
  void dispose() {
    _tickTimer?.cancel();
  }
}
```

### 2. Расширенный контроллер с эмоциями

```dart
// lib/cozmo/animation/emotion_player.dart
enum CozmoEmotion {
  happy,
  sad,
  surprised,
  thinking,
  frustrated,
  scared,
  sleepy,
  greeting,
  win,
  lose,
  chatty,
}

class CozmoEmotionPlayer {
  final ReliableProtocol _protocol;
  final CozmoAnimationController _animController;
  
  CozmoEmotionPlayer(this._protocol, this._animController);
  
  Future<void> playEmotion(CozmoEmotion emotion, {int loops = 1}) async {
    final triggerId = _getEmotionTriggerId(emotion);
    
    for (int i = 0; i < loops; i++) {
      await _playAnimationTrigger(triggerId);
      if (i < loops - 1) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }
  }
  
  Future<void> _playAnimationTrigger(int triggerId) async {
    // Создание пакета PlayAnimationTrigger (0x26)
    final payload = <int>[];
    payload.addAll(_int32ToBytes(triggerId)); // trigger_id
    payload.add(0x00); // unknown1
    payload.addAll(_int32ToBytes(-1)); // unknown2
    payload.addAll(_int32ToBytes(-1)); // unknown3
    payload.add(0x00); // unknown4
    
    await _protocol.sendCommand(0x26, payload);
    
    // Длительность типичной эмоции ~1-2 секунды
    await Future.delayed(Duration(milliseconds: 1500));
  }
  
  int _getEmotionTriggerId(CozmoEmotion emotion) {
    // ID триггеров основаны на pycozmo CozmoAnim triggers
    switch (emotion) {
      case CozmoEmotion.happy:
        return 0x62775834; // "happy" trigger hash
      case CozmoEmotion.sad:
        return 0x6d333d34; // "sad" trigger hash
      case CozmoEmotion.surprised:
        return 0x3fa6f867; // "surprised" trigger hash
      case CozmoEmotion.thinking:
        return 0x63f8a8c6; // "thinking" trigger hash
      case CozmoEmotion.frustrated:
        return 0x728d22f7; // "frustrated" trigger hash
      case CozmoEmotion.scared:
        return 0x4e6a7b3d; // "scared" trigger hash
      case CozmoEmotion.sleepy:
        return 0x55512d8e; // "sleepy" trigger hash
      case CozmoEmotion.greeting:
        return 0x6c4d4f21; // "greeting" trigger hash
      case CozmoEmotion.win:
        return 0x63f8a8c6; // "win" trigger hash (same as thinking)
      case CozmoEmotion.lose:
        return 0x4e6a7b3d; // "lose" trigger hash (same as scared)
      case CozmoEmotion.chatty:
        return 0x5aa65d3e; // "chatty" trigger hash
    }
  }
  
  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }
}
```

---

## Аудио подсистема

### 1. u-law кодирование

```dart
// lib/cozmo/audio/ulaw_encoder.dart
class ULawEncoder {
  static const int MULAW_MAX = 0x7FFF;
  static const int MULAW_BIAS = 132;
  
  static List<int> encodePCM16(List<int> pcmData) {
    final encoded = <int>[];
    
    // Конвертировать пары байт в 16-bit сэмплы
    for (int i = 0; i < pcmData.length; i += 2) {
      if (i + 1 < pcmData.length) {
        final sample = (pcmData[i + 1] << 8) | pcmData[i];
        // Конвертировать signed little-endian в signed int
        final signedSample = sample > 32767 ? sample - 65536 : sample;
        encoded.add(_uLawEncode(signedSample));
      }
    }
    
    return encoded;
  }
  
  static int _uLawEncode(int sample) {
    int mask = 0x4000;
    int position = 14;
    int sign = 0;
    
    if (sample < 0) {
      sample = -sample;
      sign = 0x80;
    }
    
    sample += MULAW_BIAS;
    if (sample > MULAW_MAX) {
      sample = MULAW_MAX;
    }
    
    while ((sample & mask) != mask && position >= 7) {
      mask >>= 1;
      position--;
    }
    
    final lsb = (sample >> (position - 4)) & 0x0f;
    return -(~(sign | ((position - 7) << 4) | lsb));
  }
}
```

### 2. Аудио проигрыватель с Audio Takeover

```dart
// lib/cozmo/audio/audio_player.dart
class CozmoAudioPlayer {
  final ReliableProtocol _protocol;
  final CozmoAnimationController _animController;
  
  bool _isPlaying = false;
  Timer? _playbackTimer;
  
  CozmoAudioPlayer(this._protocol, this._animController);
  
  Future<void> playWAVFile(String wavPath) async {
    if (_isPlaying) {
      throw StateError('Audio already playing');
    }
    
    try {
      _isPlaying = true;
      
      // 1. ЗАХВАТЫВАЕМ КОНТРОЛЬ
      _animController.setAudioBusy(true);
      
      // 2. Загрузить и конвертировать WAV
      final file = File(wavPath);
      final bytes = await file.readAsBytes();
      final pcmData = _extractPCMFromWAV(bytes);
      final ulawData = ULawEncoder.encodePCM16(pcmData);
      
      // 3. Разделить на пакеты
      final packets = _splitIntoPackets(ulawData);
      
      // 4. БЫСТРАЯ ОТПРАВКА
      await _sendPacketsFast(packets);
      
    } finally {
      // 5. ВОЗВРАЩАЕМ КОНТРОЛЬ
      _animController.setAudioBusy(false);
      _isPlaying = false;
    }
  }
  
  List<int> _extractPCMFromWAV(List<int> wavData) {
    // Простая реализация для WAV 16-bit PCM
    if (wavData.length < 44) return [];
    
    // Проверка WAV формата
    final header = String.fromCharCodes(wavData.sublist(0, 4));
    if (header != 'RIFF') {
      throw FormatException('Not a WAV file');
    }
    
    // Извлечь PCM данные (после заголовка 44 байта)
    return wavData.sublist(44);
  }
  
  List<List<int>> _splitIntoPackets(List<int> ulawData) {
    final packets = <List<int>>[];
    static const int PACKET_SIZE = 744; // Количество сэмплов в пакете
    
    for (int i = 0; i < ulawData.length; i += PACKET_SIZE) {
      final end = math.min(i + PACKET_SIZE, ulawData.length);
      final chunk = ulawData.sublist(i, end);
      packets.add(chunk);
    }
    
    return packets;
  }
  
  Future<void> _sendPacketsFast(List<List<int>> packets) async {
    for (int i = 0; i < packets.length; i++) {
      // Только backpressure тормозит нас
      while (_protocol.outboundQueueLength > 100) {
        await Future.delayed(Duration(milliseconds: 1));
      }
      
      // Создать и отправить OutputAudio пакет (0x8e)
      await _protocol.sendCommand(0x8e, packets[i]);
    }
    
    // Ждем пока очередь опустеет
    while (_protocol.outboundQueueLength > 0) {
      await Future.delayed(Duration(milliseconds: 50));
    }
  }
  
  void stop() {
    _playbackTimer?.cancel();
    _isPlaying = false;
    _animController.setAudioBusy(false);
  }
}
```

---

## Обработка изображений

### 1. Простые изображения

```dart
// lib/cozmo/video/simple_image.dart
class CozmoSimpleImage {
  static const int WIDTH = 128;
  static const int HEIGHT = 32;
  
  final List<int> pixels = List.filled(WIDTH * HEIGHT, 0);
  
  CozmoSimpleImage();
  
  factory CozmoSimpleImage.createEyes() {
    final img = CozmoSimpleImage();
    
    // Левый глаз (35-55, 8-16)
    img.drawRect(35, 8, 55, 16);
    
    // Правый глаз (73-93, 8-16)
    img.drawRect(73, 8, 93, 16);
    
    // Улыбка (линия от 40 до 88 на y=24)
    for (int x = 40; x <= 88; x++) {
      img.setPixel(x, 24, 255);
    }
    
    return img;
  }
  
  factory CozmoSimpleImage.createHappy() {
    final img = CozmoSimpleImage();
    
    // Глаза-полумесяцы
    img.drawArc(35, 8, 20, 8, 0, math.pi);
    img.drawArc(73, 8, 20, 8, 0, math.pi);
    
    // Большая улыбка
    img.drawArc(40, 12, 48, 20, 0.2 * math.pi, 0.8 * math.pi);
    
    return img;
  }
  
  factory CozmoSimpleImage.createSad() {
    final img = CozmoSimpleImage();
    
    // Опущенные глаза
    img.drawLine(35, 12, 55, 12);
    img.drawLine(73, 12, 93, 12);
    
    // Опущенные уголки рта
    img.drawLine(40, 24, 50, 28);
    img.drawLine(78, 28, 88, 24);
    
    return img;
  }
  
  void setPixel(int x, int y, int value) {
    if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
      pixels[y * WIDTH + x] = value;
    }
  }
  
  void drawRect(int x1, int y1, int x2, int y2) {
    for (int y = y1; y <= y2; y++) {
      for (int x = x1; x <= x2; x++) {
        setPixel(x, y, 255);
      }
    }
  }
  
  void drawLine(int x1, int y1, int x2, int y2) {
    final dx = (x2 - x1).abs();
    final dy = (y2 - y1).abs();
    final sx = x1 < x2 ? 1 : -1;
    final sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    int x = x1;
    int y = y1;
    
    while (true) {
      setPixel(x, y, 255);
      
      if (x == x2 && y == y2) break;
      
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
    }
  }
  
  void drawArc(int x, int y, int width, int height, double startAngle, double endAngle) {
    // Упрощённая рисование дуги
    final centerX = x + width ~/ 2;
    final centerY = y + height ~/ 2;
    final radiusX = width ~/ 2;
    final radiusY = height ~/ 2;
    
    for (double angle = startAngle; angle <= endAngle; angle += 0.1) {
      final px = centerX + (radiusX * math.cos(angle)).round();
      final py = centerY + (radiusY * math.sin(angle)).round();
      setPixel(px, py, 255);
    }
  }
  
  List<int> encodeRLE() {
    final result = <int>[];
    
    // Заголовок RLE для Cozmo
    result.add(0x03); // Flags
    result.add(0x01); // ImgID
    result.add(0x00); // ChunkID
    
    // Простой RLE по столбцам
    for (int x = 0; x < WIDTH; x++) {
      int blankPixels = 0;
      int lastPixel = -1;
      int repeatCount = 0;
      
      for (int y = 0; y < HEIGHT; y++) {
        final pixel = pixels[y * WIDTH + x];
        
        if (pixel == 0) {
          if (lastPixel != 0) {
            if (repeatCount > 0) {
              _addRepeat(result, repeatCount);
              repeatCount = 0;
            }
          }
          blankPixels++;
          lastPixel = 0;
        } else {
          if (blankPixels > 0) {
            _addSkip(result, blankPixels);
            blankPixels = 0;
          }
          
          if (pixel == lastPixel && repeatCount < 15) {
            repeatCount++;
          } else {
            if (repeatCount > 0) {
              _addRepeat(result, repeatCount);
              repeatCount = 0;
            }
            _addPixel(result, pixel);
            lastPixel = pixel;
          }
        }
      }
      
      // Завершить столбец
      if (blankPixels > 0) {
        _addSkip(result, blankPixels);
      }
      if (repeatCount > 0) {
        _addRepeat(result, repeatCount);
      }
    }
    
    return result;
  }
  
  void _addSkip(List<int> result, int count) {
    while (count > 0) {
      final chunk = math.min(count - 1, 0x3F);
      result.add(chunk); // Skip (0x00-0x3F)
      count -= chunk + 1;
    }
  }
  
  void _addRepeat(List<int> result, int count) {
    while (count > 0) {
      final chunk = math.min(count - 1, 0x3F);
      result.add(0x40 | chunk); // Repeat (0x40-0x7F)
      count -= chunk + 1;
    }
  }
  
  void _addPixel(List<int> result, int pixel) {
    result.add(0x80); // Draw (0x80)
    result.add(pixel); // Pixel value
  }
}
```

### 2. Кэширование изображений

```dart
// lib/cozmo/video/image_cache.dart
class CozmoImageCache {
  static final Map<String, List<int>> _cache = {};
  static bool _initialized = false;
  
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // Предзагрузка часто используемых изображений
    final commonImages = [
      'eyes', 'happy', 'sad', 'surprised', 
      'thinking', 'frustrated', 'scared'
    ];
    
    for (final name in commonImages) {
      await _preloadImage(name);
    }
    
    _initialized = true;
    print('🖼️ Image cache initialized with ${_cache.length} images');
  }
  
  static Future<List<int>> _preloadImage(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;
    
    late CozmoSimpleImage img;
    
    switch (name) {
      case 'eyes':
        img = CozmoSimpleImage.createEyes();
        break;
      case 'happy':
        img = CozmoSimpleImage.createHappy();
        break;
      case 'sad':
        img = CozmoSimpleImage.createSad();
        break;
      case 'surprised':
        img = CozmoSimpleImage.createSurprised();
        break;
      case 'thinking':
        img = CozmoSimpleImage.createThinking();
        break;
      case 'frustrated':
        img = CozmoSimpleImage.createFrustrated();
        break;
      case 'scared':
        img = CozmoSimpleImage.createScared();
        break;
      default:
        img = CozmoSimpleImage.createEyes();
    }
    
    final rleData = img.encodeRLE();
    _cache[name] = rleData;
    
    return rleData;
  }
  
  static List<int> getImage(String name) {
    if (!_initialized) {
      throw StateError('Image cache not initialized. Call initialize() first.');
    }
    
    return _cache[name] ?? _cache['eyes']!;
  }
  
  static void clearCache() {
    _cache.clear();
    _initialized = false;
    print('🗑️ Image cache cleared');
  }
}
```

---

## Интеграция и тестирование

### 1. Основной клиент

```dart
// lib/cozmo/client.dart
class CozmoClient {
  late CozmoConnection _connection;
  late ReliableProtocol _protocol;
  late CozmoAnimationController _animController;
  late CozmoAudioPlayer _audioPlayer;
  late CozmoEmotionPlayer _emotionPlayer;
  
  bool _isConnected = false;
  
  CozmoClient();
  
  Future<String?> connect({String? cozmoIP}) async {
    try {
      // 1. Инициализация кэша изображений
      await CozmoImageCache.initialize();
      
      // 2. Установка соединения
      _connection = CozmoConnection();
      final error = await _connection.connect(cozmoIP: cozmoIP);
      if (error != null) return error;
      
      // 3. Создание протокола
      _protocol = ReliableProtocol(_connection);
      
      // 4. Создание контроллеров
      _animController = CozmoAnimationController(_protocol);
      _audioPlayer = CozmoAudioPlayer(_protocol, _animController);
      _emotionPlayer = CozmoEmotionPlayer(_protocol, _animController);
      
      // 5. Отправка Enable команды
      await _protocol.sendCommand(0x25, []); // Enable
      
      _isConnected = true;
      print('🤖 Cozmo connected successfully!');
      return null;
    } catch (e) {
      return 'Connection failed: $e';
    }
  }
  
  // API методы
  Future<void> playAudio(String wavPath) async {
    if (!_isConnected) throw StateError('Not connected to Cozmo');
    await _audioPlayer.playWAVFile(wavPath);
  }
  
  Future<void> playEmotion(CozmoEmotion emotion, {int loops = 1}) async {
    if (!_isConnected) throw StateError('Not connected to Cozmo');
    await _emotionPlayer.playEmotion(emotion, loops: loops);
  }
  
  Future<void> setVolume(int volume) async {
    if (!_isConnected) throw StateError('Not connected to Cozmo');
    
    // Конвертация процента в Cozmo диапазон (0-65535)
    final cozmoVolume = (volume / 100.0 * 65535).round();
    final payload = _int32ToBytes(cozmoVolume);
    await _protocol.sendCommand(0x64, payload); // SetRobotVolume
  }
  
  Future<void> setHeadAngle(double angle, {double speed = 10.0}) async {
    if (!_isConnected) throw StateError('Not connected to Cozmo');
    
    final payload = <int>[];
    payload.addAll(_float32ToBytes(angle)); // angle_rad
    payload.addAll(_float32ToBytes(speed)); // max_speed_rad_per_sec
    payload.addAll(_float32ToBytes(10.0)); // accel_rad_per_sec2
    payload.addAll(_float32ToBytes(0.0)); // duration_sec
    payload.add(0x00); // action_id
    
    await _protocol.sendCommand(0x37, payload); // SetHeadAngle
  }
  
  Future<void> displayImage(String imageName) async {
    if (!_isConnected) throw StateError('Not connected to Cozmo');
    
    final imageData = CozmoImageCache.getImage(imageName);
    _animController.setCurrentImage(imageData);
  }
  
  // Вспомогательные методы
  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }
  
  List<int> _float32ToBytes(double value) {
    final byteData = ByteData(4)..setFloat32(0, value, Endian.little);
    return [
      byteData.getUint8(0),
      byteData.getUint8(1),
      byteData.getUint8(2),
      byteData.getUint8(3),
    ];
  }
  
  void disconnect() {
    if (_isConnected) {
      _animController.dispose();
      _protocol.dispose();
      _isConnected = false;
      print('🤖 Cozmo disconnected');
    }
  }
  
  bool get isConnected => _isConnected;
}
```

### 2. Пример комплексной сцены

```dart
// lib/examples/combined_scene.dart
class CozmoCombinedScene {
  late CozmoClient _cozmo;
  
  Future<void> run() async {
    // 1. Подключение
    final error = await _cozmo.connect();
    if (error != null) {
      print('❌ Connection failed: $error');
      return;
    }
    
    try {
      // 2. Настройка
      await _cozmo.setVolume(80);
      await _cozmo.setHeadAngle(0.0); // Голова прямо
      await _cozmo.displayImage('eyes');
      
      await Future.delayed(Duration(seconds: 1));
      
      // 3. Сценарий
      await _performWakeUpSequence();
      await Future.delayed(Duration(seconds: 1));
      
      await _performSpeakingSequence();
      await Future.delayed(Duration(seconds: 1));
      
      await _performEmotionalResponse();
      
    } finally {
      // 4. Отключение
      _cozmo.disconnect();
    }
  }
  
  Future<void> _performWakeUpSequence() async {
    print('🎬 Wake up sequence...');
    
    // Просыпаемся
    await _cozmo.setHeadAngle(-0.2, speed: 5.0);
    await Future.delayed(Duration(milliseconds: 500));
    await _cozmo.setHeadAngle(0.0, speed: 5.0);
    await Future.delayed(Duration(milliseconds: 500));
    await _cozmo.setHeadAngle(0.3, speed: 5.0);
    
    // Показываем улыбку
    await _cozmo.displayImage('happy');
    await _cozmo.playEmotion(CozmoEmotion.happy);
  }
  
  Future<void> _performSpeakingSequence() async {
    print('🗣️ Speaking sequence...');
    
    // Показываем думающее лицо
    await _cozmo.displayImage('thinking');
    await _cozmo.playEmotion(CozmoEmotion.thinking);
    
    // Воспроизводим речь
    await _cozmo.playAudio('assets/sounds/hello.wav');
    
    // Показываем нормальное лицо
    await _cozmo.displayImage('eyes');
  }
  
  Future<void> _performEmotionalResponse() async {
    print('😊 Emotional response...');
    
    // Случайная эмоция
    final emotions = [
      CozmoEmotion.happy,
      CozmoEmotion.surprised,
      CozmoEmotion.excited,
    ];
    
    final random = Random();
    final emotion = emotions[random.nextInt(emotions.length)];
    
    await _cozmo.playEmotion(emotion);
    await _cozmo.displayImage(emotion.toString().split('.').last);
  }
}
```

### 3. Тестирование

```dart
// lib/examples/testing.dart
class CozmoTester {
  late CozmoClient _cozmo;
  
  Future<void> runAllTests() async {
    final error = await _cozmo.connect();
    if (error != null) {
      print('❌ Connection failed: $error');
      return;
    }
    
    try {
      await testBasicConnection();
      await testAudioPlayback();
      await testImageDisplay();
      await testAudioTakeover();
      await testEmotions();
      
      print('✅ All tests completed successfully!');
    } catch (e) {
      print('❌ Test failed: $e');
    } finally {
      _cozmo.disconnect();
    }
  }
  
  Future<void> testBasicConnection() async {
    print('\n🧪 Testing basic connection...');
    
    // Тест управления головой
    await _cozmo.setHeadAngle(-0.2);
    await Future.delayed(Duration(milliseconds: 500));
    await _cozmo.setHeadAngle(0.0);
    await Future.delayed(Duration(milliseconds: 500));
    await _cozmo.setHeadAngle(0.3);
    
    print('✅ Head control test passed');
  }
  
  Future<void> testAudioPlayback() async {
    print('\n🧪 Testing audio playback...');
    
    final testAudio = 'assets/test_audio.wav';
    
    final stopwatch = Stopwatch()..start();
    await _cozmo.playAudio(testAudio);
    stopwatch.stop();
    
    print('✅ Audio playback test passed (${stopwatch.elapsedMilliseconds}ms)');
  }
  
  Future<void> testImageDisplay() async {
    print('\n🧪 Testing image display...');
    
    final images = ['eyes', 'happy', 'sad', 'surprised'];
    
    for (final imageName in images) {
      await _cozmo.displayImage(imageName);
      await Future.delayed(Duration(milliseconds: 1000));
    }
    
    print('✅ Image display test passed');
  }
  
  Future<void> testAudioTakeover() async {
    print('\n🧪 Testing audio takeover...');
    
    // Показываем изображение
    await _cozmo.displayImage('thinking');
    
    // Воспроизводим аудио (должно работать с изображением)
    await _cozmo.playAudio('assets/test_audio.wav');
    
    // Проверяем, что изображение всё ещё видно
    await Future.delayed(Duration(milliseconds: 500));
    
    print('✅ Audio takeover test passed');
  }
  
  Future<void> testEmotions() async {
    print('\n🧪 Testing emotions...');
    
    final emotions = [
      CozmoEmotion.happy,
      CozmoEmotion.sad,
      CozmoEmotion.surprised,
      CozmoEmotion.thinking,
      CozmoEmotion.frustrated,
      CozmoEmotion.scared,
    ];
    
    for (final emotion in emotions) {
      await _cozmo.playEmotion(emotion);
      await Future.delayed(Duration(milliseconds: 1500));
    }
    
    print('✅ Emotions test passed');
  }
}
```

---

## Заключение

Эта практическая реализация демонстрирует полный цикл создания клиента для Cozmo с акцентом на правильную координацию аудио и видео через Audio Takeover Pattern.

### Ключевые моменты

1. **Надёжный UDP слой** с ретрансляцией и sliding window
2. **Audio Takeover Pattern** для координации аудио и видео
3. **Эффективное кодирование** аудио (u-law) и изображений (RLE)
4. **Кэширование ресурсов** для повышения производительности
5. **Комплексное тестирование** всех компонентов

### Рекомендации

1. Начните с базового подключения и постепенно добавляйте функциональность
2. Тщательно тестируйте Audio Takeover с логированием
3. Используйте кэширование для изображений, которые часто меняются
4. Оптимизируйте под свою конкретную задачу (аудио, видео или смешанные сценарии)
5. Мониторьте производительность и потери пакетов в реальном времени

Эта архитектура обеспечивает прочную основу для создания интерактивных приложений с Cozmo, сочетающих аудио и визуальные эффекты.