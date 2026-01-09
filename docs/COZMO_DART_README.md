# Cozmo Dart Client - Полная документация

## 🎯 Особенности

- **✅ Reliable UDP** — ретрансмиссия потерянных пакетов как в TCP
- **✅ Sliding Window** — контроль потока с подтверждением доставки
- **✅ Skip-to-Live** — аудио "догоняет" реальное время
- **✅ Простое API** — topLevel функции для быстрой работы
- **✅ Синглтон** — автоматическое управление подключением
- **✅ Без зависимостей** — только встроенные пакеты Dart
- **✅ Flutter готов** — работает на iOS, Android, macOS
- **📊 Полная диагностика** — логи всех отправленных и полученных пакетов

## 🆕 v3.2.0 — Система анимаций! 🎬

**50+ АНИМАЦИЙ** — теперь Cozmo может танцевать, celebrating, и показывать эмоции через анимации!
- ✅ **CozmoAnimation enum** — 50+ готовых анимаций (dance, celebrate, sleep, и др.)
- ✅ **playAnimation()** — воспроизведение анимаций по enum
- ✅ **playAnimationByName()** — воспроизведение по имени (строка)
- ✅ **Хеширование имен** — автоматический Trigger ID

**Категории анимаций:**
- Пробуждение и сон: wakeUp, sleep, yawn
- Счастье: happyPounce, excited, celebrate, majorWin
- Танцы: dance, danceSprint, moonwalk
- Социальные: greeting, yes, no, love
- Игры: game_win, game_lose
- И 40+ других!

## 🆕 v3.1.0 — Эмоции! 🎭

**13 ЭМОЦИЙ** — Cozmo может выражать эмоции!
- ✅ **CozmoEmotion enum** — happy, sad, surprised, thinking, и др.
- ✅ **playEmotion()** — воспроизведение эмоций

## 🆕 v3.0.0 — Reliable UDP Layer! 🚀

**РЕВОЛЮЦИОННАЯ АРХИТЕКТУРА** — теперь клиент ведет себя как TCP!
- ✅ **Ретрансмиссия** — потерянные пакеты переотправляются (RTO = 40мс)
- ✅ **Sliding Window** — окно подтвержденных пакетов (size = 8)
- ✅ **Skip-to-Live** — аудио "догоняет" реальное время при отставании
- ✅ **Главный цикл (_tick)** — единая точка управления отправкой
- ✅ **PING Keep-Alive** — поддерживает соединение без разрывов
- ✅ **Deadlock-free** — гарантированно избегает взаимной блокировки

### Что работает:

- ✅ **Reliable UDP Layer** — ретрансмиссия, sliding window, flow control
- ✅ **SetHeadAngle** — управление головой (-0.436 = вниз, 0.0 = прямо, 0.777 = вверх)
- ✅ **SetLiftHeight** — управление подъёмником (32mm = вниз, 92mm = вверх)
- ✅ **SetVolume** — управление громкостью (0-100%)
- ✅ **PlayAudio** — воспроизведение WAV файлов (22050Hz, 16-bit PCM, mono)
- ✅ **DriveWheels** — управление колесами (вперед, назад, поворот)
- ✅ **Bi-Directional Communication** — полноценная приём/отправка UDP пакетов

### Предыдущие версии:

**v2.0.0** — Flow Control для стабильного аудио

**v1.3.0** — Базовое управление Cozmo

**v1.2.0** — ROBOT Frame Handling (события от робота)

**v1.1.0** — UDP Receive Loop (приём ответов от Cozmo)

Подробнее:
- [CHANGELOG.md](CHANGELOG.md) — история изменений
- [RECEIVE_LOOP_IMPLEMENTATION.md](RECEIVE_LOOP_IMPLEMENTATION.md) — реализация receive loop
- [PROTOCOL_REFERENCE.md](PROTOCOL_REFERENCE.md) — полное описание протокола
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) — быстрая шпаргалка по командам

## 📦 Установка

### 1. Добавьте файл в проект

Скопируйте `cozmo_dart.dart` в папку `lib/` вашего Flutter проекта:

```
my_flutter_app/
├── lib/
│   ├── cozmo_dart.dart  # ← Сюда
│   └── main.dart
```

### 2. Добавьте зависимости в `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
```

Больше никаких зависимостей не нужно! Используются только встроенные пакеты Dart.

## 🚀 Быстрый старт

### Минимальный пример

```dart
import 'package:my_flutter_app/cozmo_dart.dart';

void main() async {
  // Используем topLevel функции
  final error = await connect();
  if (error != null) {
    print('Ошибка подключения: $error');
    return;
  }

  // Воспроизведение аудио (16-bit PCM, 22.05kHz, mono)
  await playAudio('/path/to/audio.wav');

  // Отключение
  await disconnect();
}
```

## 🔬 КРИТИЧЕСКИЕ ЗНАНИЯ - Природа протокола

### ⚠️ "Надежный UDP" (Reliable UDP)

**Самое важное:** Cozmo использует UDP, но требует поведения как у TCP!

#### Строгая последовательность
```
Отправили: Пакет 1 → Пакет 2 → Пакет 3
Потерян: Пакет 2
Результат: Пакет 3 ВЫБРОСЕН! Робот ждет Пакет 2 до победного.
```

**Последствие:** Любая потеря пакета разрывает поток данных навсегда (если нет ретрансмиссии).

#### Обязательная ретрансмиссия
```dart
// ❌ ПЛОХО - отправили и забыли
socket.send(packet);
// Пакет потерялся → робот завис в ожидании → connection dead

