# Спецификация реализации EyeAnimationController

## 🎯 Цель

Создать класс `EyeAnimationController` для управления анимациями глаз робота Cozmo, который автоматически активируется при установке соединения с устройством.

## 📋 Требования

### Функциональные требования

1. **Типы анимаций**:
   - Ожидание (плавное движение глаз)
   - Моргание (однократное и циклическое)
   - Сон (постепенное закрытие глаз)
   - Пробуждение (постепенное открытие глаз)
   - Эмоциональные выражения

2. **Автоматическая активация**:
   - Запускаться при успешном подключении к роботу
   - Останавливаться при отключении

3. **Интеграция с существующей архитектурой**:
   - Использовать `CozmoFace` для рисования
   - Использовать `CozmoAnimController` для отображения
   - Использовать `CozmoClient` для отправки команд

### Технические требования

1. **Производительность**:
   - Анимации не должны блокировать основной поток
   - Использовать Timer для асинхронности
   - Минимальная нагрузка на сеть

2. **Совместимость**:
   - Работать с существующими `CozmoRobot` и компонентами
   - Не конфликтовать с аудио-системой
   - Поддерживать остановку и возобновление

3. **Расширяемость**:
   - Легко добавлять новые типы анимаций
   - Настраиваемые параметры (длительность, амплитуда)
   - Поддержка пользовательских колбэков

## 🏗️ Архитектура

### Структура класса

```dart
library cozmo_eye_animation_controller;

import 'dart:async';
import 'dart:math';
import 'cozmo_client.dart';
import 'cozmo_face.dart';
import 'cozmo_anim_controller.dart';
import 'cozmo_robot.dart';

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

class EyeAnimationController {
  final CozmoClient _client;
  final CozmoFace _face;
  final CozmoAnimController _animController;
  
  EyeAnimationType _currentAnimation = EyeAnimationType.none;
  Timer? _animationTimer;
  
  // Параметры анимации
  Duration _blinkInterval = Duration(seconds: 4);
  Duration _wanderInterval = Duration(milliseconds: 2000);
  double _wanderAmplitude = 0.05;
  
  // Состояние
  bool _isActive = false;
  
  EyeAnimationController(this._client, this._face, this._animController);
  
  // Основные методы
  void activate();
  void deactivate();
  void startAnimation(EyeAnimationType type);
  void stopAnimation();
  
  // Специфические анимации
  void blink();
  void startBlinkLoop({Duration? interval});
  void stopBlinkLoop();
  void startWandering({Duration? interval});
  void stopWandering();
  void startSleep();
  void startWakeup();
  
  // Эмоциональные анимации
  void setHappy();
  void setSad();
  void setSurprised();
  void setThinking();
  
  // Настройка параметров
  void setBlinkInterval(Duration interval);
  void setWanderInterval(Duration interval);
  void setWanderAmplitude(double amplitude);
  
  // Геттеры
  bool get isActive => _isActive;
  EyeAnimationType get currentAnimation => _currentAnimation;
}
```

### Интеграция с CozmoRobot

```dart
// В cozmo_robot.dart
class CozmoRobot {
  // ... существующие поля
  late final EyeAnimationController eyeController;
  
  CozmoRobot._internal() {
    // ... существующая инициализация
    
    // Добавление EyeAnimationController
    eyeController = EyeAnimationController(_client, _face, _animController);
  }
  
  Future<String?> connect() async {
    final res = await _client.connect();
    
    if (res == null) {
      // ... существующие команды инициализации
      
      // Автоматическая активация анимации глаз
      print('👀 Starting eye animation controller...');
      eyeController.activate();
    }
    return res;
  }
  
  void disconnect() {
    // Деактивация контроллера глаз
    eyeController.deactivate();
    
    // ... существующие команды отключения
    animController.stop();
    _client.disconnect();
  }
  
  // ... существующие методы
}
```

## 🧩 Детали реализации

### 1. Анимация ожидания (wandering)

```dart
void _startWandering() {
  if (_currentAnimation == EyeAnimationType.wander) return;
  
  _currentAnimation = EyeAnimationType.wander;
  double wanderPhase = 0.0;
  
  _animationTimer = Timer.periodic(_wanderInterval, (timer) {
    if (!_isActive) return;
    
    wanderPhase += 0.1;
    
    // Гармоническое движение глаз
    double leftX = 0.35 + _wanderAmplitude * sin(wanderPhase);
    double rightX = 0.65 + _wanderAmplitude * sin(wanderPhase + pi);
    
    // Небольшие вертикальные движения
    double leftY = 0.5 + 0.02 * cos(wanderPhase * 2);
    double rightY = 0.5 + 0.02 * cos(wanderPhase * 2);
    
    _face._leftEyeX = leftX;
    _face._leftEyeY = leftY;
    _face._rightEyeX = rightX;
    _face._rightEyeY = rightY;
    
    _updateFace();
  });
}
```

### 2. Анимация моргания

