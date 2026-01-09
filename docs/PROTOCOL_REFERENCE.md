# Cozmo Protocol Reference - Dart Implementation

## 📋 Содержание

1. [Обзор протокола](#обзор-протокола)
2. [Типы фреймов](#типы-фреймов)
3. [Типы пакетов](#типы-пакетов)
4. [Важные команды](#важные-команды)
5. [События робота](#события-робота)
6. [Структура фрейма](#структура-фрейма)
7. [Кодирование данных](#кодирование-данных)
8. [Примеры пакетов](#примеры-пакетов)

---

## Обзор протокола

Cozmo использует проприетарный бинарный протокол поверх UDP для коммуникации между клиентом и роботом.

### Основные характеристики:

- **Транспорт**: UDP
- **IP робота**: 172.31.1.1 (фиксированный)
- **Порт**: 5551
- **Версия прошивки**: 2381
- **Архитектура**: Би-directional (клиент ↔ робот)

### Ключевые файлы pycozmo:

```
pycozmo/pycozmo/
├── conn.py                    # UDP соединение, отправка/приём
├── frame.py                   # Кодирование/декодирование фреймов
├── protocol_encoder.py        # Классы пакетов (автосгенерирован)
├── protocol_declaration.py    # Декларация протокола
├── protocol_ast.py            # AST (Enum'ы FrameType, PacketType)
├── client.py                  # High-level API
├── audio.py                   # u-law кодирование аудио
└── robot.py                   # Константы робота
```

---

## Типы фреймов

Фрейм — это контейнер для пакетов. Все фреймы начинаются с `FRAME_ID`.

### FrameType Enum (protocol_ast.py:50)

```python
class FrameType(enum.Enum):
    RESET = 1         # Сброс соединения
    RESET_ACK = 2     # Подтверждение сброса
    FIN = 3           # Завершение соединения
    ENGINE_ACT = 4    # Активация двигателя (Connect/Disconnect)
    ENGINE = 7        # Команды от клиента к роботу
    ROBOT = 9         # События от робота к клиенту ⚠️ ВАЖНО!
    PING = 0x0b       # Ping/Keep-alive
```

### Обработка в Dart:

```dart
if (frameType == 0x07) {
  _handleEngineFrame(data, 14);  // Команды
} else if (frameType == 0x09) {
  _handleRobotFrame(data, 14);   // События ⚠️ БЫЛО ОТСУТСТВУЕТ!
} else if (frameType == 0x0b) {
  _handlePingFrame(data);        // Ping
}
```

**🐛 БАГ v1.1.0**: Отсутствовала обработка ROBOT (0x09), поэтому события отображались как "Неизвестный Frame Type".

---

## Типы пакетов

Пакеты вложены во фреймы и имеют собственный тип.

### PacketType Enum (protocol_ast.py:61)

```python
class PacketType(enum.Enum):
    UNKNOWN = -1
    CONNECT = 2       # Подключение
    DISCONNECT = 3    # Отключение
    COMMAND = 4       # Команда (от клиента)
    EVENT = 5         # Событие (от робота) ⚠️ ВАЖНО!
    KEYFRAME = 0x0a   # Ключевой кадр
    PING = 0x0b       # Ping пакет
```

### Внутренняя структура пакета:

```
[PacketType: 1B][PacketLength: 2B][PacketData...]
```

Для COMMAND и EVENT добавляется:
```
...[CommandID/EventID: 1B][Data...]
```

---

## Важные команды

Команды отправляются от клиента к роботу в ENGINE фреймах.

### ID команд (protocol_encoder.py):

| Command ID | Название          | Описание                          | Параметры |
|------------|-------------------|-----------------------------------|-----------|
| 0x25 (37)  | Enable            | Включить управление               | -         |
| 0x37 (55)  | SetHeadAngle      | Установить угол головы            | angle_rad, max_speed, accel, duration |
| 0x3a (58)  | MoveHead          | Двигать головой                   | speed_rad_per_sec |
| 0x45 (69)  | SetOrigin         | Установить начало координат       | pose_frame_id, pose_origin_id, x, y, z |
| 0x4b (75)  | SyncTime          | Синхронизировать время            | timestamp |
| 0x64 (100) | SetRobotVolume    | Установить громкость              | volume (0-65535) |
| 0x8e (142) | OutputAudio       | Воспроизвести аудио               | samples[744] (u-law) |

### SetHeadAngle (0x37) - Пример:

**Структура** (protocol_encoder.py:1586):

```python
class SetHeadAngle(Packet):
    __slots__ = (
        "_angle_rad",           # float (4 bytes)
        "_max_speed_rad_per_sec", # float (4 bytes)
        "_accel_rad_per_sec2",  # float (4 bytes)
        "_duration_sec",        # float (4 bytes)
        "_action_id",           # uint8 (1 byte)
    )
```

**Dart реализация**:

```dart
final packet = _createCommandPacket(0x37, [
  ..._float32(angle),        // angle_rad
  ..._float32(speed),        // max_speed_rad_per_sec
  ..._float32(acceleration), // accel_rad_per_sec2
  ..._float32(0.0),          // duration_sec
  0x00,                      // action_id
]);
```

**Константы робота** (robot.py:34-36):

```python
MIN_HEAD_ANGLE = -25°  # = -0.436332 рад
MAX_HEAD_ANGLE = 44.5° # = 0.776672 рад
```

**Dart ограничения** (cozmo_class.dart:248-250):

```dart
const double minAngle = 0.0;   // Упрощено
const double maxAngle = 0.68;  // ~44.5°
```

### OutputAudio (0x8e) - Пример:

**Структура** (protocol_encoder.py:3313):

```python
class OutputAudio(Packet):
    __slots__ = (
        "_samples",  # uint8[744] - u-law encoded
    )
```

**Аудио кодирование** (audio.py:58-65):

```python
def bytes_to_cozmo(byte_string: bytes, rate_correction: int, channels: int) -> bytearray:
    out = bytearray(744)
    n = channels * rate_correction
    bs = struct.unpack('{}h'.format(int(len(byte_string) / 2)), byte_string)[0::n]
    for i, s in enumerate(bs):
        out[i] = u_law_encoding(s)
    return out
```

**Требования**:
- Формат: WAV, 16-bit PCM
- Частота: 22050 Hz или 48000 Hz
- Каналы: mono
- Сэмплов на пакет: 744
- Длительность пакета: 744 / 22050 ≈ 33.7 мс

---

## События робота

События отправляются от робота к клиенту в ROBOT фреймах.

### Вероятные ID событий (требуется уточнение):

| Event ID | Название            | Описание                          |
|----------|---------------------|-----------------------------------|
| 0x01     | RobotState          | Состояние робота (pose, battery)  |
| 0x02     | FaceDetection       | Обнаружено лицо                   |
| 0x03     | ObjectDetected      | Обнаружен объект (кубик)          |
| 0x04     | BatteryStateChanged | Изменилось состояние батареи      |
| 0x05     | RobotFound          | Робот обнаружен/инициализирован   |

### RobotState (0x01) - Структура:

**В pycozmo** (client.py:278-298):

```python
def _on_robot_state(self, cli, pkt: protocol_encoder.RobotState):
    self.pose_frame_id = pkt.pose_frame_id
    self.pose = util.Pose(pkt.pose_x, pkt.pose_y, pkt.pose_z,
                          angle_z=util.Angle(radians=pkt.pose_angle_rad),
                          origin_id=pkt.pose_origin_id)
    self.pose_pitch = util.Angle(radians=pkt.pose_pitch_rad)
    self.head_angle = util.Angle(radians=pkt.head_angle_rad)
    self.left_wheel_speed = util.Speed(mmps=pkt.lwheel_speed_mmps)
    self.right_wheel_speed = util.Speed(mmps=pkt.rwheel_speed_mmps)
    self.lift_position = robot.LiftPosition(height=util.Distance(mm=pkt.lift_height_mm))
    self.battery_voltage = pkt.battery_voltage
    self.accel = util.Vector3(pkt.accel_x, pkt.accel_y, pkt.accel_z)
    self.gyro = util.Vector3(pkt.gyro_x, pkt.gyro_y, pkt.gyro_z)
    self.robot_status = pkt.status
```

**Dart обработка** (cozmo_class.dart:464-484):

```dart
case 0x01: // RobotState event
  print('  📊 RobotState обновлён');
  // TODO: Парсить данные состояния
  break;
```

---

## Структура фрейма

### Формат фрейма (frame.py:55-82):

```
[FRAME_ID: 7B][FrameType: 1B][FirstSeq: 2B][Seq: 2B][Ack: 2B][Packets...]
```

### Разбор полей:

```dart
// Frame ID (magic number)
const List<int> FRAME_ID = [0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01]; // "COZ\x03RE\x01"

// Frame Type
final frameType = data[7];  // 1, 2, 3, 4, 7, 9, 11

// Sequence numbers (упрощено)
final firstSeq = _byteDataGetUint16(data, 8);  // + 1 = encoded
final seq = _byteDataGetUint16(data, 10);      // + 1 = encoded
final ack = _byteDataGetUint16(data, 12);      // + 1 = encoded

// Packets (начиная с offset 14)
```

### Пример ENGINE фрейма:

```
43 4F 5A 03 52 45 01  |  FRAME_ID
07                    |  FrameType: ENGINE
01 00                |  FirstSeq: 0 (encoded as 1)
01 00                |  Seq: 0 (encoded as 1)
01 00                |  Ack: 0 (encoded as 1)
04                   |  PacketType: COMMAND
13 00               |  PacketLength: 19 bytes
25                   |  CommandID: Enable (0x25)
00 00 00 00         |  Padding/Reserved
...                  |  (если есть данные)
```

### Кодирование Sequence Numbers (frame.py:57-60):

```python
writer.write((self.first_seq + 1) % 0x10000, "H")
writer.write((self.seq + 1) % 0x10000, "H")
writer.write((self.ack + 1) % 0x10000, "H")
```

**Важно**: Sequence numbers кодируются с +1, поэтому:
- Encoded: 1 → Decoded: 0
- Encoded: 2 → Decoded: 1
- и т.д.

---

## Кодирование данных

### Типы данных:

| Тип      | Размер | Dart код                        |
|----------|--------|---------------------------------|
| uint8    | 1 B    | `value & 0xFF`                  |
| uint16   | 2 B    | `[value & 0xFF, (value >> 8) & 0xFF]` (little-endian) |
| uint32   | 4 B    | `[value & 0xFF, (value >> 8) & 0xFF, ...]` (little-endian) |
| float32  | 4 B    | `ByteData(4)..setFloat32(0, value, Endian.little)` |
| float64  | 8 B    | `ByteData(8)..setFloat64(0, value, Endian.little)` |

### u-law кодирование (audio.py:68-85):

**Формула**:

```python
def u_law_encoding(sample: int) -> int:
    MULAW_MAX = 0x7FFF
    MULAW_BIAS = 132

    mask = 0x4000
    position = 14
    sign = 0

    if sample < 0:
        sample = -sample
        sign = 0x80

    sample += MULAW_BIAS
    if sample > MULAW_MAX:
        sample = MULAW_MAX

    while (sample & mask) != mask and position >= 7:
        mask >>= 1
        position -= 1

    lsb = (sample >> (position - 4)) & 0x0f
    return -(~(sign | ((position - 7) << 4) | lsb))
```

**Dart реализация** (cozmo_class.dart:796-821):

```dart
int _uLawEncode(int sample) {
  const int MULAW_MAX = 0x7FFF;
  const int MULAW_BIAS = 132;

  int mask = 0x4000;
  int position = 14;
  int sign = 0;

  if (sample < 0) {
    sample = -sample;
    sign = 0x80;
  }

  sample += MULAW_BIAS;
  if (sample > MULAW_MAX) {
    sample = MULAW_MAX;
  }

  while ((sample & mask) != mask && position >= 7) {
    mask >>= 1;
    position--;
  }

  int lsb = (sample >> (position - 4)) & 0x0f;
  return -(~(sign | ((position - 7) << 4) | lsb));
}
```

---

## Примеры пакетов

### 1. Подключение (RESET frame):

```dart
// Отправка
final writer = _ByteWriter();
writer.writeBytes(FRAME_ID);      // 7 bytes
writer.writeUint8(0x01);           // FrameType: RESET
writer.writeUint16(1);             // first_seq + 1
writer.writeUint16(1);             // seq + 1
writer.writeUint16(1);             // ack + 1
// Нет данных
final frame = writer.toUint8List();
_socket.send(frame, _cozmoAddress, COZMO_PORT);
```

**Результат**: `43 4F 5A 03 52 45 01 01 01 00 01 00 01 00` (14 bytes)

### 2. Enable команда (0x25):

```dart
final packet = _createCommandPacket(0x25, []);
await _sendPacket(packet);
```

**ENGINE frame**:
```
43 4F 5A 03 52 45 01 | FRAME_ID
07                    | FrameType: ENGINE
01 00 01 00 01 00    | Seq numbers
04                   | PacketType: COMMAND
02 00               | PacketLength: 2
25                   | CommandID: Enable
```

### 3. SetHeadAngle (0x37):

```dart
final angle = 0.5; // радианы
final speed = 10.0;
final accel = 10.0;

final packet = _createCommandPacket(0x37, [
  ..._float32(angle),   // 00 00 00 3F (0.5)
  ..._float32(speed),   // 00 00 20 41 (10.0)
  ..._float32(accel),   // 00 00 20 41 (10.0)
  ..._float32(0.0),     // 00 00 00 00 (duration)
  0x00,                 // action_id
]);
```

**ENGINE frame**:
```
43 4F 5A 03 52 45 01 | FRAME_ID
07                    | FrameType: ENGINE
...                  | Seq numbers
04                   | PacketType: COMMAND
11 00               | PacketLength: 17
37                   | CommandID: SetHeadAngle
00 00 00 3F         | angle_rad: 0.5
00 00 20 41         | max_speed: 10.0
00 00 20 41         | accel: 10.0
00 00 00 00         | duration_sec: 0.0
00                   | action_id: 0
```

### 4. OutputAudio (0x8e):

```dart
final ulawSamples = _convertToULaw(pcm16Data);
final packet = _createCommandPacket(0x8e, ulawSamples);
await _sendPacket(packet);
```

**ENGINE frame**:
```
43 4F 5A 03 52 45 01 | FRAME_ID
07                    | FrameType: ENGINE
...                  | Seq numbers
04                   | PacketType: COMMAND
E9 02               | PacketLength: 741
8E                   | CommandID: OutputAudio
[744 bytes]          | u-law samples
```

### 5. Ping пакет:

```dart
final writer = _ByteWriter();
writer.writeFloat64(0.0);  // time_sent_ms
writer.writeUint32(0);     // counter
writer.writeUint32(0);     // last
writer.writeUint8(0);      // unknown

final data = writer.toUint8List();

final frameWriter = _ByteWriter();
frameWriter.writeBytes(FRAME_ID);
frameWriter.writeUint8(0x0b);  // FrameType: PING
frameWriter.writeUint16(1);    // first_seq + 1
frameWriter.writeUint16(1);    // seq + 1
frameWriter.writeUint16(1);    // ack + 1
frameWriter.writeBytes(data);  // 17 bytes

_socket.send(frameWriter.toUint8List(), _cozmoAddress, COZMO_PORT);
```

---

## Дополнительные команды

### MoveHead (0x3a) - Движение головы:

**pycozmo** (client.py:370):
```python
def move_head(self, speed: float) -> None:
    pkt = protocol_encoder.MoveHead(speed_rad_per_sec=speed)
    self.conn.send(pkt)
```

**protocol_encoder.py:1417**:
```python
class MoveHead(Packet):
    __slots__ = ("_speed_rad_per_sec",)  # float
```

**Dart реализация** (TODO):
```dart
Future<void> moveHead(double speed) async {
  if (!_isConnected) {
    throw CozmoException('Не подключено к Cozmo');
  }

  final packet = _createCommandPacket(0x3a, [
    ..._float32(speed),  // speed_rad_per_sec
  ]);

  await _sendPacket(packet);
  print('🤖 Голова движется со скоростью: $speed рад/сек');
}
```

### DriveWheels - Управление колесами:

**pycozmo** (client.py:384):
```python
def drive_wheels(self, lwheel_speed: float, rwheel_speed: float,
                 lwheel_acc: Optional[float] = 0.0, rwheel_acc: Optional[float] = 0.0,
                 duration: Optional[float] = None) -> None:
    pkt = protocol_encoder.DriveWheels(lwheel_speed_mmps=lwheel_speed,
                                       rwheel_speed_mmps=rwheel_speed,
                                       lwheel_accel_mmps2=lwheel_acc,
                                       rwheel_accel_mmps2=rwheel_acc)
    self.conn.send(pkt)
    if duration is not None:
        time.sleep(duration)
        self.stop_all_motors()
```

**Константы** (robot.py:54-57):
```python
MAX_WHEEL_SPEED = 200.0 mmps  # миллиметров в секунду
TRACK_WIDTH = 45.0 mm
```

### SetLiftHeight - Управление подъемником:

**pycozmo** (client.py:374):
```python
def set_lift_height(self, height: float, accel: float = 10.0, max_speed: float = 10.0,
                    duration: float = 0.0):
    pkt = protocol_encoder.SetLiftHeight(height_mm=height, accel_rad_per_sec2=accel,
                                         max_speed_rad_per_sec=max_speed, duration_sec=duration)
    self.conn.send(pkt)
```

**Константы** (robot.py:38-41):
```python
MIN_LIFT_HEIGHT = 32.0 mm
MAX_LIFT_HEIGHT = 92.0 mm
LIFT_ARM_LENGTH = 66.0 mm
LIFT_PIVOT_HEIGHT = 45.0 mm
```

---

## Полезные ссылки

### pycozmo файлы:

- **protocol_ast.py** - Определения FrameType, PacketType enum
- **protocol_encoder.py** - Все классы пакетов (SetHeadAngle, OutputAudio, etc.)
- **frame.py** - Кодирование/декодирование фреймов
- **conn.py** - UDP соединение, SendThread, ReceiveThread
- **client.py** - High-level API (set_head_angle, play_audio, etc.)
- **audio.py** - u-law кодирование
- **robot.py** - Константы (MIN_HEAD_ANGLE, MAX_WHEEL_SPEED, etc.)

### Документация:

- [COZMO_DART_README.md](COZMO_DART_README.md) - Руководство пользователя
- [RECEIVE_LOOP_IMPLEMENTATION.md](RECEIVE_LOOP_IMPLEMENTATION.md) - Реализация receive loop
- [CHANGELOG.md](CHANGELOG.md) - История версий

### External:

- [pycozmo repository](https://github.com/zayfod/pycozmo)
- [Cozmo Python SDK](https://github.com/anki/cozmo-python-sdk)
- [u-law algorithm](https://en.wikipedia.org/wiki/%CE%9C-law_algorithm)

---

**Дата создания**: 2026-01-05
**Версия протокола**: 2381
**Версия Dart клиента**: 1.2.0 (с ROBOT frame support)