// ✅ ХОРОШО - храним и переотправляем
_inflightPackets[seq] = packet;
// Если ack не пришел → отправляем снова через RTO (20-30мс)
```

**Без ретрансмиссии:** Любой лаг Wi-Fi разрывает соединение.

---

### 🎵 Настройки для Аудио (Audio Tuning)

Чтобы звук был плавным, а соединение не рвалось:

#### 1. Размер окна (Window Size)

```dart
static const int _WINDOW_SIZE = 32; // Рекомендуется: 32-48
```

| Размер | Описание | Результат |
|--------|----------|-----------|
| **4-8** | Маленькое окно | ❌ Любой лаг опустошает буфер → щелчки/тишина |
| **16** | Среднее окно | ⚠️ Работает, но неустойчиво при плохом Wi-Fi |
| **32-48** | Большое окно | ✅ ~1 секунда звука в запасе → плавно |
| **64+** | Очень большое | ⚠️ Большая задержка, но стабильно |

**Рекомендация:** Используйте **32-48** для аудио.

#### 2. Таймаут переотправки (RTO - Retransmission Timeout)

```dart
static const int _RTO_MS = 25; // Рекомендуется: 20-30 мс
```

**Почему 20-30мс?**
- Длительность аудио пакета = **~33.7 мс** (744 сэмплов @ 22050Hz)
- Если пакет потерян → нужно переотправить **ДО** того, как робот доиграет предыдущий
- Если RTO > 33мс → будет щелчок или тишина

```
Пакет 1: [0...........33мс]
Пакет 2: [ПОТЕРЯН] ← Переотправить через 25мс!
Пакет 3:        [33...........66мс] ← Робот уже ждет данных
```

#### 3. Command ID для аудио

```dart
// ❌ ПЛОХО - "голые" u-law данные
socket.send(uLawData); // Робот пытается исполнить как код → краш

// ✅ ХОРОШО - обернуть в команду 0x8e (OutputAudio)
final packet = _createCommandPacket(0x8e, uLawData);
sendCommand(0x8e, uLawData);
```

---

### 📦 Структура пакетов и Sequence Numbers

#### Никаких пустых ENGINE фреймов!

```dart
// ❌ СМЕРТЕЛЬНО - пустой ENGINE фрейм
_sendFrame([]); // seq++ но нет данных!
// Робот: "seq вырос, но данных нет? Ошибка протокола!" → disconnect
```

**Правило:** ENGINE (0x07) фреймы ВСЕГДА содержат хотя бы один пакет.

#### PING (0x0b) для Keep-Alive

```dart
// ✅ ПРАВИЛЬНО - PING не затрагивает seq
void _sendPing() {
  w.writeUint8(0x0b); // PING тип
  w.writeUint16(0);   // seq = 0 (out-of-band)
  w.writeUint16(0);
  w.writeUint16(_lastAck); // Подтверждаем получение
  // ... тело пинга ...
}
```

**PING безопасен:**
- НЕ увеличивает sequence number
- Используется для keep-alive в простое
- Можно отправлять когда окно забито

---

### 🌊 Flow Control (Контроль потока)

#### Deadlock (Взаимная блокировка)

```dart
// ❌ ПЛОХО - блокируем всё (включая PING!)
while (_inflightPackets.length > _WINDOW_SIZE) {
  await Future.delayed(Duration(milliseconds: 5));
  // Мы ждем ACK от робота
  // Но РОБОТ тоже ждет PING от нас!
  // → Deadlock → disconnect через 5 сек
}
```

#### Правильный подход

```dart
// ✅ ПРАВИЛЬНО - главный цикл (_tick)
void _tick(Timer timer) {
  // 1. Ретрансмиссия потерянных
  _retransmitTimeoutPackets();

  // 2. Отправка новых (если окно свободно)
  if (_inflightPackets.length < _WINDOW_SIZE) {
    _sendNewPackets();
  }

  // 3. Keep-Alive (всегда отправляем PING!)
  if (now.difference(_lastSendTime) > 1 second) {
    _sendPing(); // Даже если окно забито!
  }
}
```

**Ключевой принцип:** PING должен отправляться **ВСЕГДА**, независимо от состояния окна.

---

### ⚙️ Технические константы

#### Аудио формат
```dart
const int COZMO_SAMPLE_RATE = 22050;      // 22.05 kHz
const int AUDIO_PACKET_SAMPLES = 744;     // 744 сэмплов
const int PACKET_DURATION_MS = 33.7;      // ~33.7 мс на пакет
```

#### Структура WAV
```
Формат: 16-bit PCM, Mono
Частота: 22050 Hz (ИЛИ 24000 Hz после ресемплинга)
Кодек: u-law (8-bit compressed)
```

#### Frame ID
```dart
const List<int> FRAME_ID = [0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01];
// Строка: "COZ\x03RE\x01" (7 байт)
// ВСЕГДА проверяйте перед обработкой пакета!
```

---

### 🔄 Идеальный цикл (_tick)

**Алгоритм Reliable UDP Layer:**

```dart
void _tick(Timer timer) {
  // 1. УДАЛИТЬ подтвержденное
  // Робот прислал ack=42 → удаляем все пакеты с seq ≤ 42
  _inflightPackets.removeWhere((seq, pkt) =>
    _getSeqDistance(seq, _lastRemoteAck) <= 0
  );

  // 2. РЕТРАНСКМИССИЯ потерянных
  // Если пакет не подтвержден > RTO_MS → отправляем снова
  for (var pkt in _inflightPackets.values) {
    if (now.difference(pkt.lastSentTime).inMilliseconds > _RTO_MS) {
      _sendRaw(pkt.frameData);
      pkt.lastSentTime = now;
      pkt.retries++;
      return; // Отправили один → выходим
    }
  }

  // 3. ОТПРАВИТЬ новые (если окно свободно)
  while (_inflightPackets.length < _WINDOW_SIZE &&
         _outboundQueue.isNotEmpty) {
    final payload = _outboundQueue.removeFirst();
    _sendReliableFrame(payload);
  }

  // 4. KEEP-ALIVE (PING)
  // Если ничего не отправляли > 1 сек → шлем PING
  if (now.difference(_lastSendTime).inMilliseconds > 1000) {
    _sendPing();
  }
}
```

**Порядок важен:**
1. Сначала очистить подтвержденные
2. Затем ретранслировать потерянные
3. Потом отправить новые
4. Всегда поддерживать keep-alive

---

## 📱 Flutter Примеры

### Пример 1: Виджет управления

```dart
import 'package:flutter/material.dart';
import 'cozmo_dart.dart';

