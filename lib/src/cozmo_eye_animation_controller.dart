library cozmo_eye_animation_controller;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'cozmo_client.dart';
import 'cozmo_face.dart';
import 'cozmo_anim_controller.dart';

/// Типы анимаций глаз робота Cozmo
enum EyeAnimationType {
  none,
  blink,
  blinkLoop,
  wander,
  sleep,
  wakeup,
  happy,
  sad,
  surprised,
  thinking,
}

/// Контроллер анимации глаз робота Cozmo
/// 
/// Предоставляет различные типы анимаций глаз, включая ожидание,
/// моргание и эмоциональные выражения. Автоматически
/// активируется при подключении к роботу.
class EyeAnimationController {
  final CozmoClient _client;
  final CozmoFace _face;
  final CozmoAnimController _animController;
  
  EyeAnimationType _currentAnimation = EyeAnimationType.none;
  Timer? _animationTimer;
  Timer? _blinkTimer;
  
  // Параметры анимации
  Duration _blinkInterval = const Duration(seconds: 4);
  Duration _wanderInterval = const Duration(milliseconds: 200); // Как в pycozmo (5 FPS)
  double _wanderAmplitude = 0.05;
  
  // Состояние
  bool _isActive = false;
  
  // Буфер для снижения частоты обновления
  bool _needsUpdate = false;
  Timer? _updateTimer;
  
  EyeAnimationController(this._client, this._face, this._animController);
  
  /// Активирует контроллер и запускает анимацию ожидания
  void activate() {
    if (_isActive) return;
    
    _isActive = true;
    print('👀 Eye Animation Controller activated');
    
    // Запускаем таймер для буферизированного обновления изображения (с частотой 5 FPS)
    _startUpdateTimer();
    
    // Запускаем анимацию ожидания по умолчанию
    _startWandering();
    
    // Принудительно обновляем лицо сразу после активации
    _needsUpdate = true;
  }
  
  /// Запускает таймер для буферизированного обновления изображения
  void _startUpdateTimer() {
    print('🕐 Starting eye update timer with 200ms interval');
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isActive) {
        print('🕐 Eye update timer canceled (inactive)');
        timer.cancel();
        return;
      }
      
