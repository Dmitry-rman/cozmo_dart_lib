# Cozmo Protocol - Quick Reference

## 🎯 Frame Types (Типы фреймов)

| Value | Name        | Direction         | Description                |
|-------|-------------|-------------------|----------------------------|
| 0x01  | RESET       | Client → Robot    | Сброс соединения           |
| 0x02  | RESET_ACK   | Robot → Client    | Подтверждение сброса       |
| 0x03  | FIN         | Either → Either   | Завершение соединения      |
| 0x04  | ENGINE_ACT  | Client → Robot    | Активация (Connect/Disconnect) |
| 0x07  | ENGINE      | Client → Robot    | **Команды**                |
| 0x09  | ROBOT       | **Robot → Client**| **События** ⚠️             |
| 0x0b  | PING        | Bi-directional    | Keep-alive                 |

---

## 📦 Packet Types (Типы пакетов)

| Value | Name     | Contains         | Used In Frame Types |
|-------|----------|------------------|---------------------|
| 0x02  | CONNECT  | Connect data     | ENGINE_ACT          |
| 0x03  | DISCONNECT | Disconnect data| ENGINE_ACT          |
| 0x04  | COMMAND  | **Command ID + Data** | ENGINE, ENGINE_ACT |
| 0x05  | EVENT    | **Event ID + Data** | ROBOT ⚠️          |
| 0x0a  | KEYFRAME | Keyframe data    | ENGINE, ROBOT       |
| 0x0b  | PING     | Ping data (17B)   | PING                |

---

## 🤖 Important Commands (0x04)

### Robot Control

| Command ID | Hex   | Name           | Parameters                                    | Status  |
|------------|-------|----------------|-----------------------------------------------|---------|
| 37         | 0x25  | **Enable**     | -                                             | ✅      |
| 55         | 0x37  | **SetHeadAngle** | angle_rad (float32)                          | ✅      |
|            |       |                | max_speed_rad_per_sec (float32)              |         |
|            |       |                | accel_rad_per_sec2 (float32)                 |         |
|            |       |                | duration_sec (float32)                       |         |
|            |       |                | action_id (uint8)                            |         |
| 58         | 0x3a  | MoveHead       | speed_rad_per_sec (float32)                  | TODO    |
| 69         | 0x45  | **SetOrigin**  | pose_frame_id (uint32)                        | ✅      |
|            |       |                | pose_origin_id (uint32)                       |         |
|            |       |                | pose_x, pose_y, pose_z (float32)              |         |
|            |       |                | unknown (uint32)                              |         |
| 75         | 0x4b  | **SyncTime**   | timestamp (uint32)                            | ✅      |
|            |       |                | unknown (uint32)                              |         |
| 100        | 0x64  | **SetVolume**  | volume (uint16, 0-65535)                      | ✅      |
| 142        | 0x8e  | **OutputAudio** | samples[744] (uint8, u-law)                   | ✅      |

### Movement Control

| Command ID | Hex   | Name           | Parameters                                    | Status  |
|------------|-------|----------------|-----------------------------------------------|---------|
| ?          | ?     | DriveWheels    | lwheel_speed_mmps (float32)                   | TODO    |
|            |       |                | rwheel_speed_mmps (float32)                   |         |
|            |       |                | lwheel_accel_mmps2 (float32)                  |         |
|            |       |                | rwheel_accel_mmps2 (float32)                  |         |
| ?          | ?     | SetLiftHeight  | height_mm (float32)                           | TODO    |
|            |       |                | accel_rad_per_sec2 (float32)                  |         |
|            |       |                | max_speed_rad_per_sec (float32)               |         |
|            |       |                | duration_sec (float32)                        |         |
| ?          | ?     | MoveLift        | speed_rad_per_sec (float32)                   | TODO    |

### Light Control

| Command ID | Hex   | Name           | Parameters                                    | Status  |
|------------|-------|----------------|-----------------------------------------------|---------|
| ?          | ?     | SetHeadLight   | enable (uint8)                                | TODO    |

---

## 🎉 Robot Events (0x05)

