# OpenAI Realtime API - WebSocket Реализация

## ✅ Готово!

Реализована WebSocket версия OpenAI Realtime API для Cozmo. Аудио теперь приходит через `response.audio.delta` события как base64-encoded PCM16 данные!

## Что изменилось

### Проблема с WebRTC подходом
- ❌ WebRTC API отправляет аудио через audio track (raw PCM)
- ❌ flutter_webrtc НЕ предоставляет API для захвата raw PCM из remote audio track
- ❌ MediaRecorder предназначен только для локального микрофона/камеры

### Решение через WebSocket API
- ✅ OpenAI Realtime WebSocket API отправляет аудио через `response.audio.delta` события
- ✅ Аудио приходит как base64-encoded PCM16 данные
- ✅ Прямая работа с аудио буфером - никакого "черного ящика"
- ✅ Работает без нативного кода

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter App                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  WebSocket соединение                                   │  │
│  │    wss://api.openai.com/v1/realtime                     │  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Обработка событий                                      │  │
│  │    • session.created                                    │  │
│  │    • response.audio_transcript.delta (текст ответа)    │  │
│  │    • response.audio.delta (base64 аудио) ✅            │  │
│  │    • response.audio.done                                │  │
│  │    • input_audio_transcription.completed (текст юзера) │  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Аудио обработка                                        │  │
│  │    1. Декодируем base64 → PCM16                         │  │
│  │    2. Накапливаем в буфер                               │  │
│  │    3. response.audio.done → конвертируем в WAV          │  │
│  │    4. Воспроизводим на Cozmo                            │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Захват микрофона (record пакет)                        │  │
│  │    1. PCM16, 24000Hz, mono                              │  │
│  │    2. Кодируем в base64                                 │  │
│  │    3. Отправляем input_audio_buffer.append              │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Файлы

### Основная реализация
- **[realtime_ai_websocket.dart](lib/custom_code/realtime_ai_websocket.dart)** - WebSocket версия Realtime AI
  - `RealtimeAIWebSocket` класс
  - WebSocket соединение с OpenAI
  - Обработка `response.audio.delta` событий
  - Захват микрофона через `record` пакет
  - Воспроизведение на Cozmo

### Тестовый файл
- **[realtime_ai_websocket_test.dart](lib/custom_code/realtime_ai_websocket_test.dart)** - Тест для проверки

### Старые файлы (для справки)
- **[realtime_ai.dart](lib/custom_code/realtime_ai.dart)** - WebRTC версия (не работает для аудио)
- **[realtime_ai_mediacorder.dart](lib/custom_code/realtime_ai_mediacorder.dart)** - MediaRecorder попытка (не работает)
- **[realtime_ai_native.dart](lib/custom_code/realtime_ai_native.dart)** - Нативный placeholder

## Использование

### 1. Установка зависимостей

```bash
flutter pub get
```

Установленные пакеты:
- `web_socket_channel: ^2.4.0` - WebSocket клиент
- `record: ^5.1.0` - Захват микрофона
- `audio_wave: ^0.1.0` - Конвертация аудио (опционально)

### 2. Настройка API ключа