```dart
void blink() {
  if (_currentAnimation != EyeAnimationType.none) return;
  
  // Сохраняем текущую анимацию
  final previousAnimation = _currentAnimation;
  _currentAnimation = EyeAnimationType.blink;
  
  // Закрываем веки
  _face._leftEyelid = 1.0;
  _face._rightEyelid = 1.0;
  _updateFace();
  
  // Открываем веки через 150мс
  _animationTimer = Timer(Duration(milliseconds: 150), () {
    _face._leftEyelid = 0.0;
    _face._rightEyelid = 0.0;
    _updateFace();
    
    // Восстанавливаем предыдущую анимацию
    _currentAnimation = previousAnimation;
    
    // Если была циклическая анимация, перезапускаем ее
    if (previousAnimation == EyeAnimationType.blinkLoop) {
      _startBlinkLoop();
    }
  });
}
```

### 3. Анимация сна

```dart
void startSleep() {
  if (_currentAnimation == EyeAnimationType.sleep) return;
  
  _currentAnimation = EyeAnimationType.sleep;
  double lidProgress = 0.0;
  
  _animationTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
    if (!_isActive) return;
    
    lidProgress += 0.025; // 25% прогресса каждые 50мс
    
    if (lidProgress >= 1.0) {
      lidProgress = 1.0;
      _animationTimer?.cancel();
      _currentAnimation = EyeAnimationType.none;
    }
    
    _face._leftEyelid = lidProgress;
    _face._rightEyelid = lidProgress;
    
    // Уменьшаем глаза при засыпании
    _face._leftEyeSize = 0.25 * (1.0 - lidProgress * 0.3);
    _face._rightEyeSize = 0.25 * (1.0 - lidProgress * 0.3);
    
    _updateFace();
  });
}
```

## 🎮 Интеграция с FlutterFlow

### Кастомные действия

1. **Моргание глаз**
```dart
// lib/custom_code/actions/robot_eye_blink.dart
Future robotEyeBlink() async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  robot.eyeController.blink();
}
```

2. **Циклическое моргание**
```dart
// lib/custom_code/actions/robot_eye_blink_loop.dart
Future robotEyeBlinkLoop({bool enable = true}) async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  if (enable) {
    robot.eyeController.startBlinkLoop();
  } else {
    robot.eyeController.stopBlinkLoop();
  }
}
```

3. **Установка эмоции**
```dart
// lib/custom_code/actions/robot_eye_emotion.dart
Future robotEyeEmotion(String emotion) async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  switch (emotion.toLowerCase()) {
    case 'happy':
      robot.eyeController.setHappy();
      break;
    case 'sad':
      robot.eyeController.setSad();
      break;
    case 'surprised':
      robot.eyeController.setSurprised();
      break;
    case 'thinking':
      robot.eyeController.setThinking();
      break;
    default:
      robot.eyeController.stopAnimation();
  }
}
```

### UI компоненты

```dart
// EyeControlWidget для FlutterFlow
class EyeControlWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text('Управление глазами'),
            
            // Кнопки анимаций
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FFButtonWidget(
                  onPressed: () async {
                    await actions.robotEyeBlink();
                  },
                  text: 'Моргнуть',
                ),
                FFButtonWidget(
                  onPressed: () async {
                    await actions.robotEyeEmotion('happy');
                  },
                  text: 'Счастливые',
                ),
                FFButtonWidget(
                  onPressed: () async {
                    await actions.robotEyeEmotion('thinking');
                  },
                  text: 'Думающие',
                ),
              ],
            ),
            
            // Переключатель циклического моргания
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Циклическое моргание:'),
                Switch(
                  value: FFAppState().eyeBlinkLoop,
                  onChanged: (value) async {
                    FFAppState().eyeBlinkLoop = value;
                    await actions.robotEyeBlinkLoop(enable: value);
                  },
                ),
              ],
            ),
          ].divide(SizedBox(height: 8.0)),
        ),
      ),
    );
  }
}
```

## 🧪 Тестирование

### Unit тесты

```dart
// test/cozmo_eye_animation_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

void main() {
  group('EyeAnimationController Tests', () {
    late EyeAnimationController eyeController;
    late MockCozmoClient mockClient;
    late CozmoFace face;
    late MockCozmoAnimController mockAnimController;
    
    setUp(() {
      mockClient = MockCozmoClient();
      face = CozmoFace();
      mockAnimController = MockCozmoAnimController();
      eyeController = EyeAnimationController(mockClient, face, mockAnimController);
    });
    
    tearDown(() {
      eyeController.deactivate();
    });
    
    test('activate() should start wandering animation', () {
      eyeController.activate();
      
      expect(eyeController.isActive, true);
      expect(eyeController.currentAnimation, EyeAnimationType.wander);
    });
    
    test('blink() should temporarily close and open eyelids', () async {
      eyeController.activate();
      
      // Начинаем моргание
      eyeController.blink();
      
      // Проверяем, что веки закрыты
      expect(face._leftEyelid, 1.0);
      expect(face._rightEyelid, 1.0);
      
      // Ждем окончания моргания
      await Future.delayed(Duration(milliseconds: 200));
      
      // Проверяем, что веки открыты
      expect(face._leftEyelid, 0.0);
      expect(face._rightEyelid, 0.0);
    });
    
    test('setHappy() should set happy expression', () {
      eyeController.activate();
      
      eyeController.setHappy();
      
      // Проверяем параметры счастливых глаз
      expect(face._leftEyeSize, 0.28);
      expect(face._rightEyeSize, 0.28);
      expect(face._leftEyelid, -0.1);
      expect(face._rightEyelid, -0.1);
    });
  });
}
```