| Event ID | Hex   | Name                | Description                          | Status  |
|----------|-------|---------------------|--------------------------------------|---------|
| 1        | 0x01  | **RobotState**      | Pose, battery, head_angle, etc.      | ⚠️ Parse |
| 2        | 0x02  | FaceDetection       | Face detected                        | TODO    |
| 3        | 0x03  | ObjectDetected      | Object (cube) detected               | TODO    |
| 4        | 0x04  | BatteryStateChanged | Battery level changed                | TODO    |
| 5        | 0x05  | RobotFound          | Robot initialized                    | TODO    |
| ?        | ?     | ImageChunk          | Camera frame chunk                   | TODO    |
| ?        | ?     | RobotStateChanged   | Robot status flags changed           | TODO    |

---

## 📊 RobotState Event (0x01) Structure

**Based on pycozmo/client.py:278-298**

### Offset Map (assuming little-endian):

```
Offset | Size | Type    | Field
-------|------|---------|------------------
0      | 4    | uint32  | pose_frame_id
4      | 4    | float32 | pose_x
8      | 4    | float32 | pose_y
12     | 4    | float32 | pose_z
16     | 4    | float32 | pose_angle_rad
20     | 4    | uint32  | pose_origin_id
24     | 4    | float32 | pose_pitch_rad
28     | 4    | float32 | head_angle_rad
32     | 4    | float32 | lwheel_speed_mmps
36     | 4    | float32 | rwheel_speed_mmps
40     | 4    | float32 | lift_height_mm
44     | 1    | float32 | battery_voltage
48     | 4    | float32 | accel_x
52     | 4    | float32 | accel_y
56     | 4    | float32 | accel_z
60     | 4    | float32 | gyro_x
64     | 4    | float32 | gyro_y
68     | 4    | float32 | gyro_z
72     | 4    | uint32  | status (flags)
```

### Status Flags (robot.py:63-81):

```
0x1     IS_MOVING
0x2     IS_CARRYING_BLOCK
0x4     IS_PICKING_OR_PLACING
0x8     IS_PICKED_UP
0x10    IS_BODY_ACC_MODE
0x20    IS_FALLING
0x40    IS_ANIMATING
0x80    IS_PATHING
0x100   LIFT_IN_POS
0x200   HEAD_IN_POS
0x400   IS_ANIM_BUFFER_FULL
0x800   IS_ANIMATING_IDLE
0x1000  IS_ON_CHARGER
0x2000  IS_CHARGING
0x4000  CLIFF_DETECTED
0x8000  ARE_WHEELS_MOVING
0x10000 IS_CHARGER_OOS
```

---

## 🔢 Constants (robot.py)

### Head Movement

```dart
MIN_HEAD_ANGLE = -25°  // = -0.436332 rad
MAX_HEAD_ANGLE = 44.5° // = 0.776672 rad
```

### Lift Movement

```dart
MIN_LIFT_HEIGHT = 32.0 mm
MAX_LIFT_HEIGHT = 92.0 mm
LIFT_ARM_LENGTH = 66.0 mm
LIFT_PIVOT_HEIGHT = 45.0 mm
```

### Wheels

```dart
MAX_WHEEL_SPEED = 200.0 mmps  // millimeters per second
TRACK_WIDTH = 45.0 mm
```

### Audio

```dart
AUDIO_PACKET_SAMPLES = 744
COZMO_SAMPLE_RATE = 22050  // Hz
PACKET_DURATION = 744 / 22050 ≈ 33.7 ms
```

---

## 📝 Frame Structure

### Standard Frame (ENGINE, ROBOT)

```
[FRAME_ID: 7B][FrameType: 1B][FirstSeq: 2B][Seq: 2B][Ack: 2B][Packets...]
```

### Packet Structure (COMMAND, EVENT)

```
[PacketType: 1B][PacketLength: 2B][PacketData...]
```

For COMMAND (0x04) and EVENT (0x05):
```
...[CommandID/EventID: 1B][Data...]
```

### Sequence Number Encoding

**Encoded = Decoded + 1**

Examples:
- Encoded: 1 → Decoded: 0
- Encoded: 2 → Decoded: 1
- Encoded: 65535 → Decoded: 65534 (OOB_SEQ = 65535)

---

## 🎵 Audio Encoding

### WAV Requirements

- **Format**: WAV (RIFF)
- **Codec**: 16-bit PCM
- **Sample Rate**: 22050 Hz or 48000 Hz
- **Channels**: Mono (1)
- **Bit Depth**: 16-bit

### u-law Encoding (audio.py:68-85)

