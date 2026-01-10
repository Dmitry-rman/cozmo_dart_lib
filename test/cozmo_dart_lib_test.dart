import 'package:flutter_test/flutter_test.dart';

import 'package:cozmo_dart_lib/cozmo_dart_lib.dart';

void main() {
  test('CozmoRobot singleton instance', () {
    final robot1 = CozmoRobot.instance;
    final robot2 = CozmoRobot.instance;
    expect(identical(robot1, robot2), true);
  });

  test('CozmoClient singleton instance', () {
    final client1 = CozmoClient.instance;
    final client2 = CozmoClient.instance;
    expect(identical(client1, client2), true);
  });

  test('CozmoSimpleImage createEyes', () {
    final image = CozmoSimpleImage.createEyes();
    expect(CozmoSimpleImage.width, 128);
    expect(CozmoSimpleImage.height, 64);
    expect(image.pixels.length, 8192);
  });
}
