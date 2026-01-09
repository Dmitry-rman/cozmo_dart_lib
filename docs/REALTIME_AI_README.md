# Realtime AI для Cozmo

Система голосового взаимодействия с роботом Cozmo через OpenAI Realtime API.

## Архитектура

```
lib/custom_code/
├── cozmo_class.dart          # Управление роботом (UDP, пакеты)
├── realtime_ai.dart          # OpenAI API + WebRTC
├── audio_processor.dart      # Обработка аудио и эффекты
├── models/
│   └── ai_config.dart        # Конфигурация AI
└── examples/
    └── realtime_ai_example.dart  # Примеры использования
```

### Разделение ответственности

- **CozmoClient** ([cozmo_class.dart](cozmo_class.dart)):
  - ONLY robot control (head, lift, audio playback)
  - UDP коммуникация с Cozmo
  - Управление пакетами протокола

- **RealtimeAI** ([realtime_ai.dart](realtime_ai.dart)):
  - OpenAI Realtime API сессии
  - WebRTC peer connection
  - Микрофон и аудио потоки
  - Управление состоянием разговора

- **AudioProcessor** ([audio_processor.dart](audio_processor.dart)):
  - Применение голосовых эффектов
  - Конвертация PCM ↔ WAV
  - Интеграция с FFmpeg

## Установка

### 1. Зависимости

Добавьте в `pubspec.yaml`:

```yaml
dependencies:
  flutter_webrtc: ^0.9.48
  http: ^1.2.0
```

Установите:

```bash
flutter pub get
```

### 2. FFmpeg (опционально)

Для голосовых эффектов нужен FFmpeg:

**macOS:**
```bash
brew install ffmpeg
```

**Linux:**
```bash
sudo apt install ffmpeg
```

**Windows:**
Скачайте с https://ffmpeg.org/download.html

### 3. Переменные окружения

Создайте файл `.env` в корне проекта:

```env
API_REALTIME_SESSION_URL=https://api.openai.com/v1/realtime
API_TOKEN=your_openai_api_key
API_SECRET=your_api_secret
```

## Использование

### Базовый пример

```dart
import 'package:cozmo_app/custom_code/cozmo_class.dart';
import 'package:cozmo_app/custom_code/models/ai_config.dart';
import 'package:cozmo_app/custom_code/realtime_ai.dart';

void main() async {
  // 1. Конфигурация
  final config = AIConfig(
    sessionUrl: 'https://api.openai.com/v1/realtime',
    apiToken: 'your_token',
    apiSecret: 'your_secret',
    systemInstructions: 'Ты робот Cozmo. Отвечай коротко.',
    voice: 'alloy',
    language: 'ru',
    voiceCode: 9982,
  );

  // 2. Подключение к Cozmo
  final cozmo = CozmoClient();
  await cozmo.connect(
    ip: InternetAddress('172.31.1.1'),
    port: 5551,
  );

  // 3. Создание Realtime AI
  final ai = RealtimeAI(config: config, cozmo: cozmo);
  await ai.connect();

  // 4. Говорите с роботом!
  // ... (код будет поддерживать соединение)

  // 5. Отключение
  await ai.disconnect();
  await cozmo.disconnect();
}
```

### Настройка голосовых эффектов

```dart
import 'package:cozmo_app/custom_code/audio_processor.dart';

// Применить робо-эффекты к WAV файлу
await AudioProcessor.applyRobotEffect(
  inputWav: 'input.wav',
  outputWav: 'output.wav',
  pitch: 1.35,   // Высота голоса (>1.0 = выше)
  tempo: 0.9,    // Скорость (<1.0 = медленнее)
);
```

**Параметры эффектов:**

| Эффект | Значение | Описание |
|--------|----------|----------|
| `pitch` | 0.8 - 1.5 | Изменение высоты голоса |
| `tempo` | 0.5 - 1.5 | Скорость воспроизведения |

**Рекомендуемые пресеты:**

```dart
// Обычный голос
{'pitch': 1.0, 'tempo': 1.0}

// Робот Cozmo (по умолчанию)
{'pitch': 1.35, 'tempo': 0.9}

// Высокий робот
{'pitch': 1.5, 'tempo': 0.8}

// Низкий робот
{'pitch': 0.8, 'tempo': 1.2}
```

## API Reference

### AIConfig

Конфигурация OpenAI Realtime API.

```dart
final config = AIConfig(
  sessionUrl: String,      // URL для создания сессии
  apiToken: String,        // API токен
  apiSecret: String,       // API секрет
  systemInstructions: String,  // Системные инструкции (default: Cozmo persona)
  voice: String,           // Голос (default: 'alloy')
  language: String,        // Язык (default: 'ru')
  voiceCode: int,          // Код голоса (default: 9982 = russian)
);
```

### RealtimeAI

