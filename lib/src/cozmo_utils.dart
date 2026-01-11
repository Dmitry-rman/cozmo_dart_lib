library cozmo_utils;

import 'dart:typed_data';

// --- CONSTANTS ---
const String COZMO_IP = '172.31.1.1';
const int COZMO_PORT = 5551;
const List<int> FRAME_ID = [0x43, 0x4F, 0x5A, 0x03, 0x52, 0x45, 0x01];
const int AUDIO_PACKET_SAMPLES = 744;
const int COZMO_SAMPLE_RATE = 22050;

// --- COMMAND IDs ---
class CozmoCmd {
  static const int driveWheels = 0x32;
  static const int turnInPlace = 0x39;
  static const int setLiftHeight = 0x36;
  static const int setHeadAngle = 0x37;
  static const int stopAllMotors = 0x3b;
  static const int setVolume = 0x64;
  static const int outputAudio = 0x8e;
  static const int outputSilence = 0x8f;
  static const int displayImage = 0x97;
  static const int endAnimation = 0x9a;
  static const int playAnimationTrigger = 0x26;
  static const int playAnimation = 0x27;
  static const int robotState = 0x25;       // Enable
  static const int enableRobotState = 0x45; // SetOrigin
  static const int syncTime = 0x4b;
  static const int enableAnimState = 0x9f;
  static const int enableCamera = 0x4c;     // Enable/disable camera
  static const int enableColorImages = 0x66; // Enable color images
  static const int imagePacket = 0x0b;      // Image data packet
}

class CozmoException implements Exception {
  final String message;
  CozmoException(this.message);
  @override
  String toString() => 'CozmoException: $message';
}

// --- ENUMS ---
enum CozmoEmotion {
  happy(20), sad(21), surprised(22), thinking(23), frustrated(24),
  scared(25), sleepy(26), dog(27), cat(28), win(29), lose(30),
  chatty(19), greeting(2704), sneeze(2725), hiccup(2727);
  final int id;
  const CozmoEmotion(this.id);
}

enum CozmoAnimation {
  wakeUp("anim_launch_wakeup_01"),
  sleep("anim_sleeping_01"),
  greeting("anim_greeting_01"),
  happy("anim_happy_pounce_01"),
  sad("anim_sad_reactions_01"),
  surprised("anim_surprised_01"),
  thinking("anim_thinking_01"),
  dance("anim_dance_01"),
  pounce("anim_pounce_01"),
  nothing("anim_keep_face_01");
  final String name;
  const CozmoAnimation(this.name);
}

// --- HELPERS ---
class ByteWriter {
  final List<int> _b = [];
  void writeUint8(int v) => _b.add(v & 0xFF);
  void writeUint16(int v) { _b.add(v & 0xFF); _b.add((v >> 8) & 0xFF); }
  void writeUint32(int v) { _b.add(v & 0xFF); _b.add((v >> 8) & 0xFF); _b.add((v >> 16) & 0xFF); _b.add((v >> 24) & 0xFF); }
  void writeFloat64(double v) {
    var d = ByteData(8)..setFloat64(0, v, Endian.little);
    for (int i = 0; i < 8; i++) {
      _b.add(d.getUint8(i));
    }
  }
  void writeBytes(List<int> v) => _b.addAll(v);
  Uint8List toUint8List() => Uint8List.fromList(_b);
}

class ByteReader {
  final Uint8List _d; int _p = 0; ByteReader(this._d, [int s=0]) : _p=s;
  int readUint8() => _d[_p++] & 0xFF;
  int readUint16() { int v = _d[_p] | (_d[_p+1] << 8); _p+=2; return v; }
  int readUint32() { int v = _d[_p] | (_d[_p+1] << 8) | (_d[_p+2] << 16) | (_d[_p+3] << 24); _p+=4; return v; }
  double readFloat64() {
    var d = ByteData(8);
    for (int i = 0; i < 8; i++) {
      d.setUint8(i, _d[_p + i]);
    }
    _p += 8;
    return d.getFloat64(0, Endian.little);
  }
}

List<int> uint16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> uint32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> float32(double v) { var b = ByteData(4)..setFloat32(0, v, Endian.little); return [b.getUint8(0), b.getUint8(1), b.getUint8(2), b.getUint8(3)]; }