library cozmo_drive;

import 'dart:async';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';

class CozmoDrive {
  final CozmoClient _client;
  CozmoDrive(this._client);

  Future<void> wheels(double l, double r, {double lAccel = 0.0, double rAccel = 0.0, double? duration}) async {
    l = l.clamp(-250.0, 250.0); r = r.clamp(-250.0, 250.0);
    _client.sendCommand(CozmoCmd.driveWheels, [...float32(l), ...float32(r), ...float32(lAccel), ...float32(rAccel)]);
    if (duration != null) {
      await Future.delayed(Duration(milliseconds: (duration * 1000).toInt()));
      await stop();
    }
  }

  Future<void> stop() async => _client.sendCommand(CozmoCmd.stopAllMotors, []);

  Future<void> turn(double angle, {double speed = 2.0}) async {
    double rad = (angle.abs() <= 360) ? angle * 3.14159 / 180.0 : angle;
    _client.sendCommand(CozmoCmd.turnInPlace, [...float32(rad), ...float32(speed), ...float32(2.0), ...float32(0.01), 0, 0, 0, 0]);
  }
}