Откройте [realtime_ai_websocket.dart:47](lib/custom_code/realtime_ai_websocket.dart#L47) и замените API ключ:

```dart
final String _apiKey = 'ВАШ_OPENAI_API_KEY';
```

**Важно:** Используйте настоящий OpenAI API key (начинается с `sk-`), не Supabase token!

### 3. Запуск теста

```bash
flutter run -d macos lib/custom_code/realtime_ai_websocket_test.dart
```

Или используйте в коде:

```dart
import 'package:cozmo_app/custom_code/realtime_ai_websocket.dart';

// Подключение
await RealtimeAIWebSocket.instance.connect();

// Отключение
await RealtimeAIWebSocket.instance.disconnect();

// Коллбеки
RealtimeAIWebSocket.instance.onUserTranscript = (text) {
  print('Пользователь: $text');
};

RealtimeAIWebSocket.instance.onAiTranscript = (text) {
  print('AI: $text');
};

RealtimeAIWebSocket.instance.onError = (error) {
  print('Ошибка: $error');
};
```

## Как это работает

### Подключение к OpenAI

```dart
// 1. WebSocket соединение с авторизацией
final wsUrl = Uri.parse(
  'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01',
);

_channel = IOWebSocketChannel.connect(
  wsUrl,
  headers: {
    'Authorization': 'Bearer $_apiKey',
    'OpenAI-Beta': 'realtime=v1',  // Обязательно для Realtime API
  },
);

// 2. Отправляем конфигурацию сессии
_sendSessionUpdate();
```

### Прием аудио от OpenAI

```dart
case 'response.audio.delta':
  // Аудио чанк (base64-encoded PCM16)
  final delta = event['delta'] as String?;
  if (delta != null) {
    final audioBytes = base64Decode(delta);
    _audioBuffer.addAll(audioBytes);  // Накапливаем
  }
  break;

case 'response.audio.done':
  // Аудио закончилось - воспроизводим
  if (_audioBuffer.isNotEmpty) {
    _processAndPlayAudio();
  }
  break;
```

### Захват микрофона

```dart
// 1. Настраиваем запись: PCM16, 24000Hz, mono
final config = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 24000,
  numChannels: 1,
);

// 2. Запускаем запись в поток
final stream = await _audioRecorder.startStream(config);

// 3. Слушаем поток аудио данных
_audioStreamSubscription = stream.listen((audioData) {
  // audioData - это Uint8List с PCM16 данными
  _sendAudioChunk(audioData);
});
```

### Отправка аудио в OpenAI

```dart
void _sendAudioChunk(List<int> pcm16Data) {
  final base64Audio = base64Encode(pcm16Data);

  final message = {
    'type': 'input_audio_buffer.append',
    'audio': base64Audio,
  };

  _channel?.sink.add(jsonEncode(message));
}
```

### Воспроизведение на Cozmo

```dart
// 1. Конвертируем PCM16 в WAV
final pcmData = Uint8List.fromList(_audioBuffer);
final wavData = AudioProcessor.pcmToWav(pcmData);

// 2. Сохраняем во временный файл
final wavFile = '/tmp/cozmo_response_$timestamp.wav';
await file.writeAsBytes(wavData);

// 3. Воспроизводим на Cozmo
await cozmo.playAudio(wavFile);
```

## События OpenAI Realtime API

### События от сервера

| Событие | Описание |
|---------|----------|
| `session.created` | Сессия создана |
| `response.audio_transcript.delta` | Текст ответа (потоковый) |
| `response.audio.delta` | Аудио чанк (base64 PCM16) ✅ |
| `response.audio.done` | Аудио завершено |
| `response.done` | Ответ завершен |
| `input_audio_transcription.completed` | Распознанный текст пользователя |
| `error` | Ошибка API |

### События от клиента

| Событие | Описание |
|---------|----------|
| `session.update` | Обновление конфигурации сессии |
| `input_audio_buffer.append` | Аудио чанк от микрофона (base64 PCM16) |
| `input_audio_buffer.commit` | Завершить ввод и начать генерацию ответа |

## Сравнение WebRTC vs WebSocket

| Характеристика | WebRTC API | WebSocket API |
|----------------|------------|---------------|
| **Транспорт** | WebRTC (PeerConnection) | WebSocket |
| **Аудио от OpenAI** | Audio track (raw PCM) | `response.audio.delta` (base64) |
| **Захват аудио** | ❌ Нужен нативный код | ✅ Стандартный WebSocket |
| **Аудио микрофона** | MediaStream | base64 через WebSocket |
| **Сложность** | ❌ Высокая | ✅ Низкая |
| **Работает в Flutter** | ❌ Ограниченно | ✅ Полностью |
| **Задержка** | ✅ Минимальная | ⚠️ Немного выше |
| **NAT traversal** | ✅ Встроен | ❌ Не нужен |

## Troubleshooting

### Ошибка: Нет разрешения на микрофон

**macOS:**
- В `macos/Runner/Info.plist` добавьте:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Нужно для голосового ассистента</string>
```

- В `macos/Runner/DebugProfile.entitlements` и `Release.entitlements`:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Ошибка: WebSocket не подключается

1. **Проверьте API ключ:**
   - Должен начинаться с `sk-`
   - Должен быть активен
   - Должен иметь доступ к Realtime API

2. **Проверьте интернет соединение:**
   ```bash
   curl -I https://api.openai.com
   ```

3. **Проверьте заголовки:**
   - `Authorization: Bearer $API_KEY`
   - `OpenAI-Beta: realtime=v1`

### Аудио не воспроизводится на Cozmo

1. **Проверьте подключение Cozmo:**
   ```dart
   if (!cozmo.isConnected) {
     print('Cozmo не подключен!');
   }
   ```

2. **Проверьте формат аудио:**
   - Должен быть WAV
   - 22050Hz (или 24000Hz с ресемплингом)
   - Mono, PCM16

3. **Проверьте файл:**
   ```bash
   file /tmp/cozmo_response_*.wav
   # Ожидается: RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 24000 Hz
   ```

### Аудио приходит, но не воспроизводится

Возможно проблема с ресемплингом. OpenAI использует 24000Hz, а Cozmo - 22050Hz.

**Решение:**
- Используйте `AudioProcessor.applyRobotEffect()` для конвертации
- Или настройте OpenAI на 22050Hz (если возможно)

## Ссылки

- [OpenAI Realtime API Docs](https://platform.openai.com/docs/guides/realtime-conversations)
- [OpenAI Server Events Reference](https://platform.openai.com/docs/api-reference/realtime-server-events)
- [Flutter record package](https://pub.dev/packages/record)
- [WebSocket channel package](https://pub.dev/packages/web_socket_channel)

## Дальнейшие улучшения

1. **Оптимизация задержки:**
   - Сейчас аудио накапливается до `response.audio.done`
   - Можно воспроизводить чанками для уменьшения задержки

2. **Ресемплинг:**
   - Добавить конвертацию 24000Hz → 22050Hz
   - Использовать ffmpeg или native код

3. **VAD (Voice Activity Detection):**
   - Определять когда пользователь закончил говорить
   - Автоматически отправлять `input_audio_buffer.commit`

4. **Эхо-подавление:**
   - OpenAI отправляет эхо собственного голоса
   - Нужно фильтровать `response.audio.delta` когда робот говорит

## Заключение

✅ **WebSocket API - правильный путь!**

Теперь аудио OpenAI работает в Flutter без нативного кода. Проблема решена!

**Sources:**
- [OpenAI Realtime Conversations Guide](https://platform.openai.com/docs/guides/realtime-conversations)
- [OpenAI Server Events Reference](https://platform.openai.com/docs/api-reference/realtime-server-events)
- [record | Flutter package](https://pub.dev/packages/record)
