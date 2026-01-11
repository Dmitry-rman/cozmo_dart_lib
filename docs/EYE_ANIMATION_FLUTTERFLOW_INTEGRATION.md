# Интеграция EyeAnimationController с FlutterFlow

## 📋 Обзор

Документация описывает способы интеграции `EyeAnimationController` с FlutterFlow для создания кастомных действий, которые позволяют управлять анимацией глаз робота Cozmo через визуальный интерфейс.

## 🎯 Предварительные требования

1. **Библиотека cozmo_dart_lib** должна быть установлена в проект
2. **EyeAnimationController** должен быть добавлен в `cozmo_robot.dart`
3. **Кастомные действия** должны быть созданы в папке `lib/custom_code/actions/`

## 🔧 Настройка проекта

### 1. Обновление библиотеки

Добавьте EyeAnimationController в основной экспорт библиотеки:

```dart
// В cozmo_dart_lib/lib/cozmo_dart_lib.dart
library cozmo_dart_lib;

export 'src/cozmo_robot.dart';
export 'src/cozmo_eye_animation_controller.dart'; // 🆕 Добавлен
// ... другие экспорты
```

### 2. Интеграция в CozmoRobot

Добавьте EyeAnimationController в класс `CozmoRobot`:

```dart
// В cozmo_dart_lib/lib/src/cozmo_robot.dart
class CozmoRobot {
  // ... существующие поля
  
  late final EyeAnimationController eyeController;  // 🆕 Добавлен
  
  CozmoRobot._internal() {
    // Существующая инициализация
    animController = CozmoAnimController(_client);
    
    // 🆕 Добавление EyeAnimationController
    face = CozmoFace();
    eyeController = EyeAnimationController(_client, face, animController); // 🆕 Инициализация
  }
  
  Future<String?> connect() async {
    // ... существующие команды
    
    // 🆕 Автоматическая активация EyeAnimationController
    eyeController.activate();
    
    return res;
  }
  
  void disconnect() {
    // 🆕 Деактивация EyeAnimationController
    eyeController.deactivate();
    
    animController.stop();
    _client.disconnect();
  }
}
```

## 🎮 Создание кастомных действий

### 1. Моргание глаз

Создайте файл `lib/custom_code/actions/robot_eye_blink.dart`:

```dart
// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions

// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future robotEyeBlink() async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  // 🆕 Используем eye controller
  robot.eyeController.blink();
}
```

### 2. Циклическое моргание

Создайте файл `lib/custom_code/actions/robot_eye_blink_loop.dart`:

```dart
// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions

// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future robotEyeBlinkLoop({bool enable = true}) async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  // 🆕 Используем eye controller
  if (enable) {
    robot.eyeController.startBlinkLoop();
  } else {
    robot.eyeController.stopBlinkLoop();
  }
}
```

### 3. Эмоциональные выражения

Создайте файл `lib/custom_code/actions/robot_eye_emotion.dart`:

```dart
// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions

// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future robotEyeEmotion(String emotion) async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  // 🆕 Используем eye controller
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
      break;
  }
}
```

## 🎨 Добавление в FlutterFlow UI

### 1. Кнопки для управления глазами

```dart
// В вашем виджете
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
  text: 'Счастливые глаза',
),
```

### 2. Переключатели для анимаций

```dart
// В вашем виджете
Row(
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
)
```

### 3. Выпадающий список для выбора эмоций

```dart
// В вашем виджете
DropdownButton<String>(
  options: ['happy', 'sad', 'surprised', 'thinking'],
  onChanged: (value) async {
    await actions.robotEyeEmotion(value);
  },
  hint: 'Выберите эмоцию',
  icon: Icon(Icons.face),
)
```

## 🔄 Состояние приложения

Добавьте в `app_state.dart`:

```dart
class FFAppState extends ChangeNotifier {
  // ... существующие поля
  
  // 🆕 Состояния EyeAnimationController
  bool _eyeBlinkLoop = false;
  
  bool get eyeBlinkLoop => _eyeBlinkLoop;
  set eyeBlinkLoop(bool value) {
    _eyeBlinkLoop = value;
    notifyListeners();
  }
}
```

