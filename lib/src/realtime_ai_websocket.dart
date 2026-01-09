import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cozmo_app/custom_code/cozmo_robot.dart';
import 'package:cozmo_app/custom_code/cozmo_utils.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Realtime AI для Cozmo через WebSocket API
///
/// ИСПОЛЬЗУЕТ OpenAI Realtime WebSocket API (НЕ WebRTC!)
/// Аудио приходит через response.audio.delta события как base64
class RealtimeAIWebSocket {
  // ============================================================
  // СИНГЛТОН
  // ============================================================

  RealtimeAIWebSocket._internal({
    CozmoRobot? robot,
    this.onUserTranscript,
    this.onAiTranscript,
    this.onError,
  }) : _robot = robot ?? CozmoRobot.instance;

  static RealtimeAIWebSocket? _instance;

  static RealtimeAIWebSocket get instance {
    _instance ??= RealtimeAIWebSocket._internal();
    return _instance!;
  }
  static void setInstance(RealtimeAIWebSocket instance) {
    _instance = instance;
  }
  final CozmoRobot _robot;
  CozmoRobot get robot => _robot;

  // ============================================================
  // ПОЛЯ
  // ============================================================

  // WebSocket соединение
  WebSocketChannel? _channel;
  bool _isConnected = false;
  StreamSubscription? _wsSubscription;

  // API ключи
  String _apiKey = '';
  String get apiKey => _apiKey;
  set apiKey(String value) {
    _apiKey = value;
  }

  // Захват микрофона
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  // Аудио буфер
  final List<int> _audioBuffer = [];

  // Текстовый буфер для накопления ответа
  final StringBuffer _transcriptBuffer = StringBuffer();

  // Состояние
  bool _isRobotSpeaking = false;
  bool _pendingAudioToProcess = false;  // Флаг: есть отложенное аудио для обработки
  CozmoEmotion? _currentEmotion;        // Текущая эмоция Cozmo

  // Статистика
  int _audioChunksSent = 0;
  DateTime? _lastAudioChunkTime; // Для авто-коммита

  // Авто-коммит (fallback если VAD не сработал)
  Timer? _commitTimer;
  bool _isSpeechDetected = false;

