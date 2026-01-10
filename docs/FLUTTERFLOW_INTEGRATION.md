# Интеграция cozmo_dart_lib с FlutterFlow

## 📋 Обзор

Документация описывает способы интеграции библиотеки `cozmo_dart_lib` с FlutterFlow для создания приложений управления роботом Cozmo.

## 🔗 Структура интеграции

### Путь к библиотеке

В `pubspec.yaml` основного проекта:

```yaml
dependencies:
  cozmo_dart_lib:
    path: ./cozmo_dart_lib
```

### Структура кастомных действий

```
lib/custom_code/actions/
├── connect_a_i.dart           # Подключение к AI
├── connect_cozmo.dart         # Подключение к роботу
├── disconnect_a_i.dart        # Отключение от AI
├── disconnect_cozmo.dart     # Отключение от робота
├── play_sample.dart           # Воспроизведение тестового звука
├── play_sound.dart            # Воспроизведение звука
├── robot_drive_wheels.dart    # Управление колесами
├── robot_head_angle.dart      # Управление головой
├── robot_lift_height.dart     # Управление подъемником
├── robot_stop_all.dart       # Остановка всех движителей
├── robot_turn_left.dart       # Поворот влево
├── robot_turn_right.dart      # Поворот вправо
└── set_robot_volume.dart      # Установка громкости
```

## 🛠️ Создание кастомных действий

### 1. Базовый шаблон действия

```dart
// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future<ReturnType> actionName(ParameterType parameter) async {
  final robot = CozmoRobot.instance;
  
  if (!robot.isConnected) {
    throw Exception('Robot not connected');
  }
  
  // Ваш код здесь
  
  return result;
}
```

### 2. Пример: Подключение к роботу

```dart
// lib/custom_code/actions/connect_cozmo.dart
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future<String?> connectCozmo() async {
  final robot = CozmoRobot.instance;
  final error = await robot.connect();
  
  if (error == null) {
    robot.setVolume(FFAppState().speechVolume.round());
  }
  
  return error;
}
```

### 3. Пример: Управление головой

```dart
// lib/custom_code/actions/robot_head_angle.dart
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future robotHeadAngle(double angle) async {
  final robot = CozmoRobot.instance;
  await robot.head.setAngle(angle);
}
```

### 4. Пример: Воспроизведение звука

```dart
// lib/custom_code/actions/play_sound.dart
import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

Future playSound(String soundPath) async {
  final robot = CozmoRobot.instance;
  final volume = FFAppState().speechVolume.round();
  
  robot.setVolume(volume);
  await robot.playAudio(soundPath);
}
```

## 🎮 Использование в UI

### Добавление кнопок в интерфейс

В FlutterFlow дизайнере:

1. Добавьте виджет `Button`
2. В разделе "On Click" выберите "Backend API" → "Custom Action"
3. Выберите созданное действие
4. Настройте параметры при необходимости

### Пример кода для кнопки

```dart
FFButtonWidget(
  onPressed: () async {
    await actions.connectCozmo();
  },
  text: 'Подключить Cozmo',
  options: FFButtonOptions(
    height: 40.0,
    color: FlutterFlowTheme.of(context).primary,
    textStyle: FlutterFlowTheme.of(context).titleSmall.copyWith(
      color: Colors.white,
    ),
  ),
)
```

## 📊 Управление состоянием

### Добавление состояния в FFAppState

В файле `app_state.dart`:

```dart
class FFAppState extends ChangeNotifier {
  bool _isCozmoConnected = false;
  bool get isCozmoConnected => _isCozmoConnected;
  set isCozmoConnected(bool value) {
    _isCozmoConnected = value;
    notifyListeners();
  }
  
  double _speechVolume = 80.0;
  double get speechVolume => _speechVolume;
  set speechVolume(double value) {
    _speechVolume = value;
    notifyListeners();
  }
}
```

### Использование состояния в действии

```dart
Future connectCozmo() async {
  final robot = CozmoRobot.instance;
  final error = await robot.connect();
  
  if (error == null) {
    FFAppState().isCozmoConnected = true;
    robot.setVolume(FFAppState().speechVolume.round());
  }
  
  return error;
}
```

### Отображение состояния в UI

```dart
Consumer<FFAppState>(
  builder: (context, appState, child) {
    return Container(
      color: appState.isCozmoConnected ? Colors.green : Colors.red,
      child: Text(
        appState.isCozmoConnected ? 'Подключено' : 'Не подключено',
      ),
    );
  },
)
```

## 🔧 Расширенные сценарии

### 1. Управление громкостью

```dart
// lib/custom_code/actions/set_robot_volume.dart
Future setRobotVolume(int volume) async {
  final robot = CozmoRobot.instance;
  robot.setVolume(volume);
  
  // Сохранение в состояние
  FFAppState().speechVolume = volume.toDouble();
}
```

### 2. Комплексное движение

```dart
// lib/custom_code/actions/robot_complex_movement.dart
Future robotComplexMovement() async {
  final robot = CozmoRobot.instance;
  
  // Последовательность движений
  await robot.head.setAngle(0.5);  // Голова вверх
  await Future.delayed(Duration(milliseconds: 500));
  
  await robot.lift.setHeight(80.0);  // Подъемник вверх
  await Future.delayed(Duration(milliseconds: 500));
  
  await robot.drive.wheels(lWheelSpeed: 50, rWheelSpeed: 50, duration: 1000);
  
  // Возвращение в исходное положение
  await Future.delayed(Duration(seconds: 1));
  await robot.head.setAngle(0.0);
  await robot.lift.setHeight(50.0);
}
```

### 3. Воспроизведение анимации с эмоцией

