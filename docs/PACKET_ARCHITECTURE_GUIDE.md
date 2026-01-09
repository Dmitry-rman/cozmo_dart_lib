
# Архитектура пакетов Cozmo: одновременный вывод изображений и аудио

## 📋 Содержание

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Сетевой уровень](#сетевой-уровень)
3. [Протокол фреймов](#протокол-фреймов)
4. [Модель пакетов](#модель-пакетов)
5. [Координация аудио и видео](#координация-аудио-и-видео)
6. [Практические примеры](#практические-примеры)
7. [Диагностика и отладка](#диагностика-и-отладка)
8. [Оптимизация производительности](#оптимизация-производительности)

---

## Обзор архитектуры

### Иерархия уровней

```
┌─────────────────────────────────────────────────────────────┐
│                    Прикладной уровень                       │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │   Audio Module   │  │  Image Module    │                │
│  └──────────────────┘  └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                 Координационный уровень                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              AnimationController                     │   │
│  │  ┌─────────────┐  ┌──────────────┐                  │   │
│  │  │ Audio State │  │ Image State  │                  │   │
│  │  │   Manager   │  │   Manager    │                  │   │
│  │  └─────────────┘  └──────────────┘                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                   Транспортный уровень                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  CozmoClient                          │   │
│  │  ┌─────────────┐  ┌──────────────┐                  │   │
│  │  │ SendThread  │  │ ReceiveThread │                  │   │
│  │  └─────────────┘  └──────────────┘                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Сетевой уровень                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                     UDP Socket                         │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │            Соединение с Cozmo                    │  │   │
│  │  │            IP: 172.31.1.1:5551                  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Ключевые принципы архитектуры

1. **Reliable UDP** - протокол UDP надёжности TCP
2. **Sliding Window** - контроль потока с подтверждением доставки
3. **Audio Takeover** - координация между аудио и видео
4. **Frame-based Protocol** - все данные передаются во фреймах
5. **Packet Sequencing** - строгая последовательность пакетов

---

## Сетевой уровень

### UDP соединение

Базовый сетевой уровень основан на UDP соединении с фиксированными параметрами:

```dart
// Параметры соединения
const String COZMO_IP = '172.31.1.1';
const int COZMO_PORT = 5551;

// Создание сокета
final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
socket.broadcastEnabled = true;
socket.multicastHops = 1;
```

### Reliable UDP Implementation

Сетевой уровень реализует надёжность поверх UDP через механизм ретрансляции:

### Реализация в pycozmo

**SendThread** (conn.py:45-46):
```python
COLLECT_INTERVAL = 1/30 / 3  # ~11 мс - только для сбора пакетов
ACK_TIMEOUT = 3 * 1/30       # 100 мс для ACK

def _collect_messages(self) -> Tuple[list, int]:
    with self.lock:
        last_ack = self.last_ack
        is_full = self.window.is_full()
    
    pkts = []
    start = time.perf_counter()
    while not is_full and not self.disconnected and time.perf_counter() - start < self.COLLECT_INTERVAL:
        try:
            pkt = self.queue.get(timeout=self.COLLECT_INTERVAL)
        except Empty:
            continue
        self.outgoing_packets += 1
        # Пакеты просто кладутся в очередь БЕЗ искусственных задержек!
        with self.lock:
            seq = self.window.put(pkt)
            last_ack = self.last_ack
            is_full = self.window.is_full()
        pkts.append((seq, pkt))
    return pkts, last_ack
```

**Адаптивная реализация**:
```dart
class ReliableUDPLayer {
  final Map<int, InFlightPacket> _inflightPackets = {};
  final Map<int, DateTime> _packetTimestamps = {};
  int _nextSequence = 0;
  int _lastRemoteAck = -1;
  
  // Размер окна для контроля потока
  static const int _WINDOW_SIZE = 32;
  
  // Таймаут ретрансляции
  static const int _RTO_MS = 25;
  
  void _tick(Timer timer) {
    // 1. Удалить подтвержденные пакеты
    _removeAcknowledgedPackets();
    
    // 2. Ретранслировать потерянные
    _retransmitLostPackets();
    
    // 3. Отправить новые пакеты
    _sendNewPackets();
    
    // 4. Отправить PING для keep-alive
    _sendKeepAlive();
  }
}
```

---

## Протокол фреймов

### Структура фрейма

Каждый фрейм имеет фиксированную структуру:

```
+--------+--------+--------+--------+--------+--------+--------+
|                     FRAME_ID (7 байт)                      |
+--------+--------+--------+--------+--------+--------+--------+
| Type   | FirstSeq|   Seq  |   Ack  |   Payload...               |
| (1 байт)| (2 байта)|(2 байта)|(2 байта)|(переменная длина)     |
+--------+--------+--------+--------+--------+---------------------+
```

### Frame Types

| Type | Value | Описание | Использование |
|------|-------|----------|---------------|
| RESET | 0x01 | Сброс соединения | Начало сессии |
| RESET_ACK | 0x02 | Подтверждение сброса | Ответ на RESET |
| FIN | 0x03 | Завершение соединения | Корректное отключение |
| ENGINE_ACT | 0x04 | Активация двигателя | Подключение/отключение |
| ENGINE | 0x07 | Команды к роботу | Основные команды |
| ROBOT | 0x09 | События от робота | Ответы и состояния |
| PING | 0x0b | Ping/Keep-alive | Поддержание соединения |

### Sequence Numbers

Механизм нумерации последовательностей для обеспечения порядка пакетов:

```dart
// Кодирование sequence numbers
void _writeSequenceNumbers(ByteWriter writer) {
  writer.writeUint16(_firstSeq + 1);  // +1 для кодирования
  writer.writeUint16(_seq + 1);       // +1 для кодирования
  writer.writeUint16(_ack + 1);       // +1 для кодирования
}

// Декодирование
int _decodeSequence(int encoded) => encoded - 1;
```

---

## Модель пакетов

### Иерархия пакетов

```
Frame (ENGINE/ROBOT)
  └── Packet (COMMAND/EVENT)
      └── CommandID/EventID
          └── Payload (конкретные данные)
```

### Ключевые команды для аудио и видео

| ID | Название | Тип | Описание | Параметры |
|----|----------|-----|----------|-----------|
| 0x8e | OutputAudio | Команда | Воспроизвести аудио | u-law samples[744] |
| 0x8f | OutputSilence | Команда | Тишина (keep-alive) | - |
| 0x26 | PlayAnimationTrigger | Команда | Запустить анимацию | trigger_id |
| 0x25 | Enable | Команда | Включить управление | - |
| 0x37 | SetHeadAngle | Команда | Установить угол головы | angle, speed, accel |
| 0x01 | RobotState | Событие | Состояние робота | pose, battery, etc. |

### Формат аудио пакетов

```
+--------+--------+--------+--------+
| Type   | Length | CmdID  | Samples            |
| (1 байт)|(2 байта)|(1 байт)|(744 байта)        |
+--------+--------+--------+--------------------+
| 0x04   | 0xE902 | 0x8e   | u-law encoded...  |
+--------+--------+--------+--------------------+
```

### Формат пакетов изображений

```
+--------+--------+--------+--------+
| Type   | Length | CmdID  | Image Payload       |
| (1 байт)|(2 байта)|(1 байт)|(переменная длина)  |
+--------+--------+--------+---------------------+
| 0x04   | varies | varies | RLE compressed data |
+--------+--------+--------+---------------------+
```

---

## Координация аудио и видео

### Audio Takeover Pattern

Ключевая проблема: одновременная отправка OutputSilence (0x8f) и OutputAudio (0x8e) вызывает конфликты.

**Решение:** Audio Takeover Pattern

```dart
class CozmoAnimController {
  bool _isAudioBusy = false;
  
  void _tick() {
    // 1. АУДИО / ТИШИНА
    if (!_isAudioBusy) {
      _client.sendCommand(CozmoCmd.outputSilence, []);
    }
    
    // 2. ЭКРАН (ДАЖЕ ВО ВРЕМЯ АУДИО!)
    if (_tickCounter % 30 == 0 && _currentImagePayload != null) {
      _client.sendCommand(CozmoCmd.displayImage, _currentImagePayload!);
    }
    
    _tickCounter++;
  }
  
  void setAudioBusy(bool busy) {
    _isAudioBusy = busy;
  }
}
```

### Алгоритм координации

```dart
Future<void> _streamAudioPackets(List<List<int>> packets) async {
  // 1. ЗАХВАТЫВАЕМ КОНТРОЛЬ
  _animController.setAudioBusy(true);
  
  try {
    // 2. БЫСТРАЯ ОТПРАВКА (без тайминга!)
    for (int i = 0; i < packets.length; i++) {
      // Только backpressure тормозит нас
      while (_client.outboundQueueLength > 100) {
        await Future.delayed(Duration(milliseconds: 1));
      }
      _client.sendRawPacket(packets[i]);
    }
    
    // 3. Ждем пока очередь опустеет
    while (_client.outboundQueueLength > 0) {
      await Future.delayed(Duration(milliseconds: 50));
    }
  } finally {
    // 4. ВОЗВРАЩАЕМ КОНТРОЛЬ
    _animController.setAudioBusy(false);
  }
}
```

### Диаграмма состояний

```
            ┌─────────────────────────────────────┐
            │         AnimationController          │
            │                                     │
            │  ┌─────────────┐    ┌────────────┐ │
            │  │   IDLE      │    │AUDIO BUSY  │ │
            │  │             │    │            │ │
            │  │OutputSilence│◄──►│МОЛЧИТ!     │ │
            │  │DisplayImage │    │DisplayImage│ │
            │  └─────────────┘    └────────────┘ │
            │         ▲                  ▲        │
            └─────────┼──────────────────┼────────┘
                      │                  │
           audio ends │                  │ audio starts
                      │                  │
            ┌─────────┴──────────────────┴────────┐
            │            Audio Module              │
            │                                     │
            │  ┌─────────────────────────────────┐ │
            │  │       _streamPackets()          │ │
            │  │                                 │ │
            │  │1. setAudioBusy(true) ← ЗАХВАТ   │ │
            │  │2. Send packets FAST              │ │
            │  │3. Wait queue empty               │ │
            │  │4. setAudioBusy(false)←ВОЗВРАТ   │ │
            │  └─────────────────────────────────┘ │
            └─────────────────────────────────────┘
```

---

## Практические примеры

### Пример 1: Базовое воспроизведение аудио

```dart
Future<void> playBasicAudio(String wavFilePath) async {
  // 1. Загрузить WAV файл
  final file = File(wavFilePath);
  final bytes = await file.readAsBytes();
  
  // 2. Конвертировать в u-law пакеты
  final packets = _convertToUlaw(bytes);
  
  // 3. Воспроизвести через Audio Takeover
  await _streamAudioPackets(packets);
}

List<List<int>> _convertToUlaw(Uint8List wavData) {
  final packets = <List<int>>[];
  
  // Извлечь PCM данные из WAV
  final pcmData = _extractPCMFromWAV(wavData);
  
  // Разделить на пакеты по 744 сэмплов
  for (int i = 0; i < pcmData.length; i += 744) {
    final chunk = pcmData.sublist(i, math.min(i + 744, pcmData.length));
    final ulawChunk = _encodeUlaw(chunk);
    
    // Создать пакет
    final packet = _createCommandPacket(0x8e, ulawChunk);
    packets.add(packet);
  }
  
  return packets;
}
```

### Пример 2: Отображение изображения во время аудио

```dart
Future<void> displayImageDuringAudio() async {
  // 1. Создать простое изображение (глаза)
  final img = CozmoSimpleImage.createEyes();
  img.drawRect(35, 8, 55, 16);    // Левый глаз
  img.drawRect(73, 8, 93, 16);    // Правый глаз
  
  // 2. Кодировать в RLE
  final rleData = img.encodeRLE();
  
  // 3. Отправить через AnimationController
  _animController.setCurrentImage(rleData);
  
  // 4. Воспроизвести аудио
  await playBasicAudio('/path/to/audio.wav');
}
```

### Пример 3: Комплексная сцена

```dart
Future<void> performComplexScene() async {
  // 1. Показать удивлённое лицо
  await playEmotion(CozmoEmotion.surprised);
  await Future.delayed(Duration(milliseconds: 500));
  
  // 2. Воспроизвести аудио с одновременной анимацией
  final audioTask = playAudioStreaming('/path/to/speech.wav');
  
  // 3. Анимировать глаза во время речи
  for (int i = 0; i < 10; i++) {
    final img = CozmoSimpleImage.createEyes();
    
    // Мигание
    if (i % 3 == 0) {
      img.drawLine(35, 8, 55, 8);   // Закрыть левый глаз
      img.drawLine(73, 8, 93, 8);   // Закрыть правый глаз
    }
    
    _animController.setCurrentImage(img.encodeRLE());
    await Future.delayed(Duration(milliseconds: 200));
  }
  
  // 4. Дождаться завершения аудио
  await audioTask;
  
  // 5. Показать счастливую эмоцию
  await playEmotion(CozmoEmotion.happy);
}
```

---

## Диагностика и отладка

### Инструменты диагностики

#### 1. Лгирование пакетов

```dart
class PacketLogger {
  static void logOutboundPacket(List<int> data) {
    final frameType = data[7];
    
    print('📤 [OUTBOUND] Frame: 0x${frameType.toRadixString(16)}');
    
    if (frameType == 0x07) { // ENGINE
      _logEnginePacket(data);
    } else if (frameType == 0x0b) { // PING
      _logPingPacket(data);
    }
  }
  
  static void _logEnginePacket(List<int> data) {
    if (data.length < 14) return;
    
    final packetType = data[14];
    if (packetType == 0x04) { // COMMAND
      final commandId = data[16];
      print('  🎯 Command: 0x${commandId.toRadixString(16)} (${_getCommandName(commandId)})');
      
      if (commandId == 0x8e) {
        print('  🔊 Audio packet (${data.length - 17} bytes)');
      } else if (commandId == 0x8f) {
        print('  🔇 Silence packet');
      } else if (commandId == 0x26) {
        print('  🎬 Animation trigger');
      }
    }
  }
}
```

#### 2. Мониторинг состояния соединения

```dart
class ConnectionMonitor {
  int _lastSeq = -1;
  int _lastAck = -1;
  final Map<int, DateTime> _packetTimestamps = {};
  
  void updateSequence(int seq, int ack) {
    if (seq != _lastSeq) {
      print('📈 Seq: $_lastSeq → $seq');
      _lastSeq = seq;
    }
    
    if (ack != _lastAck) {
      final latency = _calculateLatency(ack);
      print('📉 Ack: $_lastAck → $ack (latency: ${latency}ms)');
      _lastAck = ack;
    }
  }
  
  void checkPacketLoss() {
    final now = DateTime.now();
    for (final entry in _packetTimestamps.entries) {
      if (now.difference(entry.value).inMilliseconds > 100) {
        print('⚠️ Packet ${entry.key} может быть потерян');
      }
    }
  }
}
```

#### 3. Визуализация Audio Takeover

```dart
class AudioTakeoverMonitor {
  bool _lastAudioState = false;
  int _silencePacketsSent = 0;
  int _audioPacketsSent = 0;
  
  void onAudioStateChange(bool isBusy) {
    if (isBusy != _lastAudioState) {
      if (isBusy) {
        print('🎵 🔄 AUDIO TAKEOVER STARTED');
        print('  📊 Silence packets sent: $_silencePacketsSent');
      } else {
        print('🔇 🔄 AUDIO TAKEOVER ENDED');
        print('  📊 Audio packets sent: $_audioPacketsSent');
      }
      _lastAudioState = isBusy;
    }
  }
  
  void onPacketSent(int commandId) {
    if (commandId == 0x8e) {
      _audioPacketsSent++;
    } else if (commandId == 0x8f) {
      _silencePacketsSent++;
    }
  }
}
```

### Распространённые проблемы

#### 1. Конфликт аудио и silence

**Симптомы:**
- Прерывистый звук
- Щелчки или тишина
- Обрыв соединения

**Диагностика:**
```dart
// Проверить, что Audio Takeover работает
if (_animController._isAudioBusy && _lastCommand == 0x8f) {
  print('❌ ERROR: Silence packet sent during audio!');
}
```

**Решение:**
- Убедиться, что `setAudioBusy(true)` вызывается перед отправкой аудио
- Проверить, что `setAudioBusy(false)` вызывается после завершения

#### 2. Переполнение очереди

**Симптомы:**
- Задержка звука
- Отключение через 5 секунд

**Диагностика:**
```dart
if (_client.outboundQueueLength > 200) {
  print('⚠️ Queue overflow: ${_client.outboundQueueLength} packets');
}
```

**Решение:**
- Увеличить размер окна (`_WINDOW_SIZE`)
- Проверить скорость обработки пакетов
- Уменьшить скорость отправки

#### 3. Буферизация изображений

**Симптомы:**
- Экран гаснет во время аудио
- Изображение не обновляется

**Диагностика:**
```dart
if (_animController._tickCounter % 30 != 0 && _currentImagePayload != null) {
  print('⚠️ Image not being updated regularly');
}
```

**Решение:**
- Убедиться, что DisplayImage отправляется раз в секунду
- Проверить, что `_currentImagePayload` установлен

---

## Оптимизация производительности

### 1. Оптимизация аудио потока

#### Предварительная обработка аудио

```dart
class AudioOptimizer {
  // Конвертировать аудио в пакеты заранее
  static Future<List<List<int>>> preprocessAudio(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    final packets = <List<int>>[];
    
    // Распараллелить конвертацию
    final chunks = _splitAudio(bytes);
    final futures = chunks.map((chunk) => _convertChunkAsync(chunk));
    final results = await Future.wait(futures);
    
    for (final result in results) {
      packets.addAll(result);
    }
    
    return packets;
  }
  
  static Future<List<List<int>>> _convertChunkAsync(List<int> chunk) async {
    return await compute(_convertChunk, chunk); // В отдельном isolate
  }
}
```

#### Адаптивное окно

```dart
class AdaptiveWindow {
  int _currentWindowSize = 16;
  int _packetLossCount = 0;
  int _totalPackets = 0;
  
  void updatePacketLoss(int lost, int total) {
    _packetLossCount += lost;
    _totalPackets += total;
    
    final lossRate = _packetLossCount / _totalPackets;
    
    if (lossRate > 0.05) {
      // Потеря > 5% - увеличить окно
      _currentWindowSize = math.min(_currentWindowSize + 4, 48);
      print('📈 Increased window to $_currentWindowSize (loss: ${(lossRate * 100).toStringAsFixed(1)}%)');
    } else if (lossRate < 0.01 && _currentWindowSize > 16) {
      // Потеря < 1% - уменьшить окно
      _currentWindowSize = math.max(_currentWindowSize - 2, 16);
      print('📉 Decreased window to $_currentWindowSize (loss: ${(lossRate * 100).toStringAsFixed(1)}%)');
    }
  }
}
```

### 2. Оптимизация изображений

#### Кэширование RLE данных

```dart
class ImageCache {
  static final Map<String, List<int>> _cache = {};
  
  static List<int> getCachedImage(String key) {
    return _cache[key] ?? _createAndCache(key);
  }
  
  static List<int> _createAndCache(String key) {
    final img = _createImageByKey(key);
    final rleData = img.encodeRLE();
    _cache[key] = rleData;
    return rleData;
  }
  
  // Предзагрузка часто используемых изображений
  static Future<void> preloadCommonImages() async {
    final commonImages = ['happy', 'sad', 'surprised', 'thinking'];
    
    for (final name in commonImages) {
      getCachedImage(name);
    }
  }
}
```

#### Плавные переходы между изображениями

```dart
class SmoothImageTransitions {
  static List<int> _interpolateImages(List<int> img1, List<int> img2, double t) {
    // Простая интерполяция между двумя RLE изображениями
    final result = <int>[];
    
    // Реализация зависит от формата RLE
    // Это пример концепции
    
    return result;
  }
  
  static Future<void> animateTransition(
    CozmoAnimController controller,
    String fromKey,
    String toKey, {
    Duration duration = const Duration(milliseconds: 500),
  }) async {
    final fromImg = ImageCache.getCachedImage(fromKey);
    final toImg = ImageCache.getCachedImage(toKey);
    
    final steps = (duration.inMilliseconds / 50).round();
    
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final interpolated = _interpolateImages(fromImg, toImg, t);
      controller.setCurrentImage(interpolated);
      await Future.delayed(Duration(milliseconds: 50));
    }
  }
}
```

### 3. Мониторинг производительности

#### Метрики производительности

```dart
class PerformanceMetrics {
  int _audioPacketsPerSecond = 0;
  int _imageUpdatesPerSecond = 0;
  int _retransmissionsPerSecond = 0;
  double _averageLatency = 0.0;
  
  void updateMetrics() {
    final now = DateTime.now();
    
    // Собрать метрики за последнюю секунду
    final audioCount = _countRecentAudioPackets(now);
    final imageCount = _countRecentImageUpdates(now);
    final retransCount = _countRecentRetransmissions(now);
    
    _audioPacketsPerSecond = audioCount;
    _imageUpdatesPerSecond = imageCount;
    _retransmissionsPerSecond = retransCount;
    
    print('📊 Performance Metrics:');
    print('  🎵 Audio: $_audioPacketsPerSecond packets/sec');
    print('  🖼️ Images: $_imageUpdatesPerSecond updates/sec');
    print('  🔄 Retrans: $_retransmissionsPerSecond packets/sec');
    print('  ⏱️ Latency: ${_averageLatency.toStringAsFixed(1)}ms');
  }
}
```

---

## Заключение

### Ключевые выводы

1. **Audio Takeover Pattern** - основа координации аудио и видео
2. **Reliable UDP** - критически важен для стабильности соединения
3. **Sequence Numbers** - обеспечивают порядок пакетов
4. **Sliding Window** - контролирует поток данных
5. **Frame-based Protocol** - структура всех коммуникаций

### Рекомендации по реализации

1. **Используйте готовые решения** из pycozmo как основу
2. **Тестируйте Audio Takeover** с подробным логированием
3. **Мониторьте производительность** в реальном времени
4. **Оптимизируйте под свои задачи** - аудио, видео или смешанные сценарии
5. **Кэшируйте ресурсы** - особенно RLE данные изображений

### Дальнейшее развитие

1. **Адаптивные алгоритмы** - автоматическая настройка окна и таймаутов
2. **Предсказание потерь** - проактивная ретрансляция
3. **Сжатие изображений** - более эффективные алгоритмы
4. **Потоковое видео** - для более сложной визуализации
5. **ML-оптимизация** - обучение на паттернах использования

Эта архитектура обеспечивает надёжную и производительную основу для создания интерактивных приложений с Cozmo, сочетающих аудио и визуальные эффекты.