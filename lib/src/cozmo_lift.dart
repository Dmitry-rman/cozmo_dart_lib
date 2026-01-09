library cozmo_lift;

import 'cozmo_client.dart';
import 'cozmo_utils.dart';

class CozmoLift {
  final CozmoClient _client;
  CozmoLift(this._client);

  Future<void> setHeight(double height, {double speed = 3.0}) async {
    height = height.clamp(32.0, 92.0);
    _client.sendCommand(CozmoCmd.setLiftHeight, [...float32(height), ...float32(speed), ...float32(20.0), ...float32(0.0), 0]);
  }
}