```dart
// lib/custom_code/actions/robot_play_emotion_animation.dart
Future robotPlayEmotionAnimation(String emotion) async {
  final robot = CozmoRobot.instance;
  
  CozmoEmotion cozmoEmotion;
  switch (emotion.toLowerCase()) {
    case 'happy':
      cozmoEmotion = CozmoEmotion.happy;
      break;
    case 'sad':
      cozmoEmotion = CozmoEmotion.sad;
      break;
    case 'surprised':
      cozmoEmotion = CozmoEmotion.surprised;
      break;
    default:
      cozmoEmotion = CozmoEmotion.thinking;
  }
  
  await robot.playEmotion(cozmoEmotion);
}
```

## 🎨 Создание UI компонентов

### 1. Компонент управления головой

```dart
class RobotHeadControl extends StatelessWidget {
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
            Text('Управление головой'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FlutterFlowIconButton(
                  onPressed: () async {
                    await actions.robotHeadAngle(0.68); // Вверх
                  },
                  icon: Icon(Icons.arrow_upward),
                ),
                FlutterFlowIconButton(
                  onPressed: () async {
                    await actions.robotHeadAngle(0.0); // Прямо
                  },
                  icon: Icon(Icons.remove),
                ),
                FlutterFlowIconButton(
                  onPressed: () async {
                    await actions.robotHeadAngle(-0.436); // Вниз
                  },
                  icon: Icon(Icons.arrow_downward),
                ),
              ].divide(SizedBox(width: 16.0)),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 2. Компонент управления подъемником

```dart
class RobotLiftControl extends StatelessWidget {
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
            Text('Управление подъемником'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FlutterFlowIconButton(
                  onPressed: () async {
                    await actions.robotLiftHeight(92.0); // Вверх
                  },
                  icon: Icon(Icons.arrow_upward),
                ),
                FlutterFlowIconButton(
                  onPressed: () async {
                    await actions.robotLiftHeight(32.0); // Вниз
                  },
                  icon: Icon(Icons.arrow_downward),
                ),
              ].divide(SizedBox(width: 16.0)),
            ),
          ],
        ),
      ),
    );
  }
}
```

## 🔄 Цикл жизни приложения

### Инициализация при запуске

```dart
class _HomePageWidgetState extends State<HomePageWidget> {
  @override
  void initState() {
    super.initState();
    
    // Попытка подключения при запуске
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final error = await actions.connectCozmo();
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка подключения: $error')),
        );
      }
    });
  }
  
  @override
  void dispose() {
    // Отключение при закрытии
    actions.disconnectCozmo();
    super.dispose();
  }
}
```

### Обработка ошибок

```dart
Future<void> _handleCozmoAction(Future Function() action) async {
  try {
    await action();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка: $e')),
    );
    
    // Попытка переподключения
    final error = await actions.connectCozmo();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переподключиться: $error')),
      );
    }
  }
}
```

## 📱 Пример полного UI

```dart
class CozmoControlPage extends StatefulWidget {
  @override
  _CozmoControlPageState createState() => _CozmoControlPageState();
}

class _CozmoControlPageState extends State<CozmoControlPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Управление Cozmo'),
        actions: [
          Consumer<FFAppState>(
            builder: (context, appState, child) {
              return Icon(
                appState.isCozmoConnected 
                  ? Icons.bluetooth_connected 
                  : Icons.bluetooth_disabled,
                color: appState.isCozmoConnected 
                  ? Colors.green 
                  : Colors.red,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Статус подключения
              Consumer<FFAppState>(
                builder: (context, appState, child) {
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        appState.isCozmoConnected 
                          ? Icons.bluetooth_connected 
                          : Icons.bluetooth_disabled,
                      ),
                      title: Text(appState.isCozmoConnected 
                        ? 'Подключено к Cozmo' 
                        : 'Не подключено'),
                      trailing: TextButton(
                        onPressed: () async {
                          if (appState.isCozmoConnected) {
                            await actions.disconnectCozmo();
                          } else {
                            final error = await actions.connectCozmo();
                            if (error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Ошибка: $error')),
                              );
                            }
                          }
                        },
                        child: Text(appState.isCozmoConnected ? 'Отключить' : 'Подключить'),
                      ),
                    ),
                  );
                },
              ),
              
              // Управление головой
              RobotHeadControl(),
              
              // Управление подъемником
              RobotLiftControl(),
              
              // Управление движением
              RobotDriveControl(),
              
              // Управление громкостью
              VolumeControl(),
            ].divide(SizedBox(height: 16.0)),
          ),
        ),
      ),
    );
  }
}
```

## 🧪 Тестирование интеграции

### 1. Тестирование действий

```dart
// lib/custom_code/actions/test_cozmo_actions.dart
Future testCozmoActions() async {
  // Тест подключения
  final connectError = await actions.connectCozmo();
  assert(connectError == null, 'Не удалось подключиться: $connectError');
  
  // Тест управления головой
  await actions.robotHeadAngle(0.0);
  
  // Тест воспроизведения звука
  await actions.playSound('/path/to/test.wav');
  
  // Тест отключения
  await actions.disconnectCozmo();
  
  print('Все тесты пройдены успешно!');
}
```

### 2. Отладка действий

В FlutterFlow:

1. Откройте страницу с действием
2. Нажмите "Run" в правом верхнем углу
3. Проверьте консоль на наличие ошибок
4. Используйте инспектор для отладки UI

## 📚 Дополнительные ресурсы

- [Руководство разработчика](DEVELOPER_GUIDE.md)
- [Практические примеры](PRACTICAL_IMPLEMENTATION_GUIDE.md)
- [Документация API](COZMO_DART_README.md)
- [Примеры интеграции с FlutterFlow](https://flutterflow.com/docs)

---

**Версия:** 0.0.2  
**Последнее обновление:** 2026-01-10