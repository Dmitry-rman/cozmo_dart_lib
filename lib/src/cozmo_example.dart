import 'dart:async';
import 'dart:io';
import 'cozmo_robot.dart';
import 'cozmo_camera.dart';

/// Example demonstrating camera functionality with Cozmo robot
///
/// This example shows how to:
/// 1. Connect to the robot
/// 2. Enable the camera (grayscale and color)
/// 3. Capture images
/// 4. Save images to disk
/// 5. Handle image events
///
/// Usage:
/// ```dart
/// var example = CozmoCameraExample();
/// await example.run();
/// ```
class CozmoCameraExample {
  final CozmoRobot robot = CozmoRobot.instance;
  StreamSubscription<CozmoCameraImage>? _imageSubscription;
  int _imageCount = 0;

  /// Run the camera example
  Future<void> run() async {
    print('🤖 Cozmo Camera Example');
    print('========================\n');

    // Connect to robot
    print('1️⃣ Connecting to Cozmo...');
    final error = await robot.connect();
    if (error != null) {
      print('❌ Failed to connect: $error');
      return;
    }
    print('✅ Connected to Cozmo!\n');

    try {
      // Example 1: Capture grayscale images
      print('2️⃣ Capturing grayscale images...');
      await _captureGrayscaleImages();

      // Example 2: Capture color images
      print('\n3️⃣ Capturing color images...');
      await _captureColorImages();

      // Example 4: Continuous capture with event stream
      print('\n4️⃣ Continuous capture with event stream...');
      await _continuousCapture();

    } catch (e) {
      print('❌ Error: $e');
    } finally {
      // Cleanup
      print('\n🧹 Cleaning up...');
      await _imageSubscription?.cancel();
      robot.enableCamera(enable: false);
      robot.disconnect();
      print('✅ Done!');
    }
  }

  /// Example 1: Capture grayscale images
  Future<void> _captureGrayscaleImages() async {
    // Enable camera in grayscale mode
    robot.enableCamera(
      enable: true,
      color: false,
      resolution: CozmoImageResolution.res320x240,
    );

    // Wait for camera to initialize
    await Future.delayed(const Duration(seconds: 1));

    // Subscribe to image events
    final completer = Completer<void>();

    _imageSubscription = robot.onCameraImage((image) {
      print('  📷 Received grayscale image: ${image.width}x${image.height}, ${image.data.length} bytes');

      // Save first 3 images
      if (_imageCount < 3) {
        _saveImage(image, 'grayscale_${_imageCount}.jpg');
        _imageCount++;
      } else {
        completer.complete();
      }
    });

    // Wait for images
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('  ⏱️ Timeout waiting for images');
      },
    );

    await _imageSubscription?.cancel();
    _imageCount = 0;

    // Disable camera
    robot.enableCamera(enable: false);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Example 2: Capture color images
  Future<void> _captureColorImages() async {
    // Enable camera in color mode
    robot.enableCamera(
      enable: true,
      color: true,
      resolution: CozmoImageResolution.res320x240,
    );

    // Wait for camera to initialize
    await Future.delayed(const Duration(seconds: 1));

    // Subscribe to image events
    final completer = Completer<void>();

    _imageSubscription = robot.onCameraImage((image) {
      print('  📷 Received color image: ${image.width}x${image.height}, ${image.data.length} bytes');

      // Save first 3 images
      if (_imageCount < 3) {
        _saveImage(image, 'color_${_imageCount}.jpg');
        _imageCount++;
      } else {
        completer.complete();
      }
    });

    // Wait for images
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('  ⏱️ Timeout waiting for images');
      },
    );

    await _imageSubscription?.cancel();
    _imageCount = 0;

    // Disable camera
    robot.enableCamera(enable: false);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Example 3: Continuous capture with event stream
  Future<void> _continuousCapture() async {
    // Enable camera
    robot.enableCamera(
      enable: true,
      color: true,
      resolution: CozmoImageResolution.res320x240,
    );

    // Wait for camera to initialize
    await Future.delayed(const Duration(seconds: 1));

    // Subscribe to image stream
    int imageCount = 0;
    final stopwatch = Stopwatch()..start();

    _imageSubscription = robot.cameraImageStream.listen(
      (image) {
        imageCount++;
        final fps = imageCount / stopwatch.elapsedMilliseconds * 1000;

        print('  📷 Frame $imageCount: ${image.width}x${image.height}, '
              '${image.data.length} bytes, ${fps.toStringAsFixed(1)} fps');

        // Save every 10th frame
        if (imageCount % 10 == 0) {
          _saveImage(image, 'continuous_$imageCount.jpg');
        }

        // Stop after 5 seconds
        if (stopwatch.elapsedMilliseconds >= 5000) {
          print('  ✅ Captured $imageCount frames in ${stopwatch.elapsedMilliseconds / 1000}s');
          stopwatch.stop();
        }
      },
      onError: (error) {
        print('  ❌ Stream error: $error');
      },
      onDone: () {
        print('  ✅ Stream completed');
      },
    );

    // Wait for 5 seconds
    await Future.delayed(const Duration(seconds: 5));

    await _imageSubscription?.cancel();

    // Disable camera
    robot.enableCamera(enable: false);
  }

  /// Save image to file
  Future<void> _saveImage(CozmoCameraImage image, String filename) async {
    final directory = Directory('cozmo_images');
    if (!await directory.exists()) {
      await directory.create();
    }

    final path = '${directory.path}/$filename';
    await image.save(path);
    print('    💾 Saved: $path');
  }
}

/// Simple example with minimal code
class SimpleCameraExample {
  static Future<void> run() async {
    final robot = CozmoRobot.instance;

    // Connect
    print('Connecting...');
    final error = await robot.connect();
    if (error != null) {
      print('Error: $error');
      return;
    }

    // Enable camera
    robot.enableCamera(enable: true, color: false);

    // Listen for images
    StreamSubscription<CozmoCameraImage>? subscription;
    subscription = robot.onCameraImage((image) {
      print('Got image: ${image.width}x$image.height');
      image.save('test.jpg');
      subscription?.cancel();
      robot.disconnect();
    });

    // Wait a bit
    await Future.delayed(const Duration(seconds: 5));
  }
}

// Run the example
Future<void> main() async {
  // Run full example
  var example = CozmoCameraExample();
  await example.run();

  // Or run simple example
  // await SimpleCameraExample.run();
}
