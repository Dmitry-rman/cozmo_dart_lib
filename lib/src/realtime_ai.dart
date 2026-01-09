import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cozmo_app/custom_code/cosmo_lib/cozmo_robot.dart';
import 'package:cozmo_app/custom_code/cosmo_lib/cozmo_utils.dart';
import 'package:cozmo_app/custom_code/cosmo_lib/modules/audio_processor.dart';
import 'package:cozmo_app/custom_code/ai_config.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Realtime AI для Cozmo с WebRTC и OpenAI API
/// Управляет голосовым взаимодействием через OpenAI Realtime API
class RealtimeAI {
  // ============================================================
  // СИНГЛТОН
  // ============================================================

  RealtimeAI._internal({
    required this.config,
    CozmoRobot? robot,
    this.onUserTranscript,
    this.onAiTranscript,
    this.onError,
  }) : _robot = robot ?? CozmoRobot.instance;

  static RealtimeAI? _instance;

  /// Возвращает единственный экземпляр RealtimeAI
  /// При первом вызове создаёт экземпляр с предустановленным config
  static RealtimeAI get instance {
    _instance ??= RealtimeAI._internal(
      config: _defaultConfig,
    );
    return _instance!;
  }

  /// Конфигурация по умолчанию
  static final AIConfig _defaultConfig = AIConfig(
    sessionUrl:
        'https://ofuwinduxpeleetuscnk.supabase.co/functions/v1/get_robot_session_v1',
    apiToken:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9mdXdpbmR1eHBlbGVldHVzY25rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUzNTQ3MDIsImV4cCI6MjA3MDkzMDcwMn0.u1ptBneez3NU6GI9spQRr-JcCBW7p6vJFCLkJ0bXgKU',
    apiSecret: 'QR@@ibNa6p@GLhX',
    systemInstructions: 'Ты коуч психологического здоровья.',
        //'Ты робот Cozmo. Отвечай коротко, 1-2 предложения. '
        //'Используй простые слова. Ты дружелюбный и любознательный робот.',
    voice: 'alloy',
    language: 'ru',
    voiceCode: 9982,
  );

  /// Конфигурация AI
  final AIConfig config;

  /// Робот
  final CozmoRobot _robot;

  // ============================================================
  // ПОЛЯ
  // ============================================================

  // Состояние соединения
  bool _isConnected = false;
  bool _isRobotSpeaking = false;

  // WebRTC
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;  // 🔥 Для захвата аудио от OpenAI

  // Файловый мониторинг для Python скрипта
  Timer? _fileMonitorTimer;
  String? _lastAudioFile;

  // Аудио буфер для входящих данных от OpenAI
  final List<int> _audioBuffer = [];
  final StreamController<List<int>> _audioController =
      StreamController.broadcast();

  // Счётчики для отладки
  int _audioDeltaCount = 0;
  int _totalAudioBytes = 0;

  // Очередь файлов для воспроизведения
  String? _pendingAudioFile;
  Timer? _playbackTimer;

  // Очередь сообщений для отправки (когда data channel будет готов)
  String? _pendingSessionConfig;

  // HTTP клиент для API запросов
  final HttpClient _httpClient = HttpClient();

