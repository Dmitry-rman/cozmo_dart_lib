library cozmo_anim_controller;

import 'dart:async';
import 'dart:typed_data';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';

class CozmoAnimController {
  final CozmoClient _client;
  
  static CozmoAnimController? _instance;
  
  Timer? _loopTimer;
  bool _running = false;
  
  // Флаг: если true, значит аудио-модуль сейчас работает,
  // и нам НЕЛЬЗЯ слать тишину.
  bool _isAudioBusy = false;
  
  Uint8List? _currentImagePayload;
  int _tickCounter = 0;
  
  static final Uint8List _clearScreenPayload = Uint8List.fromList([0x03, 0x01, 0x00, 0x3f, 0x3f]);

  CozmoAnimController(this._client) {
    _currentImagePayload = _clearScreenPayload;
  }

  void start() {
    if (_running) return;
    _client.sendCommand(CozmoCmd.enableAnimState, [1]);
    _running = true;
    _tickCounter = 0;
    _isAudioBusy = false;

    // Тикаем 30 раз в секунду
    _loopTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_client.isConnected) {
        timer.cancel();
        return;
      }
      _tick();
    });
    print('🎬 AnimationController started');
  }

  void stop() {
    _running = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _client.sendCommand(CozmoCmd.displayImage, _clearScreenPayload);
  }

  /// Главный метод, который вызывается аудио-модулем
  void setAudioBusy(bool busy) {
    _isAudioBusy = busy;
    print('🔈 Audio Busy Mode: $busy (instance: ${_instance.hashCode})');
  }

  void _tick() {
    if (!_running || _isAudioBusy) return;

    // 1. АУДИО / ТИШИНА
    // Если аудио занято - МЫ МОЛЧИМ (не шлем ничего в аудио-канал).
    // Если аудио свободно - шлем тишину, чтобы робот знал, что мы тут.
     _client.sendCommand(CozmoCmd.outputSilence, []);
    
    // 2. ЭКРАН
    // Шлем картинку раз в секунду (каждые 30 тиков), 
    // ДАЖЕ ЕСЛИ АУДИО ИГРАЕТ. Это держит экран включенным.
    if (_tickCounter % 30 == 0 && _currentImagePayload != null) {
      _client.sendCommand(CozmoCmd.displayImage, _currentImagePayload!);
    }
    
    _tickCounter++;
  }

  void displayImage(Uint8List encodedImagePayload) {
    _currentImagePayload = encodedImagePayload;
    _client.sendCommand(CozmoCmd.displayImage, _currentImagePayload!);
  }

  void clearScreen() {
    _currentImagePayload = _clearScreenPayload;
    _client.sendCommand(CozmoCmd.displayImage, _clearScreenPayload);
  }
}