## 📱 Параметры анимаций

### 1. Настройка интервалов

Добавьте в UI слайдеры для настройки параметров анимации:

```dart
// В вашем виджете
Slider(
  value: FFAppState().blinkInterval.inSeconds.toDouble(),
  min: 1.0,
  max: 10.0,
  divisions: 10,
  label: 'Интервал моргания (сек)',
  onChanged: (value) async {
    await robot.eyeController.setBlinkInterval(Duration(seconds: value.round()));
  },
),
```

### 2. Настройка амплитуды

```dart
// В вашем виджете
Slider(
  value: FFAppState().wanderAmplitude,
  min: 0.01,
  max: 0.2,
  divisions: 20,
  label: 'Амплитуда движения',
  onChanged: (value) async {
    await robot.eyeController.setWanderAmplitude(value);
  },
),
```

## 📊 Мониторинг состояния

### 1. Индикатор активности

```dart
// В вашем виджете
Consumer<FFAppState>(
  builder: (context, appState, child) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: appState.eyeController.isActive ? Colors.green : Colors.red,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.visibility,
          color: Colors.white,
          size: 12,
        ),
      ),
    );
  },
),
```

### 2. Текущая анимация

```dart
// В вашем виджете
Consumer<FFAppState>(
  builder: (context, appState, child) {
    return Text(
      'Текущая анимация: ${appState.currentAnimation}',
    );
  },
),
```

## 🧪 Полный пример виджета

```dart
class EyeControlWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<FFAppState>(
      builder: (context, appState, child) {
        return Container(
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).alternate,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Заголовок
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Управление глазами',
                      style: FlutterFlowTheme.of(context).titleLarge,
                    ),
                    Consumer<FFAppState>(
                      builder: (context, appState, child) {
                        return Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: appState.eyeController.isActive ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.visibility,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                ),
                
                SizedBox(height: 16.0),
                
                // Кнопки действий
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
                  ],
                ),
                
                SizedBox(height: 16.0),
                
                // Переключатель циклического моргания
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Циклическое моргание:'),
                    Switch(
                      value: appState.eyeBlinkLoop,
                      onChanged: (value) async {
                        appState.eyeBlinkLoop = value;
                        await actions.robotEyeBlinkLoop(enable: value);
                      },
                    ),
                  ],
                ),
                
                SizedBox(height: 16.0),
                
                // Выпадающий список для эмоций
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Эмоция:'),
                    DropdownButton<String>(
                      options: ['happy', 'sad', 'surprised', 'thinking'],
                      hint: 'Выберите эмоцию',
                      icon: Icon(Icons.face),
                      onChanged: (value) async {
                        await actions.robotEyeEmotion(value);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

## 🎨 Использование в FlutterFlow

### 1. Добавление на страницу

1. Откройте FlutterFlow и перейдите на вашу страницу
2. Добавьте компонент "Custom Action" из панели компонентов
3. Выберите "Backend API" → "Custom Action"
4. Назовите действие, например, `robotEyeBlink`
5. Добавьте необходимые параметры

### 2. Тестирование

1. Откройте страницу в режиме предпросмотра
2. Проверьте, что действия работают корректно
3. Убедитесь, что у робота моргают глаза

## 📚 Рекомендации

### 1. Начните с базовых анимаций

- Моргание: самое простое и заметное действие
- Эмоции: выберите 2-3 основные для начала
- Циклическое моргание: используйте для долгих сессий

### 2. Постепенно добавляйте complexity

1. Комбинированные анимации (моргание + эмоция)
2. Параметризированные анимации (интервал, амплитуда)
3. Контекстуальные анимации (реакция на события)

### 3. Собирайте обратную связь

- Записывайте, какие анимации нравятся пользователям
- Проводите A/B тестирование разных вариантов
- Собирайте статистику использования

---

**Версия документации:** 1.0  
**Дата:** 2026-01-10  
**Автор:** Cozmo Development Team