### Интеграционные тесты

```dart
// test/cozmo_eye_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

void main() {
  group('Eye Animation Integration Tests', () {
    testWidgets('Eyes should animate after robot connection', (WidgetTester tester) async {
      final robot = CozmoRobot.instance;
      
      // Подключаемся к роботу
      final error = await robot.connect();
      expect(error, isNull);
      
      // Проверяем, что контроллер глаз активен
      expect(robot.eyeController.isActive, true);
      expect(robot.eyeController.currentAnimation, EyeAnimationType.wander);
      
      // Отключаемся
      robot.disconnect();
      
      // Проверяем, что контроллер глаз деактивирован
      expect(robot.eyeController.isActive, false);
    });
  });
}
```

## 📚 Документация

### API документация

```dart
/// Контроллер анимации глаз робота Cozmo
/// 
/// Автоматически активируется при подключении к роботу
/// и предоставляет различные типы анимаций глаз.
/// 
/// Пример использования:
/// ```dart
/// final robot = CozmoRobot.instance;
/// await robot.connect();
/// 
/// // Однократное моргание
/// robot.eyeController.blink();
/// 
/// // Циклическое моргание каждые 3 секунды
/// robot.eyeController.startBlinkLoop(interval: Duration(seconds: 3));
/// 
/// // Счастливое выражение
/// robot.eyeController.setHappy();
/// 
/// // Остановка всех анимаций
/// robot.eyeController.stopAnimation();
/// ```
class EyeAnimationController {
  /// Создает контроллер анимации глаз
  /// 
  /// [client] - клиент для отправки команд
  /// [face] - объект для рисования лица
  /// [animController] - контроллер для отображения
  EyeAnimationController(this.client, this.face, this.animController);
  
  /// Активирует контроллер и запускает анимацию ожидания
  /// 
  /// Автоматически вызывается при подключении к роботу
  void activate();
  
  /// Деактивирует контроллер и останавливает все анимации
  /// 
  /// Автоматически вызывается при отключении от робота
  void deactivate();
  
  /// Запускает указанную анимацию
  /// 
  /// [type] - тип анимации для запуска
  void startAnimation(EyeAnimationType type);
  
  /// Останавливает текущую анимацию
  void stopAnimation();
  
  /// Выполняет однократное моргание
  void blink();
  
  /// Запускает циклическое моргание
  /// 
  /// [interval] - интервал между морганиями (по умолчанию 4 секунды)
  void startBlinkLoop({Duration? interval});
  
  /// Останавливает циклическое моргание
  void stopBlinkLoop();
  
  /// Устанавливает счастливое выражение глаз
  void setHappy();
  
  /// Устанавливает грустное выражение глаз
  void setSad();
  
  /// Устанавливает удивленное выражение глаз
  void setSurprised();
  
  /// Устанавливает думающее выражение глаз
  void setThinking();
  
  /// Текущий статус активации контроллера
  bool get isActive;
  
  /// Текущая выполняемая анимация
  EyeAnimationType get currentAnimation;
}
```

## 🚀 План внедрения

### Этап 1: Реализация базового класса

1. Создать файл `cozmo_eye_animation_controller.dart`
2. Реализовать базовую структуру класса
3. Добавить в `cozmo_dart_lib.dart` экспорт

### Этап 2: Интеграция с CozmoRobot

1. Добавить `eyeController` в `CozmoRobot`
2. Интегрировать активацию в `connect()`
3. Интегрировать деактивацию в `disconnect()`

### Этап 3: Реализация анимаций

1. Реализовать базовые анимации (blink, wander, sleep)
2. Добавить эмоциональные анимации (happy, sad, surprised)
3. Реализовать параметры конфигурации

### Этап 4: Интеграция с FlutterFlow

1. Создать кастомные действия
2. Создать UI компоненты
3. Добавить в главное окно приложения

### Этап 5: Тестирование

1. Написать unit тесты
2. Написать интеграционные тесты
3. Провести ручное тестирование

## 📊 Метрики успеха

1. **Функциональность**:
   - Все анимации работают корректно
   - Автоматическая активация при подключении
   - Корректная деактивация при отключении

2. **Производительность**:
   - Анимации не влияют на производительность приложения
   - Минимальная нагрузка на сеть
   - Плавная работа без прерываний

3. **Надежность**:
   - Отсутствие конфликтов с другими системами
   - Корректная обработка ошибок
   - Устойчивая работа при нестабильном соединении

---

**Версия:** 1.0  
**Дата:** 2026-01-10  
**Автор:** Cozmo Development Team