# EyeAnimationController для cozmo_dart_lib

## 📋 Обзор

`EyeAnimationController` - это компонент для управления анимациями глаз робота Cozmo, включая ожидание, моргание и другие выражения. Контроллер автоматически активируется при установке соединения с устройством.

## 🎯 Функциональность

### Основные возможности

1. **Анимация ожидания** - плавное движение глаз при простое
2. **Моргание** - периодическое или инициируемое моргание
3. **Эмоциональные выражения** - настройка глаз под разные состояния
4. **Автоматическая активация** - запуск при подключении к роботу

### Типы анимаций

- `EyeBlink` - однократное моргание
- `EyeBlinkLoop` - циклическое моргание с настраиваемым интервалом
- `EyeWander` - плавное движение глаз ("осматривается")
- `EyeSleep` - постепенное закрытие глаз при засыпании
- `EyeWakeup` - постепенное открытие глаз при пробуждении

## 🏗️ Архитектура

### Структура класса

```dart
class EyeAnimationController {
  // Основные компоненты
  final CozmoClient _client;
  final CozmoFace _face;
  final CozmoAnimController _animController;
  
  // Состояние анимации
  EyeAnimationType _currentAnimation = EyeAnimationType.none;
  Timer? _animationTimer;
  
  // Параметры анимации
  Duration _blinkInterval = Duration(seconds: 4);
  Duration _wanderInterval = Duration(milliseconds: 2000);
  
  // Конструктор
  EyeAnimationController(this._client, this._face, this._animController);
  
  // Управление анимацией
  void startAnimation(EyeAnimationType type);
  void stopAnimation();
  
  // Специфические анимации
  void blink();
  void startBlinkLoop({Duration? interval});
  void stopBlinkLoop();
  void startWandering({Duration? interval});
  void stopWandering();
  
  // Автоматическая активация
  void activate();
  void deactivate();
}
```

### Типы анимаций

```dart
enum EyeAnimationType {
  none,
  blink,
  blinkLoop,
  wander,
  sleep,
  wakeup,
}
```

## 🔧 Реализация

### 1. Инициализация при подключении

```dart
// В CozmoRobot.connect()
final eyeController = EyeAnimationController(_client, _face, _animController);

// Автоматическая активация после успешного подключения
if (res == null) {
  eyeController.activate();
}
```

### 2. Анимация моргания

```dart
void blink() {
  _currentAnimation = EyeAnimationType.blink;
  
  // Закрываем веки
  _face._leftEyelid = 1.0;
  _face._rightEyelid = 1.0;
  _face.render();
  _animController.displayImage(_face.encode());
  
  // Открываем веки через 150мс
  _animationTimer = Timer(Duration(milliseconds: 150), () {
    _face._leftEyelid = 0.0;
    _face._rightEyelid = 0.0;
    _face.render();
    _animController.displayImage(_face.encode());
    _currentAnimation = EyeAnimationType.none;
  });
}
```

### 3. Анимация ожидания (осмотр по сторонам)

```dart
void _startWandering() {
  _currentAnimation = EyeAnimationType.wander;
  double wanderPhase = 0.0;
  
  _animationTimer = Timer.periodic(_wanderInterval, (timer) {
    wanderPhase += 0.2;
    
    // Гармоническое движение глаз
    double leftX = 0.35 + 0.05 * math.sin(wanderPhase);
    double rightX = 0.65 + 0.05 * math.sin(wanderPhase + math.pi);
    
    // Небольшие вертикальные движения
    double leftY = 0.5 + 0.03 * math.cos(wanderPhase * 2);
    double rightY = 0.5 + 0.03 * math.cos(wanderPhase * 2);
    
    _face._leftEyeX = leftX;
    _face._leftEyeY = leftY;
    _face._rightEyeX = rightX;
    _face._rightEyeY = rightY;
    
    _face.render();
    _animController.displayImage(_face.encode());
  });
}
```

### 4. Анимация засыпания

```dart
void sleep() {
  _currentAnimation = EyeAnimationType.sleep;
  
  // Постепенно закрываем веки
  double lidProgress = 0.0;
  _animationTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
    lidProgress += 0.1;
    
    if (lidProgress >= 1.0) {
      lidProgress = 1.0;
      timer.cancel();
      _currentAnimation = EyeAnimationType.none;
    }
    
    _face._leftEyelid = lidProgress;
    _face._rightEyelid = lidProgress;
    
    // Уменьшаем глаза при засыпании
    _face._leftEyeSize = 0.25 * (1.0 - lidProgress * 0.3);
    _face._rightEyeSize = 0.25 * (1.0 - lidProgress * 0.3);
    
    _face.render();
    _animController.displayImage(_face.encode());
  });
}
```

## 🎮 Интеграция с FlutterFlow

### Кастомное действие для моргания

```dart
// lib/custom_code/actions/robot_eye_blink.dart
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future robotEyeBlink() async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  // Используем eye controller через robot
  robot.eyeController.blink();
}
```

### Кастомное действие для циклического моргания

