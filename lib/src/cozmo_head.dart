library cozmo_head;

import 'dart:async';
import 'dart:convert';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';

class CozmoHead {
  final CozmoClient _client;
  CozmoHead(this._client);

  Future<void> setAngle(double angle, {double speed = 10.0, double accel = 10.0}) async {
    angle = angle.clamp(-0.436, 0.777);
    _client.sendCommand(CozmoCmd.setHeadAngle, [...float32(angle), ...float32(speed), ...float32(accel), ...float32(0.0), 0]);
  }

  Future<void> playEmotion(CozmoEmotion emotion, {int loops = 1}) async {
    print('🎭 Emotion: ${emotion.name}');
    _client.sendCommand(CozmoCmd.playAnimationTrigger, [...uint32(emotion.id), ...uint32(loops), 1, 0, 0, 0]);
  }

  Future<void> playAnimation(CozmoAnimation anim, {int loops = 1}) async {
    await playAnimationByName(anim.name, loops: loops);
  }

  Future<void> playAnimationByName(String name, {int loops = 1}) async {
    print('🎬 Animation: $name');
    final bytes = utf8.encode(name);
    _client.sendCommand(CozmoCmd.playAnimation, [bytes.length, ...bytes, ...uint32(loops), 1, 0, 0, 0]);
  }
}