  // Коллбеки для событий
  void Function(String)? onUserTranscript;
  void Function(String)? onAiTranscript;
  void Function(String)? onError;

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Подключается к OpenAI Realtime API
  Future<void> connect(int volume) async {
    if (_isConnected) {
      print('⚠️ Уже подключено к Realtime API');
      return;
    }

    print('🔗 Подключение к OpenAI Realtime API...');
    print('   URL: ${config.sessionUrl}');

    try {
      // 0. Подключаемся к Cozmo
      if (!_robot.isConnected) {
        print('🤖 Подключение к Cozmo...');
        try {
          await _robot.connect();
          await _robot.head.setAngle(0.0, speed: 5.0);
          print('✅ Cozmo подключен и готов');
        } catch (e) {
          print('⚠️ Не удалось подключиться к Cozmo: $e');
          print('📍 Продолжаем без Cozmo...');
        }
      }

      _robot.setVolume(volume);

      // 1. Создаем WebRTC peer connection
      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };

      _pc = await createPeerConnection(configuration);

      // 2. Создаем data channel для сообщений
      _dc = await _pc!.createDataChannel(
        'session',
        RTCDataChannelInit(),
      );

      // 3. Добавляем обработчики событий data channel
      _dc?.onDataChannelState = (state) {
        print('📡 Data Channel состояние: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          // Data channel открыт - отправляем отложенную конфигурацию
          if (_pendingSessionConfig != null) {
            print('📤 Отправка отложенной конфигурации...');
            _dc?.send(RTCDataChannelMessage(_pendingSessionConfig!));
            _pendingSessionConfig = null;
          }
        }
      };

      _dc?.onMessage = (RTCDataChannelMessage message) {
        _handleDataChannelMessage(message.text);
      };

      // 4. Обработчик входящих треков (аудио от OpenAI)
      _pc?.onTrack = (RTCTrackEvent event) {
        print('🎵 Получен трек: ${event.track.kind}');
        if (event.track.kind == 'audio') {
          // Сохраняем remote stream
          _remoteStream = event.streams[0];
          _handleAudioTrack(event.streams[0]);
        }
      };

      // 5. Захватываем микрофон
      _localStream = await Helper.openCamera({
        'audio': {
          'mandatory': {
            'chromeMediaSource': 'user',
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          }
        }
      });

      // Добавляем локальный поток в peer connection (используем addTrack для Unified Plan)
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _pc?.addTrack(track, _localStream!);
        });
        print('🎤 Микрофон захвачен');
      }

      // 6. Создаем offer и устанавливаем local description
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      print('📝 Local description установлен');

      // 7. Отправляем offer в OpenAI API
      final session = await _createSession(offer.sdp ?? '');
      if (session == null) {
        throw Exception('Не удалось создать сессию');
      }

      // 8. Устанавливаем remote description
      final answer = session['answer'] as String?;
      if (answer != null) {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer, 'answer'),
        );
        print('📝 Remote description установлен');
      }

      _isConnected = true;
      print('✅ Подключено к Realtime API');

      // Запускаем цикл воспроизведения
      _startPlaybackLoop();
    } catch (e, stackTrace) {
      print('❌ Ошибка подключения: $e');
      print(stackTrace);
      onError?.call('Ошибка подключения: $e');
      rethrow;
    }
  }

  /// Отключается от API
  Future<void> disconnect() async {
    if (!_isConnected) return;

    print('🔌 Отключение от Realtime API...');

    _playbackTimer?.cancel();
    _isConnected = false;

    // Останавливаем микрофон
    await _localStream?.dispose();
    _localStream = null;

    // Закрываем data channel
    await _dc?.close();
    _dc = null;

    // Закрываем peer connection
    await _pc?.close();
    _pc = null;

    _audioBuffer.clear();
    await _audioController.close();

    _robot.disconnect(); // Отключаем Cozmo

    print('✅ Отключено');
  }

  /// Обрабатывает сообщения от OpenAI через data channel
  void _handleDataChannelMessage(String message) {
    try {
      final event = jsonDecode(message) as Map<String, dynamic>;
      final type = event['type'] as String?;

      switch (type) {
        case 'response.audio_transcript.delta':
          // Текст ответа (потоковый)
          final delta = event['delta'] as String?;
          if (delta != null) {
            print(delta);
            onAiTranscript?.call(delta);
          }
          break;

        case 'response.audio.delta':
          // Аудио чанк от OpenAI (PCM16 данные)
          final delta = event['delta'] as String?;
          if (delta != null && !_isRobotSpeaking) {
            _audioDeltaCount++;
            // Декодируем base64 аудио
            final audioBytes = base64Decode(delta);
            _totalAudioBytes += audioBytes.length;
            print('📦 Чанк #$_audioDeltaCount: +${audioBytes.length} байт (всего: $_totalAudioBytes)');
            addAudioData(audioBytes);
          }
          break;

        case 'input_audio_transcription.completed':
          // Распознанный текст пользователя
          _audioBuffer.clear();
          final transcript = event['transcript'] as String?;
          if (transcript != null) {
            print('👤 $transcript');
            onUserTranscript?.call(transcript);
          }
          break;

        case 'response.done':
          // Ответ завершен - обрабатываем аудио
          print('\n✅ Ответ получен.');
          print('📊 Статистика аудио:');
          print('   - Чанков: $_audioDeltaCount');
          print('   - Всего байт: $_totalAudioBytes');
          print('   - Размер буфера: ${_audioBuffer.length} байт');

          // TEMP: Воспроизводим тестовый файл для проверки
          if (_audioBuffer.isEmpty) {
            print('⚠️ Аудио буфер пуст (чанков не пришло через data channel)');
            print('💡 Временно воспроизводим тестовый файл...');
            _testPlaybackWithHelloWav();
          } else {
            _processAudioResponse();
          }

          // Сбрасываем счетчики
          _audioDeltaCount = 0;
          _totalAudioBytes = 0;
          break;

        case 'error':
          final error = event['error'] as Map<String, dynamic>?;
          print('❌ Ошибка API: $error');
          onError?.call('API Error: $error');
          break;

        case 'session.updated':
          print('✅ Сессия обновлена');
          break;

        default:
          // Логируем другие события для отладки
          print('📩 Событие: $type');
          if (type != null && type.contains('audio')) {
            print('   🔍 Аудио событие! Полное: ${jsonEncode(event)}');
          }
          break;
      }
    } catch (e) {
      print('❌ Ошибка обработки сообщения: $e');
      onError?.call('Ошибка обработки сообщения: $e');
    }
  }

  /// Отправляет обновление инструкций сессии
  void _sendSessionUpdate(String instructions) {
    // Отправляем полную конфигурацию с новыми инструкциями
    final updateMsg = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': instructions,
        'voice': config.voice,
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
        }
      }
    };

    print('📤 Обновление инструкций сессии...');
    print('   Новые инструкции: $instructions');
    print('   Полное сообщение: ${jsonEncode(updateMsg)}');
    _dc?.send(RTCDataChannelMessage(jsonEncode(updateMsg)));
  }

  /// Отправляет конфигурацию сессии с кастомными инструкциями
  void _sendSessionConfigWithInstructions(String instructions) {
    final configMsg = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': instructions,
        'voice': config.voice,
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
        }
      }
    };
    

    final jsonMsg = jsonEncode(configMsg);
    print('📤 Подготовка конфигурации сессии с кастомными инструкциями...');
    print('   Голос: ${config.voice}');
    print('   Язык: ${config.language} (${config.voiceCode})');
    print('   Инструкции: $instructions');
    print('   Полное сообщение: $jsonMsg');

    // Проверяем состояние data channel
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      print('✅ Data channel открыт - отправляем немедленно');
      _dc?.send(RTCDataChannelMessage(jsonMsg));
    } else {
      print('⏳ Data channel не готов (${_dc?.state}) - ставим в очередь');
      _pendingSessionConfig = jsonMsg;
    }
  }

  /// Отправляет конфигурацию сессии в OpenAI
  void _sendSessionConfig() {
    final configMsg = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': config.systemInstructions,
        'voice': config.voice,
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
        }
      }
    };

    final jsonMsg = jsonEncode(configMsg);
    print('📤 Подготовка начальной конфигурации сессии...');
    print('   Голос: ${config.voice}');
    print('   Язык: ${config.language} (${config.voiceCode})');
    print('   Инструкции: ${config.systemInstructions}');
    print('   Полное сообщение: $jsonMsg');

    // Проверяем состояние data channel
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      print('✅ Data channel открыт - отправляем немедленно');
      _dc?.send(RTCDataChannelMessage(jsonMsg));
    } else {
      print('⏳ Data channel не готов (${_dc?.state}) - ставим в очередь');
      _pendingSessionConfig = jsonMsg;
    }
  }

  /// Создает сессию в OpenAI API
  Future<Map<String, dynamic>?> _createSession(String offerSdp) async {
    try {
      print('🌐 Создание сессии OpenAI...');

      final request = await _httpClient.postUrl(Uri.parse(config.sessionUrl));

      // Установка заголовков
      request.headers.contentType = ContentType.json;
      request.headers.add('Authorization', 'Bearer ${config.apiToken}');
      request.headers.add('apikey', config.apiSecret);

      // Body запроса
      final body = jsonEncode(config.createSessionBody(offerSdp));
      request.write(body);

      final response = await request.close();

      if (response.statusCode != 200) {
        print('❌ API Error: ${response.statusCode}');
        final responseBody = await response.transform(utf8.decoder).join();
        print('   Details: $responseBody');
        onError?.call('API Error: ${response.statusCode}');
        return null;
      }

      final responseData = await response.transform(utf8.decoder).join();
      final session = jsonDecode(responseData) as Map<String, dynamic>;

      print('✅ Сессия создана');
      print('📦 Полный ответ API: $responseData');

      // Проверяем есть ли инструкции из API
      String? instructionsFromApi;
      if (session.containsKey('prompt')) {
        print('🔑 Найден ключ "prompt" в ответе');
        try {
          final messages = session['prompt']['messages'] as List;
          print('📝 Сообщений: ${messages.length}');
          if (messages.isNotEmpty) {
            instructionsFromApi = messages[0]['content'] as String?;
            if (instructionsFromApi != null && instructionsFromApi.isNotEmpty) {
              print('📝 Инструкции из API: $instructionsFromApi');
            } else {
              print('⚠️ Инструкции пустые или null');
            }
          }
        } catch (e) {
          print('⚠️ Ошибка чтения инструкций: $e');
        }
      } else {
        print('⚠️ Ключ "prompt" не найден в ответе API');
        print('📦 Доступные ключи: ${session.keys.toList()}');
      }

      // Отправляем конфигурацию сессии (с промптом из API или дефолтным)
      if (instructionsFromApi != null && instructionsFromApi.isNotEmpty) {
        print('📤 Используем инструкции из API');
        _sendSessionConfigWithInstructions(instructionsFromApi);
      } else {
        print('📤 Используем дефолтные инструкции');
        _sendSessionConfig();
      }

      return session;
    } catch (e) {
      print('❌ Ошибка создания сессии: $e');
      onError?.call('Ошибка создания сессии: $e');
      return null;
    }
  }

  /// Обрабатывает входящий аудио поток от OpenAI
  void _handleAudioTrack(MediaStream stream) {
    print('🎵 Получен аудио поток от OpenAI');

    final audioTrack = stream.getAudioTracks()[0];
    if (audioTrack == null) {
      print('⚠️ Нет аудио трека');
      return;
    }

    // ❌ ОТКЛЮЧАЕМ воспроизведение на компьютере!
    audioTrack.enabled = false;
    print('🔇 Аудио трек отключен (воспроизведение только на Cozmo)');
  }

  /// Тестовое воспроизведение hello.wav
  void _testPlaybackWithHelloWav() async {
    if (!_robot.isConnected) {
      print('⚠️ Cozmo не подключен');
      return;
    }

    final testFile = '/Volumes/Data/projects/my/cozmo_app/pycozmo/rocket_dev/hello.wav';
    final file = File(testFile);

    if (!await file.exists()) {
      print('⚠️ Тестовый файл не существует: $testFile');
      return;
    }

    print('🎵 Тестовое воспроизведение: $testFile');
    await _playOnCozmo(testFile);
  }

  /// Обрабатывает накопленный аудио буфер
  Future<void> _processAudioResponse() async {
    if (_audioBuffer.isEmpty) {
      print('⚠️ Аудио буфер пуст');
      return;
    }

    print('📊 Размер буфера: ${_audioBuffer.length} байт');

    if (_audioBuffer.length < 1000) {
      print('⚠️ Слишком короткий аудио фрагмент');
      _audioBuffer.clear();
      return;
    }

    try {
      // 1. Сохраняем исходный WAV
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalWav = '/tmp/response_$timestamp.wav';
      final pcmData = Uint8List.fromList(_audioBuffer);
      final wavData = AudioProcessor.pcmToWav(pcmData);

      print('💾 Сохранение в файл...');
      final saved = await AudioProcessor.saveWavFile(originalWav, wavData);

      if (!saved) {
        print('❌ Ошибка сохранения');
        _audioBuffer.clear();
        return;
      }

      _audioBuffer.clear();

      // 2. Применяем робо-эффекты
      final processedWav = '/tmp/response_processed_$timestamp.wav';
      final success = await AudioProcessor.applyRobotEffect(
        inputWav: originalWav,
        outputWav: processedWav,
        pitch: 1.35,
        tempo: 0.9,
      );

      if (!success) {
        print('⚠️ Используем оригинальный аудио');
        _pendingAudioFile = originalWav;
      } else {
        print('✅ Робо-эффекты применены');
        _pendingAudioFile = processedWav;
      }

      print('✅ Файл помечен для воспроизведения');
    } catch (e) {
      print('❌ Ошибка обработки аудио: $e');
      onError?.call('Ошибка обработки аудио: $e');
      _audioBuffer.clear();
    }
  }

  /// Запускает цикл воспроизведения аудио на Cozmo
  void _startPlaybackLoop() {
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkPendingAudio();
    });
  }

  /// Проверяет и воспроизводит готовое аудио
  Future<void> _checkPendingAudio() async {
    if (_pendingAudioFile == null || _isRobotSpeaking) {
      return;
    }

    final audioFile = _pendingAudioFile;
    _pendingAudioFile = null;

    await _playOnCozmo(audioFile!);
  }

  /// Воспроизводит аудио файл на Cozmo
  Future<void> _playOnCozmo(String filename) async {
    if (!_robot.isConnected) {
      print('⚠️ Cozmo не подключен');
      return;
    }

    print('🤖 Cozmo говорит...');
    _isRobotSpeaking = true;

    try {
      final file = File(filename);

      // Проверяем существование файла
      if (!await file.exists()) {
        print('❌ Файл НЕ существует: $filename');
        return;
      }

      final wavSize = (await file.length()) / 1024;

      print('📁 Файл: $filename (${wavSize.toStringAsFixed(1)} KB)');
      print('📂 Абсолютный путь: ${file.absolute.path}');

      // Устанавливаем громкость
      _robot.setVolume(65535);
      await Future.delayed(const Duration(milliseconds: 200));

      // Воспроизводим простым способом
      print('▶️ Запуск воспроизведения...');
      await _robot.playAudio(filename);

      print('✅ Воспроизведение завершено');
    } catch (e) {
      print('⚠️ Ошибка воспроизведения: $e');
      onError?.call('Ошибка воспроизведения: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      _isRobotSpeaking = false;
      print('🎤 (Слушаю...)');
    }
  }

  /// Добавляет аудио данные в буфер (для входящего аудио от OpenAI)
  void addAudioData(List<int> audioChunk) {
    if (!_isRobotSpeaking) {
      _audioBuffer.addAll(audioChunk);
      _audioController.add(audioChunk);
      print('📊 Буфер: ${_audioBuffer.length} байт (+${audioChunk.length})');
    }
  }

  /// Геттеры состояния
  bool get isConnected => _isConnected;
  bool get isRobotSpeaking => _isRobotSpeaking;
  String? get pendingAudioFile => _pendingAudioFile;

  /// Stream для входящих аудио данных
  Stream<List<int>> get audioStream => _audioController.stream;
}