```dart
// lib/custom_code/actions/robot_eye_blink_loop.dart
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

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

## 📊 Параметры конфигурации

### Настройки по умолчанию

```dart
class EyeAnimationConfig {
  // Интервалы
  static const Duration defaultBlinkInterval = Duration(seconds: 4);
  static const Duration defaultWanderInterval = Duration(milliseconds: 2000);
  
  // Длительности
  static const Duration blinkDuration = Duration(milliseconds: 150);
  static const Duration sleepDuration = Duration(milliseconds: 2000);
  static const Duration wakeupDuration = Duration(milliseconds: 1000);
  
  // Амплитуда движений
  static const double wanderAmplitude = 0.05;
  static const double verticalWanderAmplitude = 0.03;
}
```

### Пользовательские настройки

```dart
// В CozmoRobot._internal()
eyeController = EyeAnimationController(_client, _face, _animController);

// Настройка параметров
eyeController.setBlinkInterval(Duration(seconds: 3));
eyeController.setWanderAmplitude(0.08);

// Активация с настройками
eyeController.activate();
```

## 🔍 Адаптация паттернов из pycozmo

### Анализ pycozmo/procedural_face.py

Ключевые паттерны из pycozmo:

1. **Структура лица** - глаза, веки, брови
2. **Плавные переходы** - анимация через промежуточные состояния
3. **Случайность** - небольшие вариации для естественности
4. **Контекстуальность** - разные выражения для разных ситуаций

### Адаптация для Dart

1. **Прямое портирование логики**
   - Математические формулы движения глаз
   - Алгоритмы моргания

2. **Объектно-ориентированный подход**
   - Инкапсуляция в класс EyeAnimationController
   - Четкое разделение ответственности

3. **Асинхронная обработка**
   - Использование Timer для неблокирующей анимации
   - Отдельные потоки для сложных анимаций

## 🎨 Примеры использования

### Базовое подключение с анимацией ожидания

```dart
void main() async {
  final robot = CozmoRobot.instance;
  
  // Подключение
  final error = await robot.connect();
  if (error != null) {
    print('Ошибка подключения: $error');
    return;
  }
  
  // Анимация ожидания уже запущена автоматически
  print('Глаза робота анимированы');
  
  // Ожидание команд пользователя
  await Future.delayed(Duration(seconds: 30));
  
  // Отключение
  await robot.disconnect();
}
```

### Интерактивное моргание

```dart
void setupInteractiveBlinking() {
  final robot = CozmoRobot.instance;
  
  // Каждые 5 секунд моргаем
  robot.eyeController.startBlinkLoop(interval: Duration(seconds: 5));
  
  // Обработчик моргания по команде
  Timer.periodic(Duration(seconds: 10), (timer) {
    robot.eyeController.blink();
  });
}
```

### Комплексная сцена

```dart
void performComplexScene() async {
  final robot = CozmoRobot.instance;
  
  // 1. Просыпаемся
  robot.eyeController.wakeup();
  await Future.delayed(Duration(seconds: 2));
  
  // 2. Осматриваемся
  robot.eyeController.startWandering();
  await Future.delayed(Duration(seconds: 5));
  
  // 3. Останавливаемся на пользователе
  robot.eyeController.stopWandering();
  robot.face.setHappy();
  await Future.delayed(Duration(seconds: 3));
  
  // 4. Засыпаем
  robot.eyeController.sleep();
  await Future.delayed(Duration(seconds: 2));
}
```

## 🚀 Расширения и будущие улучшения

### Планируемые возможности

1. **Расширенные выражения**
   - Подмигивание одним глазом
   - "Косые" глаза
   - Изменение размера зрачков

2. **Адаптивное поведение**
   - Реакция на звуки
   - Случайные моргания
   - Контекстные выражения

3. **Синхронизация с движением**
   - Анимация при повороте головы
   - "Следящие" глаза
   - Выражения при движении

4. **Интерактивность**
   - Отслеживание объектов
   - Реакция на касания
   - Эмоциональный отклик

### Пример расширенной реализации

```dart
// Будущая версия с расширенными возможностями
class AdvancedEyeAnimationController extends EyeAnimationController {
  // Дополнительные параметры
  double _pupilX = 0.5;
  double _pupilY = 0.5;
  double _pupilSize = 0.1;
  
  // Расширенные выражения
  void wink({bool leftEye = true});
  void lookAt({double x = 0.5, double y = 0.5});
  void setExpression(EyeExpression expression);
}

enum EyeExpression {
  curious,
  bored,
  excited,
  confused,
  suspicious,
}
```

## 📝 Заключение

`EyeAnimationController` обеспечивает мощную систему для анимации глаз робота Cozmo, автоматически активируясь при подключении и предоставляя богатый набор выражений и анимаций.

Ключевые преимущества:
- **Автоматическая активация** при подключении
- **Богатый набор** анимаций
- **Асинхронная работа** без блокирования
- **Интеграция** с существующей архитектурой
- **Простое использование** через API

Компонент успешно адаптирует паттерны из pycozmo для Dart/Flutter экосистемы, сохраняя при этом гибкость и расширяемость.

---

**Версия:** 1.0  
**Дата:** 2026-01-10  
**Автор:** Cozmo Development Team