```python
def u_law_encoding(sample: int) -> int:
    MULAW_MAX = 0x7FFF
    MULAW_BIAS = 132

    sign = 0x80 if sample < 0 else 0
    sample = abs(sample) + MULAW_BIAS
    sample = min(sample, MULAW_MAX)

    # Find position
    position = 14
    mask = 0x4000
    while (sample & mask) != mask and position >= 7:
        mask >>= 1
        position -= 1

    lsb = (sample >> (position - 4)) & 0x0f
    return -(~(sign | ((position - 7) << 4) | lsb))
```

### OutputAudio Packet

```
[PacketType: 0x04][Length: 2B][CommandID: 0x8E][Samples: 744B]
```

Total: 4 + 744 = 748 bytes per packet

---

## 🔧 Data Types

| Type    | Size | Endianness    | Dart Encoding                      |
|---------|------|---------------|------------------------------------|
| uint8   | 1 B  | -             | `value & 0xFF`                     |
| uint16  | 2 B  | Little        | `[lo, hi]`                         |
| uint32  | 4 B  | Little        | `[b0, b1, b2, b3]`                 |
| float32 | 4 B  | Little        | `ByteData(4)..setFloat32(0, v)`    |
| float64 | 8 B  | Little        | `ByteData(8)..setFloat64(0, v)`    |

### Helper Functions (cozmo_class.dart)

```dart
List<int> _uint16(int value) {
  return [value & 0xFF, (value >> 8) & 0xFF];
}

List<int> _uint32(int value) {
  return [
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}

List<int> _float32(double value) {
  final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
  return [bytes.getUint8(0), bytes.getUint8(1), bytes.getUint8(2), bytes.getUint8(3)];
}
```

---

## 🔍 Packet Examples (Hex)

### Enable Command (0x25)

```
43 4F 5A 03 52 45 01 | FRAME_ID
07                   | FrameType: ENGINE
01 00 01 00 01 00   | Seq numbers
04                   | PacketType: COMMAND
02 00               | PacketLength: 2
25                   | CommandID: Enable
```

### SetHeadAngle Command (0x37)

```
43 4F 5A 03 52 45 01 | FRAME_ID
07                   | FrameType: ENGINE
01 00 01 00 01 00   | Seq numbers
04                   | PacketType: COMMAND
11 00               | PacketLength: 17
37                   | CommandID: SetHeadAngle
00 00 00 3F         | angle_rad: 0.5
00 00 20 41         | max_speed: 10.0
00 00 20 41         | accel: 10.0
00 00 00 00         | duration_sec: 0.0
00                   | action_id: 0
```

### SetVolume Command (0x64)

```
43 4F 5A 03 52 45 01 | FRAME_ID
07                   | FrameType: ENGINE
...                  | Seq numbers
04                   | PacketType: COMMAND
04 00               | PacketLength: 4
64                   | CommandID: SetVolume
FF 00               | volume: 255 (≈100%)
```

### Ping Packet

```
43 4F 5A 03 52 45 01 | FRAME_ID
0B                   | FrameType: PING
01 00 01 00 01 00   | Seq numbers
00 00 00 00 00 00 00 00 | time_sent_ms: 0.0
00 00 00 00         | counter: 0
00 00 00 00         | last: 0
00                   | unknown: 0
```

---

## 📚 pycozmo File Reference

| File                  | Description                                  |
|-----------------------|----------------------------------------------|
| protocol_ast.py       | FrameType, PacketType enums (строки 50-69)  |
| protocol_encoder.py   | All packet classes (SetHeadAngle: 1586, etc.) |
| frame.py              | Frame encoding/decoding (строки 55-82)       |
| conn.py               | UDP connection, SendThread, ReceiveThread    |
| client.py             | High-level API (set_head_angle: 364, etc.)   |
| audio.py              | u-law encoding (строки 68-85)                |
| robot.py              | Constants (MIN_HEAD_ANGLE: 34, etc.)         |

---

## 🎯 Quick Commands

### Basic Usage

```dart
// Подключение
final error = await connect();
if (error != null) return;

// Управление головой
await setHeadAngle(0.5);              // Среднее положение
await setHeadAngle(0.68, speed: 5.0);  // Медленно вверх
await setHeadAngle(0.0);               // Вниз

// Громкость
await setVolume(75);  // 75%

// Аудио
await playAudio('/path/to/audio.wav');

// Отключение
await disconnect();
```

---

**Version**: 1.2.0
**Last Updated**: 2026-01-05
**Protocol Version**: 2381