      if (_needsUpdate) {
        print('🕐 Eye update timer: needs update = true');
        _needsUpdate = false;
        _updateFace();
      }
    });
  }
  
  /// Останавливает таймер обновления
  void _stopUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }
  
  /// Деактивирует контроллер и останавливает все анимации
  void deactivate() {
    if (!_isActive) return;
    
    _isActive = false;
    stopAnimation();
    _stopUpdateTimer();
    print('👀 Eye Animation Controller deactivated');
  }
  
  /// Запускает указанную анимацию
  void startAnimation(EyeAnimationType type) {
    stopAnimation();
    _currentAnimation = type;
    
    switch (type) {
      case EyeAnimationType.blink:
        _performBlink();
        break;
      case EyeAnimationType.blinkLoop:
        _startBlinkLoop();
        break;
      case EyeAnimationType.wander:
        _startWandering();
        break;
      case EyeAnimationType.sleep:
        _startSleep();
        break;
      case EyeAnimationType.wakeup:
        _startWakeup();
        break;
      case EyeAnimationType.happy:
        setHappy();
        break;
      case EyeAnimationType.sad:
        setSad();
        break;
      case EyeAnimationType.surprised:
        setSurprised();
        break;
      case EyeAnimationType.thinking:
        setThinking();
        break;
      default:
        break;
    }
  }
  
  /// Останавливает текущую анимацию
  void stopAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _stopUpdateTimer();
    _currentAnimation = EyeAnimationType.none;
  }
  
  /// Выполняет однократное моргание
  void blink() {
    if (_currentAnimation != EyeAnimationType.none && 
        _currentAnimation != EyeAnimationType.blinkLoop) return;
    
    // Сохраняем текущую анимацию
    final previousAnimation = _currentAnimation;
    _currentAnimation = EyeAnimationType.blink;
    
    // Закрываем веки
    _face.setLeftEyelid(1.0);
    _face.setRightEyelid(1.0);
    _needsUpdate = true;
    
    // Открываем веки через 150мс
    _animationTimer = Timer(const Duration(milliseconds: 150), () {
      _face.setLeftEyelid(0.0);
      _face.setRightEyelid(0.0);
      _needsUpdate = true;
      
      // Восстанавливаем предыдущую анимацию
      if (previousAnimation == EyeAnimationType.blinkLoop) {
        _startBlinkLoop();
      } else {
        _currentAnimation = previousAnimation;
      }
    });
  }
  
  /// Запускает циклическое моргание
  void _startBlinkLoop() {
    _currentAnimation = EyeAnimationType.blinkLoop;
    _blinkTimer = Timer.periodic(_blinkInterval, (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      _performBlink();
    });
  }
  
  /// Выполняет моргание (внутренний метод)
  void _performBlink() {
    // Закрываем веки
    _face.setLeftEyelid(1.0);
    _face.setRightEyelid(1.0);
    _needsUpdate = true;
    
    // Открываем веки через 150мс
    _animationTimer = Timer(const Duration(milliseconds: 150), () {
      _face.setLeftEyelid(0.0);
      _face.setRightEyelid(0.0);
      _needsUpdate = true;
    });
  }
  
  /// Останавливает циклическое моргание
  void stopBlinkLoop() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    
    if (_currentAnimation == EyeAnimationType.blinkLoop) {
      _currentAnimation = EyeAnimationType.none;
    }
  }
  
  /// Запускает циклическое моргание (публичный метод)
  void startBlinkLoop() {
    _startBlinkLoop();
  }
  
  /// Запускает анимацию ожидания (осмотр по сторонам)
  void _startWandering() {
    _currentAnimation = EyeAnimationType.wander;
    double wanderPhase = 0.0;
    
    _animationTimer = Timer.periodic(_wanderInterval, (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      
      wanderPhase += 0.1;
      
      // Гармоническое движение глаз
      double leftX = 0.35 + _wanderAmplitude * sin(wanderPhase);
      double rightX = 0.65 + _wanderAmplitude * sin(wanderPhase + pi);
      
      // Небольшие вертикальные движения
      double leftY = 0.5 + 0.02 * cos(wanderPhase * 2);
      double rightY = 0.5 + 0.02 * cos(wanderPhase * 2);
      
      _face.setLeftEyeX(leftX);
      _face.setLeftEyeY(leftY);
      _face.setRightEyeX(rightX);
      _face.setRightEyeY(rightY);
      
      _needsUpdate = true;
    });
  }
  
  /// Останавливает анимацию ожидания
  void _stopWandering() {
    if (_currentAnimation == EyeAnimationType.wander) {
      _animationTimer?.cancel();
      _animationTimer = null;
      _currentAnimation = EyeAnimationType.none;
    }
  }
  
  /// Запускает анимацию засыпания
  void _startSleep() {
    _currentAnimation = EyeAnimationType.sleep;
    double lidProgress = 0.0;
    
    _animationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      
      lidProgress += 0.025; // 25% прогресса каждые 50мс
      
      if (lidProgress >= 1.0) {
        lidProgress = 1.0;
        _animationTimer?.cancel();
        _animationTimer = null;
        _currentAnimation = EyeAnimationType.none;
      }
      
      _face.setLeftEyelid(lidProgress);
      _face.setRightEyelid(lidProgress);
      
      // Уменьшаем глаза при засыпании
      double eyeSize = 0.25 * (1.0 - lidProgress * 0.3);
      _face.setLeftEyeSize(eyeSize);
      _face.setRightEyeSize(eyeSize);
      
      _needsUpdate = true;
    });
  }
  
  /// Запускает анимацию пробуждения
  void _startWakeup() {
    _currentAnimation = EyeAnimationType.wakeup;
    double lidProgress = 1.0;
    
    _animationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }
      
      lidProgress -= 0.025; // 25% прогресса каждые 50мс
      
      if (lidProgress <= 0.0) {
        lidProgress = 0.0;
        _animationTimer?.cancel();
        _animationTimer = null;
        _currentAnimation = EyeAnimationType.none;
        
        // Возвращаемся к анимации ожидания
        _startWandering();
      }
      
      _face.setLeftEyelid(lidProgress);
      _face.setRightEyelid(lidProgress);
      
      // Увеличиваем глаза при пробуждении
      double eyeSize = 0.25 * (1.0 - lidProgress * 0.3);
      _face.setLeftEyeSize(eyeSize);
      _face.setRightEyeSize(eyeSize);
      
      _needsUpdate = true;
    });
  }
  
  /// Устанавливает счастливое выражение глаз
  void setHappy() {
    _face.setHappy();
    _needsUpdate = true;
  }
  
  /// Устанавливает грустное выражение глаз
  void setSad() {
    _face.setSad();
    _needsUpdate = true;
  }
  
  /// Устанавливает удивленное выражение глаз
  void setSurprised() {
    _face.setSurprised();
    _needsUpdate = true;
  }
  
  /// Устанавливает задумчивое выражение глаз
  void setThinking() {
    _face.setThinking();
    _needsUpdate = true;
  }
  
  /// Обновляет отображение лица на роботе
  void _updateFace() {
    if (!_client.isConnected) {
      print('🚫 Eye controller update: client not connected');
      return; // Проверяем соединение перед отправкой
    }
    
    _face.render();
    final faceData = _face.encode();
    print('👀 Eye controller update: sending ${faceData.length} bytes');
    // Отправляем напрямую через простой UDP пакет, минуя надежный протокол
    _sendDisplayImageCommand(faceData);
  }
  
  /// Отправляет команду отображения изображения напрямую через клиент
  void _sendDisplayImageCommand(List<int> faceData) {
    // Используем клиент для отправки, но без надежного протокола
    final payload = [
      0x97, // DisplayImage command ID
      0x00, // Reserved
      faceData.length, // Image size
      ...faceData // Image data
    ];
    
    // Отправляем напрямую через sendRaw, минуя надежный протокол
    _client.sendRaw(payload);
  }
  
  /// Устанавливает интервал моргания
  void setBlinkInterval(Duration interval) {
    _blinkInterval = interval;
    
    // Если запущена циклическая анимация моргания, перезапускаем ее
    if (_currentAnimation == EyeAnimationType.blinkLoop) {
      stopBlinkLoop();
      _startBlinkLoop();
    }
  }
  
  /// Устанавливает интервал анимации ожидания
  void setWanderInterval(Duration interval) {
    _wanderInterval = interval;
    
    // Если запущена анимация ожидания, перезапускаем ее
    if (_currentAnimation == EyeAnimationType.wander) {
      _stopWandering();
      _startWandering();
    }
  }
  
  /// Устанавливает амплитуду движения глаз при ожидании
  void setWanderAmplitude(double amplitude) {
    _wanderAmplitude = amplitude;
  }
  
  /// Геттеры текущей анимации
  EyeAnimationType get currentAnimation => _currentAnimation;
  
  /// Геттер состояния активации
  bool get isActive => _isActive;
}