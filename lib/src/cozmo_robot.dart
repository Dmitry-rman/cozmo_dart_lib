library cozmo_robot;

import 'dart:async';
import 'dart:typed_data';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';
import 'cozmo_audio.dart';
import 'cozmo_head.dart';
import 'cozmo_drive.dart';
import 'cozmo_lift.dart';
import 'cozmo_anim_controller.dart';
import 'cozmo_simple_image.dart';
import 'cozmo_face.dart';
import 'cozmo_eye_animation_controller.dart'; // 🆕 Изменено на импорт из файла

class CozmoRobot {
  final CozmoClient _client = CozmoClient.instance;

  static final CozmoRobot _instance = CozmoRobot._internal();
  static CozmoRobot get instance => _instance;

  late final CozmoAudio audio;
  late final CozmoHead head;
  late final CozmoDrive drive;
  late final CozmoLift lift;
  late final CozmoAnimController animController;
  late final CozmoFace face;
  late final EyeAnimationController eyeController;

  CozmoRobot._internal() {
    // Сначала создаем контроллер анимаций
    animController = CozmoAnimController(_client);
    
    // 🆕 Создаем лицо и контроллер анимаций глаз
    face = CozmoFace();
    eyeController = EyeAnimationController(_client, face, animController);
    
    // Передаем его в аудио
    audio = CozmoAudio(_client, animController);
    
    head = CozmoHead(_client);
    drive = CozmoDrive(_client);
    lift = CozmoLift(_client);
  }

  Future<String?> connect() async {
    final res = await _client.connect();
    
    if (res == null) {
      print('⏳ Initializing robot systems...');

      _client.sendCommand(CozmoCmd.robotState, [1]);
      await Future.delayed(const Duration(milliseconds: 50));

      final now = DateTime.now().millisecondsSinceEpoch;
      _client.sendCommand(CozmoCmd.syncTime, [...uint32(now), ...uint32(0)]);
      await Future.delayed(const Duration(milliseconds: 50));

      _client.sendCommand(CozmoCmd.enableRobotState, [...uint32(0), ...uint32(0), ...uint32(1), ...float32(0.0), ...float32(0.0), ...uint32(0x80000000)]);
      await Future.delayed(const Duration(milliseconds: 50));

      print('🎬 Starting Animation Controller...');
      animController.start();

      print('☀️ Waking up...');
      await head.playAnimation(CozmoAnimation.wakeUp);
      
      await Future.delayed(const Duration(seconds: 2));

      print('👀 Displaying test eyes...');
      final eyesImage = CozmoSimpleImage.createEyes();
      displayImage(eyesImage);
      
      print('✅ Robot Ready & Screen ON');
      
      // 🆕 Активируем контроллер анимаций глаз после инициализации
      print('👀 Starting Eye Animation Controller...');
      eyeController.activate();
    }
    return res;
  }

  void disconnect() {
    // 🆕 Деактивируем контроллер глаз перед отключением
    eyeController.deactivate();
    
    animController.stop();
    _client.disconnect();
  }

  // --- Геттеры ---
  bool get isConnected => _client.isConnected;
  DateTime? get lastPacketTime => _client.lastPacketTime;

  // --- Proxy методы ---
  void setVolume(int volume) {
    volume = volume.clamp(0, 100);
    final raw = (volume * 65535 / 100).round();
    _client.sendCommand(CozmoCmd.setVolume, [...uint16(raw)]);
  }

  // ИСПРАВЛЕНО: Убраны лишние вызовы setPlayingAudio
  Future<void> playAudio(String path, {void Function(double)? onProgress}) async {
    await audio.playWav(path, onProgress: onProgress);
  }

  Future<void> playPCMData(List<int> pcmData) async {
    await audio.playPCMData(pcmData);
  }

  Future<void> playAnimation(CozmoAnimation anim, {int loops = 1}) async {
    await head.playAnimation(anim, loops: loops);
  }

  Future<void> playEmotion(CozmoEmotion emotion) async {
    await head.playEmotion(emotion);
  }

  void displayImage(CozmoSimpleImage image) {
    final rleData = image.encodeRLE();
    // Заголовок [Flags=3, ImgID=1, ChunkID=0]
    final payload = Uint8List.fromList([0x03, 0x01, 0x00, ...rleData]);
    animController.displayImage(payload);
  }

  void clearScreen() {
    animController.clearScreen();
  }
}