Главный класс для голосового взаимодействия.

**Методы:**

```dart
// Подключение к OpenAI Realtime API
Future<void> connect()

// Отключение
Future<void> disconnect()

// Состояние
bool get isConnected
bool get isRobotSpeaking
Stream<List<int>> get audioStream
```

**События:**

```dart
// Подписка на аудио поток
ai.audioStream.listen((audioChunk) {
  print('Получено ${audioChunk.length} байт');
});
```

### AudioProcessor

Обработка аудио и эффекты.

**Статические методы:**

```dart
// Применить робо-эффекты (требует FFmpeg)
static Future<bool> applyRobotEffect({
  required String inputWav,
  required String outputWav,
  double pitch = 1.35,
  double tempo = 0.9,
})

// Конвертировать PCM в WAV
static Uint8List pcmToWav(Uint8List pcmData)

// Сохранить WAV файл
static Future<bool> saveWavFile(String path, Uint8List wavData)

// Простые эффекты без FFmpeg
static Uint8List applySimpleEffects(
  Uint8List pcmData, {
  double volume = 1.5,
  double echoDelay = 0.1,
  double echoDecay = 0.3,
})
```

## Протокол

### WebRTC Signal Flow

```
Приложение                    OpenAI API
   |                              |
   |---(1) SDP Offer------------->|
   |                              |
   |<--(2) SDP Answer-------------|
   |                              |
   |---(3) Audio Stream---------->|
   |    (Microphone PCM)          |
   |                              |
   |<--(4) Audio Stream-----------|
   |    (Response PCM)            |
   |                              |
   |<--(5) Messages---------------|
   |    (Transcripts, events)     |
```

### Аудио формат

**От микрофона → OpenAI:**
- Формат: PCM 16-bit
- Частота: 16kHz (настраивается)
- Каналы: Mono

**От OpenAI → Cozmo:**
- Формат: PCM 16-bit
- Частота: 22050Hz (требование Cozmo)
- Каналы: Mono
- Эффекты: FFmpeg filters

### FFmpeg фильтры

```bash
asetrate=22050*1.35,   # Изменение высоты (pitch)
atempo=0.9,            # Скорость (tempo)
highpass=f=200,        # Фильтр низких частот
aecho=0.8:0.8:10:0.5,  # Эхо эффект
volume=2.0             # Громкость
```

## Troubleshooting

### FFmpeg не найден

**Ошибка:** `❌ Ошибка запуска FFmpeg`

**Решение:**
1. Установите FFmpeg (см. выше)
2. Проверьте установку: `ffmpeg -version`
3. Если не используется, можно применять простые эффекты через `applySimpleEffects()`

### WebRTC не работает

**Ошибка:** Ошибки при создании peer connection

**Решение:**
1. Проверьте права на микрофон в `Info.plist` (iOS) или `AndroidManifest.xml` (Android)
2. Убедитесь, что `flutter_webrtc` правильно инициализирован
3. Проверьте сетевое соединение

### Cozmo не воспроизводит аудио

**Проверьте:**
1. Cozmo подключен и готов (`cozmo.isConnected`)
2. Громкость установлена (`cozmo.setVolume()`)
3. Аудио формат: PCM 16-bit, 22050Hz, mono
4. WAV файл конвертирован в пакеты правильно

### Робот "заикается"

**Причина:** Буфер аудио пуст или пакеты приходят слишком медленно

**Решение:**
1. Используйте `playAudioStreaming()` вместо пакетного воспроизведения
2. Увеличьте размер очереди аудио
3. Проверьте скорость интернета

## Производительность

### Оптимизация

1. **Аудио очередь:** Используйте `playAudioStreaming()` для плавного воспроизведения
2. **Обработка:** Применяйте эффекты асинхронно
3. **Буферизация:** Настраивайте размер буфера для задержки

### Метрики

| Метрика | Значение |
|---------|----------|
| Задержка речи | ~1-2 сек |
| Частота пакетов | 30 fps (33ms) |
| Размер пакета | 744 сэмплов |
| Качество звука | 16-bit PCM |

## TODO

- [ ] Полная реализация WebRTC с flutter_webrtc
- [ ] Запись микрофона в Flutter
- [ ] Конвертация аудио форматов на лету
- [ ] Кэширование эффектов FFmpeg
- [ ] UI для управления параметрами
- [ ] Настройка VAD (Voice Activity Detection)
- [ ] Экспрессия лица во время речи
- [ ] Движения во время речи

## Лицензия

MIT License - см. LICENSE файл

## Ссылки

- [pycozmo](https://github.com/zayodate/pycozmo) - Python библиотека для Cozmo
- [OpenAI Realtime API](https://platform.openai.com/docs/api-reference/realtime)
- [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc)
- [FFmpeg Filters](https://ffmpeg.org/ffmpeg-filters.html)