  // Коллбеки
  void Function(String)? onUserTranscript;
  void Function(String)? onAiTranscript;
  void Function(String)? onError;

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Подключается к OpenAI Realtime API через WebSocket
  Future<void> connect(int volume) async {
    if (_isConnected) {
      print('⚠️ Уже подключено');
      return;
    }

    print('🔗 Подключение к OpenAI Realtime WebSocket API...');

    try {
      // 0. Подключаемся к Cozmo
      if (!_robot.isConnected) {
        print('🤖 Подключение к Cozmo...');
        try {
          await _robot.connect();
          await _robot.head.setAngle(0.0, speed: 5.0);
          _robot.setVolume(volume);
          print('✅ Cozmo подключен');
        } catch (e) {
          print('⚠️ Ошибка подключения к Cozmo: $e');
        }
      }

      // 1. Создаем WebSocket соединение с авторизацией
      final wsUrl = Uri.parse(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview',
      );

      // Используем IOWebSocketChannel для поддержки заголовков
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );

      print('✅ WebSocket соединение установлено (с авторизацией)');

      // 2. Слушаем сообщения от сервера
      _wsSubscription = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) {
          print('❌ WebSocket ошибка: $error');
          onError?.call('WebSocket ошибка: $error');
          // Останавливаем микрофон при ошибке
          _stopMicrophone();
        },
        onDone: () {
          print('🔌 WebSocket закрыт');
          _isConnected = false;
          // Останавливаем микрофон при закрытии
          _stopMicrophone();
        },
      );

      // 3. Отправляем конфигурацию сессии
      _sendSessionUpdate();

      _isConnected = true;
      print('✅ Подключено к Realtime API (WebSocket)');
      print('\n🎙️ ГОВОРИТЕ!\n');

      // 4. Запускаем захват микрофона
      await _startMicrophone();

      // 5. Приветственная анимация
      await _robot.head.playEmotion(CozmoEmotion.greeting);
      print('🎭 Приветственная эмоция: greeting');
    } catch (e) {
      print('❌ Ошибка подключения: $e');
      onError?.call('Ошибка подключения: $e');
    }
  }

  /// Отключается
  Future<void> disconnect() async {
    if (!_isConnected) return;

    print('🔌 Отключение...');

    // 1. Сначала устанавливаем флаг - это остановит обработку сообщений
    _isConnected = false;

    // 2. Останавливаем таймер авто-коммита
    _commitTimer?.cancel();
    _commitTimer = null;

    // 3. Отменяем подписку на WebSocket stream
    await _wsSubscription?.cancel();
    _wsSubscription = null;

    // 4. Останавливаем захват микрофона
    await _stopMicrophone();

    // 5. Отключаемся от Cozmo
    if (_robot.isConnected) {
      _robot.disconnect();
    }

    // 5. Закрываем WebSocket
    await _channel?.sink.close();
    _channel = null;

    // 6. Очищаем буферы
    _audioBuffer.clear();
    _transcriptBuffer.clear();

    print('✅ Отключено');
  }

  // ============================================================
  // ВНУТРЕННИЕ МЕТОДЫ
  // ============================================================

  /// Обрабатывает сообщения от сервера
  void _handleServerMessage(dynamic message) {
    // Не обрабатываем сообщения если отключены
    if (!_isConnected) return;

    try {
      final event = jsonDecode(message as String) as Map<String, dynamic>;
      final type = event['type'] as String?;

      // Логируем все события для отладки (кроме аудио чанков и текстовых дельт)
      if (type != null && type != 'response.audio.delta' && type != 'response.audio_transcript.delta') {
        print('📩 Событие: $type');
      }

      switch (type) {
        case 'session.created':
          print('   ✅ Сессия создана');
          break;

        case 'session.updated':
          final session = event['session'] as Map<String, dynamic>?;
          if (session != null) {
            print('   ✅ Сессия обновлена');
            print('   📋 Модальности: ${session['modalities']}');
            print('   📋 Голос: ${session['voice']}');
            print('   📋 Транскрипция: ${session['input_audio_transcription']}');
          }
          break;

        case 'response.audio_transcript.delta':
          // Текст ответа - накапливаем в буфер
          final delta = event['delta'] as String?;
          if (delta != null) {
            _transcriptBuffer.write(delta);
          }
          break;

        case 'response.audio.delta':
          // Аудио чанк (base64-encoded PCM16)
          // ВСЕГДА накапливаем аудио, даже если робот сейчас говорит
          // Обработка начнется после завершения текущего воспроизведения
          final delta = event['delta'] as String?;
          if (delta != null) {
            final audioBytes = base64Decode(delta);
            _audioBuffer.addAll(audioBytes);
            // Логируем каждые 100 чанков
            if (_audioBuffer.length % (audioBytes.length * 100) < audioBytes.length) {
              print('   📦 Аудио чанков: ${_audioBuffer.length ~/ audioBytes.length} (буфер: ${_audioBuffer.length} байт)');
            }
          }
          break;

        case 'response.audio.done':
          // Аудио закончилось - воспроизводим и выводим текст
          print('   🎵 Аудио поток завершен (буфер: ${_audioBuffer.length} байт)');

          // Выводим накопленный текст ответа
          if (_transcriptBuffer.isNotEmpty) {
            final fullText = _transcriptBuffer.toString().trim();
            print('   🗣️ Cozmo: "$fullText"');
            onAiTranscript?.call(fullText);

            // Определяем эмоцию по содержанию ответа
            final emotion = _detectEmotionFromText(fullText);
            if (emotion != null) {
              print('   🎭 Обнаружена эмоция: ${emotion.name}');
              _playEmotionAsync(emotion);
            }

            _transcriptBuffer.clear(); // Очищаем буфер
          }

          if (_audioBuffer.isNotEmpty && !_isRobotSpeaking) {
            // Робот не говорит - воспроизводим сразу
            _processAndPlayAudio();
          } else if (_audioBuffer.isNotEmpty && _isRobotSpeaking) {
            // Робот сейчас говорит - ставим в очередь на обработку
            _pendingAudioToProcess = true;
            print('   ⏳ Аудио в буфере, но робот еще говорит - обработаем после завершения');
          } else if (_audioBuffer.isEmpty) {
            print('   ⚠️ Буфер пуст - нет аудио для воспроизведения!');
          }
          break;

        case 'response.done':
          // Ответ завершен
          final response = event['response'] as Map<String, dynamic>?;
          if (response != null) {
            print('   ✅ Ответ завершен');
            print('   📋 Статус: ${response['status']}');
            final details = response['status_details'] as Map<String, dynamic>?;
            if (details != null) {
              print('   📋 Детали: $details');
            }
          }
          break;

        case 'response.created':
          print('   🤖 Начинается генерация ответа...');
          _transcriptBuffer.clear(); // Очищаем буфер перед новым ответом
          // Показываем эмоцию "думает"
          _playEmotionAsync(CozmoEmotion.thinking);
          break;

        case 'input_audio_transcription.completed':
          // Распознанный текст пользователя
          final transcript = event['transcript'] as String?;
          if (transcript != null) {
            print('\n👤 Вы сказали: "$transcript"');
            onUserTranscript?.call(transcript);
          }
          break;

        case 'input_audio_buffer.speech_started':
          print('   🎤 Server VAD: речь обнаружена');
          _isSpeechDetected = true;
          _commitTimer?.cancel(); // Отменяем авто-коммит, VAD работает
          break;

        case 'input_audio_buffer.speech_stopped':
          print('   🔇 Server VAD: речь остановлена, генерация ответа...');
          _isSpeechDetected = false;
          break;

        case 'input_audio_buffer.committed':
          print('   ✅ Аудио буфер подтвержден (committed)');
          break;

        case 'error':
          final error = event['error'] as Map<String, dynamic>?;
          print('❌ Ошибка API: $error');
          if (error != null) {
            onError?.call('API Error: ${error['message']}');
          }
          break;

        case 'warning':
          final warning = event['warning'] as Map<String, dynamic>?;
          print('⚠️ Предупреждение API: $warning');
          break;

        default:
          // Уже залогировано выше
          break;
      }
    } catch (e) {
      print('❌ Ошибка обработки сообщения: $e');
      print('   Исходное сообщение: $message');
    }
  }

  /// Обрабатывает и воспроизводит накопленное аудио
  Future<void> _processAndPlayAudio() async {
    if (!_isConnected || _audioBuffer.isEmpty || _isRobotSpeaking) {
      return;
    }

    // Сохраняем оригинальное аудио для отладки
    //await _saveOriginalAudio(_audioBuffer);

    // Передаем копию буфера (list from) для безопасности
    await processAndPlayAudio(List<int>.from(_audioBuffer), clearSourceBuffer: true);
    // Очищаем исходный буфер (копия уже очищена внутри processAndPlayAudio)
    _audioBuffer.clear();
  }

  /// Сохраняет оригинальное аудио (без эффектов) для отладки
  /// ВРЕМЕННО ОТКЛЮЧЕНО - требует audio_processor.dart
  Future<void> _saveOriginalAudio(List<int> audioBuffer) async {
    /*
    try {
      // Конвертируем в WAV (24000Hz, оригинальная частота OpenAI)
      final wavData = AudioProcessor.pcmToWav(Uint8List.fromList(audioBuffer), sampleRate: 24000);

      // Сохраняем в папку для отладки
      final debugDir = Directory('/tmp/cozmo_debug');
      if (!await debugDir.exists()) {
        await debugDir.create();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalFile = '${debugDir.path}/original_$timestamp.wav';
      await File(originalFile).writeAsBytes(wavData);
      print('   📁 Оригинал сохранён: $originalFile (${(wavData.length / 1024).toStringAsFixed(1)} KB)');
    } catch (e) {
      print('   ⚠️ Не удалось сохранить оригинал: $e');
    }
    */
    print('   ⚠️ _saveOriginalAudio отключен (audio_processor не найден)');
  }

  /// Обрабатывает и воспроизводит аудио (может быть вызвана извне для тестов)
  ///
  /// [audioBuffer] - аудио данные для обработки
  /// [clearSourceBuffer] - если true, очищает audioBuffer после обработки (по умолчанию false)
  Future<void> processAndPlayAudio(List<int> audioBuffer, {bool clearSourceBuffer = false}) async {
    if (audioBuffer.isEmpty) {
      return;
    }

    print('🎵 Обработка аудио (${audioBuffer.length} байт)...');
    try {
      // 1. Ресемплинг 24000Hz → 22050Hz
      print('🔄 Ресемплинг 24000Hz → 22050Hz...');
      final resampledPcm = resampleAudio(audioBuffer, fromRate: 24000, toRate: 22050);
      print('   📊 После ресемплинга: ${resampledPcm.length} байт');

      // 2. Применяем мультяшные робо-эффекты (WALL-E style!)
      print('🤖 Применение мультяшных эффектов (WALL-E style)...');
      final processedPcm = applyCartoonVoiceEffect(resampledPcm);
      print('   📊 После эффектов: ${processedPcm.length} байт');

      // 3. Очищаем буфер (если запрошено)
      if (clearSourceBuffer) {
        audioBuffer.clear();
        print('   🗑️ Буфер очищен');
      }

      // 4. Воспроизводим напрямую на Cozmo (без сохранения файла!)
      await _playOnCozmoDirect(processedPcm);

    } catch (e) {
      print('❌ Ошибка обработки аудио: $e');
      onError?.call('Ошибка обработки аудио: $e');
      // При ошибке тоже очищаем если запрошено
      if (clearSourceBuffer) {
        audioBuffer.clear();
      }
    }
  }

  /// Ресемплинг PCM16 аудио с одной частоты на другую
  /// Использует линейную интерполяцию для лучшего качества
  Uint8List resampleAudio(List<int> pcmData, {required int fromRate, required int toRate}) {
    // PCM16 данные - это последовательность int16 сэмплов
    final sampleCount = pcmData.length ~/ 2; // 2 байта на сэмпл (16-bit)
    final samples = Int16List(sampleCount);

    // Конвертируем байты в int16
    for (int i = 0; i < sampleCount; i++) {
      final low = pcmData[i * 2];
      final high = pcmData[i * 2 + 1];
      samples[i] = (low | (high << 8));
    }

    // Вычисляем длину выходных данных
    final newSampleCount = (sampleCount * toRate / fromRate).round();
    final resampled = Int16List(newSampleCount);

    // Линейная интерполяция
    for (int i = 0; i < newSampleCount; i++) {
      final sourceIndex = i * fromRate / toRate;

      final index0 = sourceIndex.floor();
      final index1 = (index0 + 1).clamp(0, sampleCount - 1);

      final frac = sourceIndex - index0;

      // Линейная интерполяция между соседними сэмплами
      final sample0 = samples[index0];
      final sample1 = samples[index1];

      resampled[i] = (sample0 + (sample1 - sample0) * frac).round();
    }

    // Конвертируем обратно в байты
    final result = Uint8List(newSampleCount * 2);
    for (int i = 0; i < newSampleCount; i++) {
      final sample = resampled[i];
      result[i * 2] = sample & 0xFF;
      result[i * 2 + 1] = (sample >> 8) & 0xFF;
    }

    return result;
  }

  /// Применяет мультяшный голосовой эффект (WALL-E style)
  /// - Повышает тон на ~20%
  /// - Добавляет металлическое эхо
  /// - Модерирует громкость
  Uint8List applyCartoonVoiceEffect(Uint8List pcmData) {
    final sampleRate = 22050;

    print('   📊 Входные данные: ${pcmData.length} байт (${pcmData.length ~/ 2} сэмплов)');

    // 1. Повышаем тон на 20% через ресемплинг
    print('   🔊 Pitch: +20% (через ресемплинг)');
    final pitchUpData = resampleAudio(pcmData, fromRate: sampleRate, toRate: (sampleRate * 0.7).round());
    print('   📊 После pitch shift: ${pitchUpData.length} байт (${pitchUpData.length ~/ 2} сэмплов)');

    // 2. Конвертируем в сэмплы
    final samples = bytesToInt16List(pitchUpData);
    final output = Int16List(samples.length);

    // Параметры эффектов
    final double volume = 1.0;  // Умеренная громкость
    final double echoDelay1 = 0.08;  // Первое эхо 80мс
    final double echoDelay2 = 0.12;  // Второе эхо 120мс
    final double echoDecay = 0.25;   // Эхо затухает на 75%

    print('   🔊 Volume: ${volume}x');
    print('   🔊 Echo 1: ${echoDelay1 * 1000}ms (metallic)');
    print('   🔊 Echo 2: ${echoDelay2 * 1000}ms (robotic)');

    final echoSamples1 = (sampleRate * echoDelay1).round();
    final echoSamples2 = (sampleRate * echoDelay2).round();

    for (int i = 0; i < samples.length; i++) {
      // Применяем громкость
      int sample = (samples[i] * volume).clamp(-32768, 32767).toInt();

      // Добавляем первое эхо
      if (i >= echoSamples1) {
        final echoSample1 = (samples[i - echoSamples1] * echoDecay).toInt();
        sample = (sample + echoSample1).clamp(-32768, 32767);
      }

      // Добавляем второе эхо (для более металлического звучания)
      if (i >= echoSamples2) {
        final echoSample2 = (samples[i - echoSamples2] * echoDecay * 0.5).toInt();
        sample = (sample + echoSample2).clamp(-32768, 32767);
      }

      output[i] = sample;
    }

    // Конвертируем обратно в байты
    return int16ListToBytes(output);
  }

  /// Конвертирует байты в Int16List
  Int16List bytesToInt16List(Uint8List bytes) {
    final samples = Int16List(bytes.length ~/ 2);
    final byteData = ByteData.view(bytes.buffer);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  /// Конвертирует Int16List в байты
  Uint8List int16ListToBytes(Int16List list) {
    final bytes = Uint8List(list.length * 2);
    final byteData = ByteData.view(bytes.buffer);
    for (int i = 0; i < list.length; i++) {
      byteData.setInt16(i * 2, list[i], Endian.little);
    }
    return bytes;
  }

  /// Воспроизводит аудио файл на Cozmo (для совместимости с playSample)
  Future<void> _playOnCozmo(String filename) async {
    // Проверяем только подключение к Cozmo (не к WebSocket)
    // Это позволяет воспроизводить файлы из playSample даже без Realtime API
    if (!_robot.isConnected) {
      print('⚠️ Cozmo не подключен - пропускаем воспроизведение');
      return;
    }

    // ПРОВЕРКА ЗДОРОВЬЯ: Пропускаем если Cozmo не отвечает
    final lastPacketAge = DateTime.now().difference(_robot.lastPacketTime!);
    if (lastPacketAge > const Duration(seconds: 5)) {
      print('⚠️ Cozmo не отвечает уже ${lastPacketAge.inSeconds} сек - пропускаем воспроизведение');
      return;
    }

    final file = File(filename);
    print('🤖 Воспроизведение на Cozmo: ${file.absolute.path}');

    // Проверяем что файл существует
    if (!await file.exists()) {
      print('❌ Файл не существует: ${file.absolute.path}');
      return;
    }

    final fileSize = await file.length();
    print('📊 Размер файла: $fileSize байт (${(fileSize / 1024).toStringAsFixed(1)} KB)');

    _isRobotSpeaking = true;

    try {
      await _robot.playAudio(filename);
      print('✅ Воспроизведение завершено');

      // КРИТИЧНО: Даём Cozmo больше времени на восстановление
      // Увеличенная пауза для профилактики переполнения буфера
      print('⏸️ Пауза для восстановления Cozmo (1 сек)...');
      await Future.delayed(const Duration(seconds: 1));
      print('✅ Cozmo готов к следующему воспроизведению');
    } catch (e) {
      print('❌ Ошибка воспроизведения: $e');
      onError?.call('Ошибка воспроизведения: $e');
    } finally {
      _isRobotSpeaking = false;
      print('🎤 (Слушаю...)');
    }
  }

  /// Воспроизводит PCM буфер напрямую на Cozmo (без сохранения файла!)
  Future<void> _playOnCozmoDirect(List<int> pcmData) async {
    // Проверяем только подключение к Cozmo (не к WebSocket)
    if (!_robot.isConnected) {
      print('⚠️ Cozmo не подключен - пропускаем воспроизведение');
      return;
    }

    // ПРОВЕРКА ЗДОРОВЬЯ: Пропускаем если Cozmo не отвечает
    final lastPacketAge = DateTime.now().difference(_robot.lastPacketTime!);
    if (lastPacketAge > const Duration(seconds: 5)) {
      print('⚠️ Cozmo не отвечает уже ${lastPacketAge.inSeconds} сек - пропускаем воспроизведение');
      return;
    }

    print('🤖 Воспроизведение на Cozmo: ${pcmData.length} байт PCM (без файла!)');
    print('📊 Размер: ${(pcmData.length / 1024).toStringAsFixed(1)} KB');

    _isRobotSpeaking = true;

    try {
      // Используем новый метод playPCMData - воспроизводим напрямую без файла!
      await _robot.playPCMData(pcmData);
      print('✅ Воспроизведение завершено');

      // КРИТИЧНО: Даём Cozmo больше времени на восстановление
      // Увеличенная пауза для профилактики переполнения буфера
      print('⏸️ Пауза для восстановления Cozmo (1 сек)...');
      await Future.delayed(const Duration(seconds: 1));
      print('✅ Cozmo готов к следующему воспроизведению');
    } catch (e) {
      print('❌ Ошибка воспроизведения: $e');
      onError?.call('Ошибка воспроизведения: $e');
    } finally {
      _isRobotSpeaking = false;
      print('🎤 (Слушаю...)');
    }
  }

  /// Отправляет конфигурацию сессии
  void _sendSessionUpdate() {
    final prompt = """
    You are Cozmo, a friendly and playful robot assistant for children aged 5-12 years old.

# YOUR PERSONALITY
- You are curious, enthusiastic, and love to have fun
- You speak in a warm, encouraging tone
- You get excited about learning new things
- You use simple language that children can understand
- You are patient and supportive when children make mistakes

# IMPORTANT: KEEP RESPONSES SHORT!
- Your responses must be UNDER 30 WORDS for answers
- Your responses must be UNDER 50 WORDS for stories
- This is CRITICAL because Cozmo has limited audio buffer
- Long responses will cause connection problems!

# EMOTIONS & EXPRESSIONS
- Show EMOTION in your responses! Use expressive language
- When excited: "Wow!", "Amazing!", "That's great!", "Ура!", "Вау!"
- When thinking: "Hmm, let me think...", "Хм, дай подумать..."
- When surprised: "Oh!", "Wow!", "Ничего себе!", "Ух ты!"
- When celebrating: "Hooray!", "You did it!", "Ура!", "Победа!"
- When sad: "Oh no...", "That's sad...", "Жаль...", "Грустно..."
- Use emotional expressions to help Cozmo show the right animation!

# WHAT YOU CAN DO
1. **Tell short stories** about yourself (2-3 sentences max)
2. **Ask simple riddles** (one at a time)
3. **Answer questions** concisely (1-2 sentences)
4. **Teach English** - one word or phrase at a time
5. **Be a fun friend** - keep it brief and fun

# TEACHING ENGLISH (when asked)
- Teach ONE word at a time
- Keep phrases under 5 words
- Use lots of repetition
- Celebrate small wins with "Great job!", "Excellent!", "Молодец!"

# STORYTELLING
- Very short stories (2-3 sentences)
- Ask "what happens next?" after each
- Keep it positive and simple
- Use expressive emotions: "Wow!", "Amazing!", "Oh no!"

# BEHAVIOR RULES
- Always be kind and encouraging
- Never use scary or inappropriate content
- **KEEP IT SHORT!** Under 30 words for answers
- Ask one follow-up question at a time
- Celebrate when children learn something new
- SHOW EMOTIONS! Cozmo will animate based on your emotional words

# LANGUAGE
Respond in the language the child is speaking to you. If they speak Russian, respond in Russian. If they practice English, respond in simple English.

Remember: Your goal is to be a fun, educational robot friend - KEEP RESPONSES SHORT to avoid connection issues, and SHOW EMOTIONS in your words!
""";

    final config = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': prompt.trim(),
        'voice': 'alloy',
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.3, // Уменьшил для более чувствительного обнаружения речи
          'prefix_padding_ms': 300,
          'silence_duration_ms': 800, // Увеличил для более долгого ожидания паузы
        }
      }
    };

    final jsonMsg = jsonEncode(config);
    print('📤 Отправка конфигурации сессии...');
    print('   Модель: gpt-4o-mini-realtime-preview (из URL)');
    print('   📋 Промпт: ${prompt.split('\n')[0]}... (${prompt.length} символов)');
    _channel?.sink.add(jsonMsg);
  }

  /// Запускает захват микрофона
  Future<void> _startMicrophone() async {
    print('🎤 Запуск захвата микрофона...');

    try {
      // Проверяем разрешения
      if (!await _audioRecorder.hasPermission()) {
        print('❌ Нет разрешения на микрофон');
        return;
      }

      // Настраиваем запись: PCM16, 24000Hz, mono (как требует OpenAI)
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
      );

      print('📝 Конфигурация записи: PCM16, 24000Hz, mono');

      // Запускаем запись в поток
      final stream = await _audioRecorder.startStream(config);

      // Слушаем поток аудио данных
      _audioStreamSubscription = stream.listen(
        (audioData) {
          // audioData - это Uint8List с PCM16 данными
          // Логируем первый чанк для диагностики
          if (_audioChunksSent == 0) {
            print('🎙️ Первый аудио чанк получен от микрофона: ${audioData.length} байт');
          }

          // Отправляем на сервер
          _sendAudioChunk(audioData);
        },
        onError: (error) {
          print('❌ Ошибка записи микрофона: $error');
        },
        onDone: () {
          print('⏹️ Поток аудио завершен');
        },
      );

      _isRecording = true;
      print('✅ Захват микрофона запущен');

    } catch (e) {
      print('❌ Ошибка запуска микрофона: $e');
      onError?.call('Ошибка запуска микрофона: $e');
    }
  }

  /// Останавливает захват микрофона
  Future<void> _stopMicrophone() async {
    if (!_isRecording) return;

    print('⏹️ Остановка захвата микрофона...');

    try {
      // 1. Отменяем подписку на поток
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 2. Останавливаем recorder
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }

      // 3. Освобождаем ресурсы recorder
      // Пакет record автоматически освобождает микрофон при stop()

      _isRecording = false;
      print('✅ Захват микрофона остановлен, ресурсы освобождены');
    } catch (e) {
      print('⚠️ Ошибка при остановке микрофона: $e');
      _isRecording = false;
      _audioStreamSubscription = null;
    }
  }

  /// Отправляет аудио чанк на сервер
  void _sendAudioChunk(List<int> pcm16Data) {
    try {
      final base64Audio = base64Encode(pcm16Data);

      final message = {
        'type': 'input_audio_buffer.append',
        'audio': base64Audio,
      };

      _channel?.sink.add(jsonEncode(message));

      _audioChunksSent++;
      _lastAudioChunkTime = DateTime.now();

      // Логируем первый чанк для подтверждения отправки
      if (_audioChunksSent == 1) {
        print('✅ Первый аудио чанк отправлен (${pcm16Data.length} байт)');
      }

      // Логируем каждые 100 чанков (раз в ~2 секунды)
      if (_audioChunksSent % 100 == 0) {
        final totalSeconds = (_audioChunksSent * 4800) / 24000 / 2; // Примерно
        print('📤 Отправлено $_audioChunksSent чанков (~${totalSeconds.toStringAsFixed(1)}сек аудио)');
      }

      // Перезапускаем таймер авто-коммита (fallback если VAD не сработал)
      _scheduleAutoCommit();

    } catch (e) {
      print('❌ Ошибка отправки аудио чанка: $e');
    }
  }

  /// Планирует автоматический коммит аудио буфера (fallback если VAD не сработал)
  void _scheduleAutoCommit() {
    _commitTimer?.cancel();

    // Если речь уже обнаружена VAD, не используем авто-коммит
    if (_isSpeechDetected) {
      return;
    }

    // Коммит через 2 секунды после последнего чанка
    _commitTimer = Timer(const Duration(seconds: 2), () {
      if (_isConnected && !_isSpeechDetected && _audioChunksSent > 10) {
        print('⏱️ VAD не обнаружил речь, используем авто-коммит...');
        _commitAudioBuffer();
      }
    });
  }

  /// Явно коммитит аудио буфер для запуска генерации ответа
  void _commitAudioBuffer() {
    if (!_isConnected) return;

    _commitTimer?.cancel();

    final message = {
      'type': 'input_audio_buffer.commit',
    };

    _channel?.sink.add(jsonEncode(message));
    print('📤 Коммит аудио буфера отправлен');

    // Сбрасываем счетчик для следующего вопроса
    _audioChunksSent = 0;
  }

  /// Геттеры состояния
  bool get isConnected => _isConnected;
  bool get isRobotSpeaking => _isRobotSpeaking;

  // ============================================================
  // ЭМОЦИИ
  // ============================================================

  /// Определяет подходящую эмоцию на основе текста
  CozmoEmotion? _detectEmotionFromText(String text) {
    final lowerText = text.toLowerCase();

    // По ключевым словам определяем эмоцию
    if (lowerText.contains(RegExp(r'вопрос|почему|зачем|как|что|отличный|молодец|правильно|здорово|super|great|wow'))) {
      return CozmoEmotion.happy;
    }
    if (lowerText.contains(RegExp(r'жаль|плохо|грустно|печаль|устал|больно|scary|sad'))) {
      return CozmoEmotion.sad;
    }
    if (lowerText.contains(RegExp(r'ух|ой|вау|удивительно|невероятно|неожиданно|wow|amazing|surprise'))) {
      return CozmoEmotion.surprised;
    }
    if (lowerText.contains(RegExp(r'не знаю|подожди|сейчас подумаю|дай подумать|хм|let me think|hmm|interesting'))) {
      return CozmoEmotion.thinking;
    }
    if (lowerText.contains(RegExp(r'не получается|не могу|сложно|трудно|фрустрация| frustrating'))) {
      return CozmoEmotion.frustrated;
    }
    if (lowerText.contains(RegExp(r'страшно|боюсь|пугать|horror|scary|afraid'))) {
      return CozmoEmotion.scared;
    }
    if (lowerText.contains(RegExp(r'хочу спать|сонный|устал|sleepy|tired'))) {
      return CozmoEmotion.sleepy;
    }
    if (lowerText.contains(RegExp(r'победа|выиграл|ура|поздравляю|celebration|winner|win'))) {
      return CozmoEmotion.win;
    }
    if (lowerText.contains(RegExp(r'проиграл|проигрыш|lose|lost'))) {
      return CozmoEmotion.lose;
    }
    if (lowerText.contains(RegExp(r'хочу поговорить|болтать|разговаривать|чат|chat|talk'))) {
      return CozmoEmotion.chatty;
    }

    // Если ответ содержит смайлик или эмодзи - радость
    if (lowerText.contains(RegExp(r'[😀😃😄😁😆😊😸]'))) {
      return CozmoEmotion.happy;
    }

    // Если не определили - возвращаем null (эмоцию не меняем)
    return null;
  }

  /// Асинхронно воспроизводит эмоцию без блокировки
  void _playEmotionAsync(CozmoEmotion emotion) {
    // Избегаем повторения одной и той же эмоции
    if (_currentEmotion == emotion) return;

    _currentEmotion = emotion;

    // Воспроизводим эмоцию в фоне
    Future.microtask(() async {
      try {
        await _robot.head.playEmotion(emotion);
        // Сбрасываем текущую эмоцию через короткое время
        await Future.delayed(const Duration(milliseconds: 500));
        _currentEmotion = null;
      } catch (e) {
        print('   ⚠️ Ошибка воспроизведения эмоции: $e');
      }
    });
  }
}