class CozmoScreen extends StatefulWidget {
  @override
  _CozmoScreenState createState() => _CozmoScreenState();
}

class _CozmoScreenState extends State<CozmoScreen> {
  bool _isConnected = false;
  bool _isPlaying = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final error = await connect();
    if (error == null) {
      setState(() => _isConnected = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка подключения: $error')),
      );
    }
  }

  Future<void> _playAudio() async {
    if (!_isConnected) return;

    setState(() => _isPlaying = true);
    _progress = 0.0;

    try {
      // Путь к файлу (используйте path_provider для кроссплатформенных путей)
      final audioPath = '/path/to/audio.wav';

      await playAudio(
        audioPath,
        onProgress: (progress) {
          setState(() => _progress = progress);
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка воспроизведения: $e')),
      );
    } finally {
      setState(() => _isPlaying = false);
    }
  }

  @override
  void dispose() {
    if (_isConnected) {
      disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cozmo Control'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Статус
            Card(
              child: ListTile(
                leading: Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                title: Text(_isConnected ? 'Подключено' : 'Не подключено'),
                trailing: _isConnected
                    ? ElevatedButton(
                        onPressed: () async {
                          await disconnect();
                          setState(() => _isConnected = false);
                        },
                        child: Text('Отключить'),
                      )
                    : ElevatedButton(
                        onPressed: _connect,
                        child: Text('Подключить'),
                      ),
              ),
            ),

            // Прогресс
            if (_isPlaying)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text('Воспроизведение...'),
                      SizedBox(height: 8),
                      LinearProgressIndicator(value: _progress),
                      SizedBox(height: 8),
                      Text('${(_progress * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              ),

            // Кнопка воспроизведения
            Card(
              child: ListTile(
                leading: Icon(Icons.play_arrow),
                title: Text('Воспроизвести аудио'),
                onTap: _isConnected && !_isPlaying ? _playAudio : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Пример 2: Генерация WAV в Flutter

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> generateTestWav() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/test.wav');

  // Создаём простой WAV файл (16-bit PCM, 22.05kHz, mono)
  final sampleRate = 22050;
  final duration = 1; // 1 секунда
  final numSamples = sampleRate * duration;

  final writer = file.openWrite();

  // WAV Header
  writer.write('RIFF'); // ChunkID
  writer.write(36 + numSamples * 2); // ChunkSize (будет обновлено позже)
  writer.write('WAVE'); // Format

  writer.write('fmt '); // Subchunk1ID
  writer.write(16); // Subchunk1Size (for PCM)
  writer.write(1); // AudioFormat (PCM = 1)
  writer.write(1); // NumChannels (mono)
  writer.write(sampleRate); // SampleRate
  writer.write(sampleRate * 2); // ByteRate
  writer.write(2); // BlockAlign
  writer.write(16); // BitsPerSample

  writer.write('data'); // Subchunk2ID
  writer.write(numSamples * 2); // Subchunk2Size

  // Audio Data (простая синусоида 440 Hz)
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sample = (sin(2 * pi * 440 * t) * 32767).round();
    writer.write(sample & 0xFF); // Little-endian
    writer.write((sample >> 8) & 0xFF);
  }

  await writer.close();

  return file.path;
}
```

### Пример 3: Загрузка WAV из assets

```dart
import 'package:flutter/services.dart';

Future<Uint8List> loadWavFromAssets(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  return byteData.buffer.asUint8List();
}

// Использование
final audioBytes = await loadWavFromAssets('assets/audio.wav');
// Сохраняем во временный файл
final tempDir = await getTemporaryDirectory();
final tempFile = File('${tempDir.path}/audio.wav');
await tempFile.writeAsBytes(audioBytes);

// Воспроизводим
await cozmo.playAudio(tempFile.path);
```

### Пример 4: Streaming аудио (очередь воспроизведения)

```dart
// Воспроизвести без блокировки выполнения
await playAudioStreaming('/path/to/audio1.wav');

// Можно сразу добавить ещё файлы - они будут играть подряд
await playAudioStreaming('/path/to/audio2.wav');
await playAudioStreaming('/path/to/audio3.wav');

// Проверить сколько пакетов в очереди
print('В очереди: $audioQueueLength пакетов');

// Остановить и очистить очередь когда нужно
clearAudioQueue();
```

**Когда использовать streaming:**
- ✅ Непрерывное воспроизведение нескольких файлов
- ✅ Фоновая музыка в игре
- ✅ TTS (Text-to-Speech) в реальном времени
- ✅ Микрофон (если хотите транслировать голос)

## 🎵 Подготовка аудио файлов

### Требования к WAV файлам

- **Формат**: WAV (RIFF)
- **Кодек**: 16-bit PCM
- **Частота дискретизации**: 22.05 kHz (22050 Hz)
- **Каналы**: Mono (1 канал)
- **Битность**: 16-bit

### Конвертация через FFmpeg

```bash
# Из MP3 в Cozmo формат
ffmpeg -i input.mp3 -ar 22050 -ac 1 -acodec pcm_s16le output.wav

# Из другого формата
ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -ar 22050 -ac 1 output.wav
```

### Конвертация через Python

```python
from scipy.io import wavfile
import numpy as np

# Загрузка аудио
rate, data = wavfile.read('input.wav')

# Конвертация в моно
if len(data.shape) > 1:
    data = data.mean(axis=1)

# Ресемплинг до 22050 Hz
if rate != 22050:
    from scipy.signal import resample
    data = resample(data, int(len(data) * 22050 / rate))

# Конвертация в 16-bit
data = (data * 32767).astype(np.int16)

# Сохранение
wavfile.write('output.wav', 22050, data)
```

## 🔧 API Reference

### TopLevel функции

Основной API для работы с Cozmo. Все функции работают через синглтон `CozmoClient.instance`.

#### `connect({Duration timeout = const Duration(seconds: 10)})`

Подключается к Cozmo роботу.

**Возвращает:**
- `null` - при успешном подключении
- `String` - текст ошибки при неудаче

**Параметры:**
- `timeout` - таймаут подключения (по умолчанию 10 секунд)

**Пример:**
```dart
final error = await connect();
if (error != null) {
  print('Ошибка: $error');
} else {
  print('Подключено!');
}
```

---

#### `disconnect()`

Отключается от Cozmo робота.

**Пример:**
```dart
await disconnect();
```

---

#### `playAudio(String wavFilePath, {void Function(double progress)? onProgress})`

Воспроизводит WAV файл через Cozmo.

**Параметры:**
- `wavFilePath` - путь к WAV файлу
- `onProgress` - callback для отслеживания прогресса (0.0 - 1.0)

**Исключения:**
- `CozmoException` - если не подключено или файл не найден

**Пример:**
```dart
await playAudio(
  '/path/to/audio.wav',
  onProgress: (progress) {
    print('Прогресс: ${(progress * 100).toInt()}%');
  },
);
```

---

#### `setVolume(int volume)`

Устанавливает громкость воспроизведения.

**Параметры:**
- `volume` - громкость от 0 до 100 (0-100%)

**Пример:**
```dart
await setVolume(75); // 75% громкости
await setVolume(100); // 100% громкости (максимум)
await setVolume(50); // 50% громкости
```

---

#### `playAudioStreaming(String wavFilePath)`

Воспроизводит WAV файл через очередь (streaming mode). Не блокирует execution.

**Преимущества над `playAudio()`:**
- Не блокирует выполнение кода
- Можно добавлять больше аудио пока воспроизводится
- Подходит для непрерывного воспроизведения

**Пример:**
```dart
// Воспроизвести без блокировки
await playAudioStreaming('/path/to/audio1.wav');
// Можно сразу добавить ещё файлы
await playAudioStreaming('/path/to/audio2.wav');
```

---

#### `enqueueAudio(List<Uint8List> packets)`

Добавляет аудио пакеты в очередь для воспроизведения.

**Использование:**
```dart
// Конвертировать аудио в пакеты заранее
final packets = convertAudioToPackets(audioData);

// Добавить в очередь для воспроизведения
enqueueAudio(packets);

// Проверить размер очереди
print('В очереди: $audioQueueLength пакетов');
```

---

#### `clearAudioQueue()`

Очищает очередь аудио и останавливает воспроизведение.

**Пример:**
```dart
// Остановить воспроизведение и очистить очередь
clearAudioQueue();
```

---

#### `audioQueueLength` → int

Возвращает текущий размер очереди аудио пакетов.

**Пример:**
```dart
if (audioQueueLength > 0) {
  print('Аудио воспроизводится, осталось $audioQueueLength пакетов');
}
```

---

#### `setLiftHeight(double height, {double speed, double acceleration})`

Устанавливает высоту подъёмника Cozmo (lift).

**Параметры:**
- `height` - высота в миллиметрах (32.0 = вниз, 92.0 = вверх)
- `speed` - скорость в рад/сек (по умолчанию 3.0)
- `acceleration` - ускорение в рад/сек² (по умолчанию 20.0)

**Диапазон:** 32.0 мм (вниз) → 92.0 мм (вверх)

**Пример:**
```dart
// Поднять подъёмник максимально вверх
await setLiftHeight(92.0);

// Опустить подъёмник вниз
await setLiftHeight(32.0);

// Среднее положение
await setLiftHeight(62.0);

// Медленно вверх
await setLiftHeight(92.0, speed: 2.0);
```

---

#### `setHeadAngle(double angle, {double speed, double acceleration})`

Устанавливает угол поворота головы Cozmo.

**Параметры:**
- `angle` - угол в радианах (-0.436 = вниз, 0.0 = прямо, 0.777 = вверх)
- `speed` - скорость в рад/сек (по умолчанию 10.0)
- `acceleration` - ускорение в рад/сек² (по умолчанию 10.0)

**Диапазон:** -25° (-0.436 рад) → +44.5° (0.777 рад)

**Пример:**
```dart
// Поднять голову максимально вверх
await setHeadAngle(0.777);

// Голова прямо (нормальное положение)
await setHeadAngle(0.0);

// Опустить голову максимально вниз
await setHeadAngle(-0.436);

// Медленно вверх
await setHeadAngle(0.5, speed: 5.0);
```

---

#### `playEmotion(CozmoEmotion emotion, {int loops = 1, bool wait = true})`

Воспроизводит анимацию эмоции на Cozmo.

**Параметры:**
- `emotion` - эмоция из перечисления `CozmoEmotion`
- `loops` - количество повторений (по умолчанию 1)
- `wait` - ждать завершения анимации (по умолчанию true)

**Доступные эмоции:**
```dart
// Основные эмоции
CozmoEmotion.happy        // Счастье
CozmoEmotion.sad          // Грусть
CozmoEmotion.surprised    // Удивление
CozmoEmotion.thinking     // Задумчивость
CozmoEmotion.frustrated   // Разочарование/Злость
CozmoEmotion.scared       // Испуг
CozmoEmotion.sleepy       // Сонливость

// Действия животных
CozmoEmotion.dog          // Собака
CozmoEmotion.cat          // Кошка

// Игровые реакции
CozmoEmotion.win          // Победа
CozmoEmotion.lose         // Проигрыш

// Общение
CozmoEmotion.chatty       // Болтовня
CozmoEmotion.greeting     // Приветствие
CozmoEmotion.sneeze       // Чихание
CozmoEmotion.hiccup       // Икота
```

**Пример:**
```dart
// Воспроизвести эмоцию "приветствие"
await CozmoClient.instance.playEmotion(CozmoEmotion.greeting);

// Воспроизвести эмоцию "счастье" 2 раза
await playEmotion(CozmoEmotion.happy, loops: 2);

// Воспроизвести без ожидания завершения
await playEmotion(CozmoEmotion.thinking, wait: false);
// Можно сразу делать что-то другое...

// Интеграция с OpenAI Realtime
// В ответе на событие:
if (responseText.contains('вау')) {
  await playEmotion(CozmoEmotion.surprised);
}
```

**Технические детали:**
- Использует команду `PlayAnimationTrigger` (0x26)
- ID эмоций соответствуют Code Lab Triggers из pycozmo
- Длительность анимации ~1-2 секунды
- При `wait=true` метод блокирует выполнение до завершения анимации

---

#### `playAnimation(CozmoAnimation animation, {int loops = 1})`

Воспроизводит анимацию на Cozmo по имени из enum `CozmoAnimation`.

**Параметры:**
- `animation` - анимация из перечисления `CozmoAnimation`
- `loops` - количество повторений (по умолчанию 1)

**Доступные анимации (50+):**
```dart
// === Пробуждение и сон ===
CozmoAnimation.wakeUp        // anim_launch_wakeup_01
CozmoAnimation.sleep         // anim_sleeping_01
CozmoAnimation.yawn          // anim_yawn_01

// === Счастье и радость ===
CozmoAnimation.happyPounce   // anim_happy_pounce_01
CozmoAnimation.happyYes      // anim_happy_yes_01
CozmoAnimation.excited       // anim_excited_01
CozmoAnimation.majorWin      // anim_majorwin_01
CozmoAnimation.celebrate     // anim_celebrate_01

// === Грусть ===
CozmoAnimation.sadReactions  // anim_sad_reactions_01
CozmoAnimation.crying        // anim_crying_01
CozmoAnimation.frustrated    // anim_frustrated_01

// === Удивление ===
CozmoAnimation.surprised     // anim_surprised_01
CozmoAnimation.what          // anim_what_01

// === Думает ===
CozmoAnimation.thinking      // anim_thinking_01
CozmoAnimation.processing    // anim_processing_01
CozmoAnimation.confused      // anim_confused_01

// === Страх ===
CozmoAnimation.scared        // anim_scared_01
CozmoAnimation.startled      // anim_startled_01
CozmoAnimation.flee          // anim_flee_01

// === Танцы и веселье ===
CozmoAnimation.dance         // anim_dance_01
CozmoAnimation.danceSprint   // anim_dance_sprint_01
CozmoAnimation.moonwalk      // anim_moonwalk_01
CozmoAnimation.burp          // anim_burp_01
CozmoAnimation.sneeze        // anim_sneeze_01
CozmoAnimation.hiccup        // anim_hiccup_01

// === Социальные реакции ===
CozmoAnimation.greeting      // anim_greeting_01
CozmoAnimation.sayName       // anim_sayname_01
CozmoAnimation.yes           // anim_yes_01
CozmoAnimation.no            // anim_no_01
CozmoAnimation.love          // anim_love_01
CozmoAnimation.like          // anim_like_01
CozmoAnimation.dislike       // anim_dislike_01
CozmoAnimation.bored         // anim_bored_01

// === Игры ===
CozmoAnimation.game_win      // anim_gamewin_01
CozmoAnimation.game_lose     // anim_gamelose_01
CozmoAnimation.scoreGoal     // anim_scoregoal_01

// === Движения ===
CozmoAnimation.rollOver      // anim_rollover_01
CozmoAnimation.shake         // anim_shake_01
CozmoAnimation.backup        // anim_backup_01
CozmoAnimation.turnLeft      // anim_turn_left_01
CozmoAnimation.turnRight     // anim_turn_right_01

// === Действия ===
CozmoAnimation.seeCharger    // anim_seecharger_01
CozmoAnimation.onCharger     // anim_oncharger_01
CozmoAnimation.pickupCube    // anim_pickupcube_01
CozmoAnimation.placeCube     // anim_placecube_01

// === Кубы ===
CozmoAnimation.cubePounce    // anim_cubepounce_01
CozmoAnimation.cubeWhack     // anim_cubewhack_01

// === Лицо ===
CozmoAnimation.faceAngry     // anim_face_angry_01
CozmoAnimation.faceSad       // anim_face_sad_01
CozmoAnimation.faceSurprised // anim_face_surprised_01

// === Скорость ===
CozmoAnimation.speedLines    // anim_speedlines_01
CozmoAnimation.dizzy         // anim_dizzy_01

// === Разное ===
CozmoAnimation.knockOver     // anim_knockover_01
CozmoAnimation.getUp         // anim_getup_01
CozmoAnimation.fail          // anim_fail_01
CozmoAnimation.look          // anim_look_01
```

**Пример:**
```dart
// Танец
await CozmoClient.instance.playAnimation(CozmoAnimation.dance);

// С повторением
await playAnimation(CozmoAnimation.celebrate, loops: 2);

// Комбинация эмоций и анимаций
await playEmotion(CozmoEmotion.happy);
await playAnimation(CozmoAnimation.dance);

// Последовательность анимаций
await playAnimation(CozmoAnimation.wakeUp);
await Future.delayed(Duration(seconds: 1));
await playAnimation(CozmoAnimation.yes);
await Future.delayed(Duration(seconds: 1));
await playAnimation(CozmoAnimation.celebrate);
```

---

#### `playAnimationByName(String animName, {int loops = 1})`

Воспроизводит анимацию по имени (строка). Полезно для анимаций, которых нет в `CozmoAnimation` enum.

**Параметры:**
- `animName` - имя анимации (например "anim_dance_01")
- `loops` - количество повторений (по умолчанию 1)

**Пример:**
```dart
// По имени анимации
await playAnimationByName("anim_speedlines_01");

// С повторением
await playAnimationByName("anim_celebrate_01", loops: 3);

// Можно использовать любые имена анимаций из pycozmo
await playAnimationByName("anim_launch_wakeup_01");
```

**Технические детали:**
- Автоматически вычисляет Trigger ID через хеширование имени
- Использует команду `PlayAnimationTrigger` (0x26)
- Имена анимаций соответствуют pycozmo animation names
- Для получения полного списка анимаций используйте pycozmo скрипт `list_animations.py`

---

### CozmoClient класс

Синглтон класс для управления Cozmo роботом. Обычно используется через topLevel функции, но можно обращаться напрямую.

#### Свойства

##### `CozmoClient.instance` → CozmoClient

Возвращает единственный экземпляр синглтона.

**Пример:**
```dart
// Проверка статуса подключения
if (CozmoClient.instance.isConnected) {
  print('Подключено!');
}
```

##### `isConnected` → bool

Статус подключения к Cozmo.

**Пример:**
```dart
if (CozmoClient.instance.isConnected) {
  print('Подключено!');
}
```

## 📋 Подготовка устройства

### 1. Включите Cozmo

Поставьте Cozmo на зарядную платформу и включите.

### 2. Получите Wi-Fi пароль

1. Покачайте подъёмник вверх-вниз 3 раза
2. Коzmo произнесёт пароль (12 символов)
3. ИЛИ используйте пароль по умолчанию: `aaaaaaaaaaaa`

### 3. Подключите устройство к Cozmo Wi-Fi

**macOS:**
1. System Settings → Network → Wi-Fi
2. Выберите сеть `Cozmo_XXXXXX`
3. Введите пароль

**iOS/Android:**
1. Settings → Wi-Fi
2. Выберите сеть `Cozmo_XXXXXX`
3. Введите пароль

### 4. Запустите Flutter приложение

```bash
flutter run
```

## 🐛 Устранение проблем

### Проблема: Не подключается к Cozmo

**Решения:**
1. Убедитесь, что устройство подключено к Wi-Fi `Cozmo_XXXXXX`
2. Проверьте, что Cozmo включен и на зарядной платформе
3. Никто другой не подключён к Cozmo
4. Проверьте сетевые настройки устройства

### Проблема: Аудио не воспроизводится

**Решения:**
1. Проверьте формат WAV файла:
   ```bash
   file audio.wav
   # Должно быть: "RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 22050 Hz"
   ```
2. Убедитесь, что файл существует и доступен
3. Проверьте громкость (должна быть > 0)

### Проблема: Звук прерывистый

**Решения:**
1. ✅ **НЕ используйте точный тайминг** - шлите пакеты максимально быстро!
2. ✅ **Только backpressure** - ждите только если очередь > 100
3. Убедитесь, что сигнал Wi-Fi хороший
4. Попробуйте другой WAV файл

**⚠️ КРИТИЧЕСКОЕ ПРАВИЛО (изучено из pycozmo):**

PyCozmo НЕ контролирует тайминг на уровне приложения! Вместо этого:

```python
# ПРАВИЛЬНО (как pycozmo conn.py):
class SendThread(Thread):
    COLLECT_INTERVAL = 1/30 / 3  # ~11 мс - только для сбора пакетов

    def send(self, data):
        self.queue.put(data)  # Просто кладем в очередь БЕЗ задержек!
```

**❌ НЕ ДЕЛАЙТЕ (наша ошибка):**
```dart
// ПЛОХО - искусственное задерживание
final targetTime = startTime + ((i + 1) * packetDurationUs);
await Future.delayed(Duration(microseconds: targetTime - now));
// Это создает бутылочное горлышко в Dart!
```

**✅ ДЕЛАЙТЕ (как pycozmo):**
```dart
// ХОРОШО - шлем максимально быстро
for (int i = 0; i < packets.length; i++) {
    // Только backpressure тормозит нас
    while (_client.outboundQueueLength > 100) {
        await Future.delayed(const Duration(milliseconds: 1));
    }
    _client.sendRawPacket(packets[i]);  // Шлем сразу!
}
```

**Почему это работает:**
1. Пакеты кладутся в очередь **как можно быстрее**
2. SendThread (5ms ticker) собирает и отправляет их по UDP
3. Робот сам буферизирует и воспроизводит с нужной скоростью
4. Никакого искусственного задерживания на уровне приложения!

## 📝 Константы протокола

```dart
const String COZMO_IP = '172.31.1.1';        // IP адрес Cozmo
const int COZMO_PORT = 5551;                   // UDP порт
const int COZMO_SAMPLE_RATE = 22050;           // Частота дискретизации
const int AUDIO_PACKET_SAMPLES = 744;          // Сэмплов в пакете
```

## 🚀 Производительность

- **Размер пакета**: 744 сэмплов (744 байта u-law)
- **Длительность пакета**: ~33.7 мс
- **Задержка между пакетами**: 33.7 мс
- **Скорость передачи**: ~22 KB/сек

## ⚠️ Ограничения

1. **Только iOS/macOS/Android** - Desktop не поддерживается (нет UDP сокетов)
2. **Только Wi-Fi сеть Cozmo** - устройство должно быть подключено к Cozmo_XXXXXX
3. **Один клиент** - только одно подключение к Cozmo одновременно

## 🔬 Детали реализации

### ⚡ AnimationController и координация аудио/экрана

**Проблема:** AnimController шлет OutputSilence каждые 33мс, что конфликтует с аудио пакетами.

**Решение от pycozmo:** "Audio Takeover" pattern

```dart
class CozmoAnimController {
  bool _isAudioBusy = false;

  void _tick() {
    // 1. АУДИО / ТИШИНА
    // Если аудио занято - МЫ МОЛЧИМ (не шлем OutputSilence)
    if (!_isAudioBusy) {
      _client.sendCommand(CozmoCmd.outputSilence, []);
    }

    // 2. ЭКРАН (обновляем даже во время аудио!)
    if (_tickCounter % 30 == 0 && _currentImagePayload != null) {
      _client.sendCommand(CozmoCmd.displayImage, _currentImagePayload!);
    }

    _tickCounter++;
  }

  void setAudioBusy(bool busy) {
    _isAudioBusy = busy;  // Аудио модуль управляет этим флагом
  }
}
```

**Использование в аудио:**
```dart
Future<void> _streamPackets(List<List<int>> packets) async {
  // 1. ЗАХВАТЫВАЕМ КОНТРОЛЬ
  _animController.setAudioBusy(true);  // Контроллер замолкает

  try {
    // 2. БЫСТРАЯ ОТПРАВКА (без тайминга!)
    for (int i = 0; i < packets.length; i++) {
      while (_client.outboundQueueLength > 100) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
      _client.sendRawPacket(packets[i]);
    }

    // 3. Ждем пока очередь опустеет
    while (_client.outboundQueueLength > 0) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  } finally {
    // 4. ВОЗВРАЩАЕМ КОНТРОЛЬ
    _animController.setAudioBusy(false);  // Контроллер снова шлет silence
  }
}
```

**Ключевые принципы:**
1. ✅ **Fast sending** - пакеты шлются максимально быстро
2. ✅ **No app-level timing** - тайминг контролируется сетевым слоем
3. ✅ **Audio takeover** - контроллер замолкает во время аудио
4. ✅ **Screen stays on** - DisplayImage обновляется даже во время аудио
5. ✅ **Backpressure only** - ждем только если очередь переполнена

### Протокол

- **Транспорт**: UDP
- **Фрейминг**: Custom binary protocol (основан на pycozmo)
- **Аудио кодек**: u-law (8-bit compressed)
- **Пакеты**: 744 сэмплов на пакет @ 22.05kHz

### 🖼️ DisplayImage - Вывод изображения на экран

**Критически важно:** OutputSilence (0x8f) должен отправляться **ДО** DisplayImage!

```dart
// ❌ ПЛОХО - без OutputSilence
_client.sendCommand(CozmoCmd.displayImage, payload);
// Может не заработать или оборвать соединение

// ✅ ХОРОШО - с OutputSilence
_client.sendCommand(CozmoCmd.outputSilence, []);
await Future.delayed(const Duration(milliseconds: 1));
_client.sendCommand(CozmoCmd.displayImage, payload);
```

**Формат изображения:**
- Разрешение: 128x32 пикселя
- Цвета: 1-bit (черный/белый)
- Компрессия: RLE (Run-Length Encoding)
- Структура: [Flags=3, ImgID=1, ChunkID=0, RLE Data...]

**RLE кодирование (column-based):**
```
Skip (0x00-0x3F): Пропустить X+1 пустых столбцов
Repeat (0x40-0x7F): Повторить X+1 одинаковых столбцов
Draw (0x80/0xC0): Нарисовать столбец с RLE пикселей
```

**Пример создания глаз:**
```dart
final img = CozmoSimpleImage.createEyes();
// Левый глаз (35-55, 8-16)
img.drawRect(35, 8, 55, 16);
// Правый глаз (73-93, 8-16)
img.drawRect(73, 8, 93, 16);
// Улыбка (линия от 40 до 88 на y=24)
for (int x = 40; x <= 88; x++) {
  img.pixels[24 * 128 + x] = 255;
}

robot.displayImage(img);
```

**Ограничения:**
- Экран гаснет через 30 секунд без обновления
- AnimController должен обновлять экран раз в секунду
- Сложные изображения (>79 bytes) могут вызывать баги RLE
- Repeat функцию лучше отключить для стабильности

### Frame Format

```
[FRAME_ID: 7 bytes][Type: 1][FirstSeq: 2][Seq: 2][Ack: 2][Packets...]
```

### Audio Packet Format

```
[Type: 1][Length: 2][CmdID: 1][Samples: 744]
```

## 📚 Дополнительные ресурсы

### Документация по протоколу:

- **[PROTOCOL_REFERENCE.md](PROTOCOL_REFERENCE.md)** — полное описание протокола Cozmo
  - FrameType и PacketType enum'ы
  - Структура всех команд и событий
  - u-law кодирование аудио
  - Примеры пакетов в hex
  - Анализ pycozmo исходников

- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** — быстрая шпаргалка
  - Все Frame Types и Packet Types
  - Карта важных команд (Enable, SetHeadAngle, OutputAudio, etc.)
  - RobotState структура события
  - Константы робота
  - Примеры пакетов в hex

- **[RECEIVE_LOOP_IMPLEMENTATION.md](RECEIVE_LOOP_IMPLEMENTATION.md)** — реализация receive loop
  - Как работает би-directional коммуникация
  - Детали реализации UDP приёма
  - Диагностика проблем

- **[CHANGELOG.md](CHANGELOG.md)** — история версий
  - v1.2.0 — ROBOT frame support
  - v1.1.0 — Bi-directional communication
  - v1.0.0 — Первый релиз

### External ссылки:

- **pycozmo**: https://github.com/zayfod/pycozmo
- **Cozmo SDK**: https://github.com/anki/cozmo-python-sdk
- **u-law encoding**: https://en.wikipedia.org/wiki/%CE%9C-law_algorithm

## 📄 Лицензия

Этот код основан на исследовании протокола Cozmo и может использоваться свободно.
