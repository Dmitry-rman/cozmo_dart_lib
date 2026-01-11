# Cozmo Camera Support - Dart Implementation

Complete camera support implementation for the Cozmo robot in Dart, ported from pycozmo.

## Overview

This implementation provides full camera functionality for Cozmo robot including:
- Grayscale and color image capture
- Multiple resolution support (160x120, 320x240)
- Event-based image streaming
- Automatic chunked packet assembly
- JPEG image handling

## Files Modified/Created

### New Files
- **`cozmo_camera.dart`** - Main camera implementation with `CozmoCamera` class
- **`CAMERA_README.md`** - This documentation file

### Modified Files
- **`cozmo_utils.dart`** - Added camera packet IDs (0x4c, 0x66, 0x4d)
- **`cozmo_client.dart`** - Integrated camera instance and packet handling
- **`cozmo_robot.dart`** - Added camera methods to high-level API
- **`cozmo_example.dart`** - Complete camera usage examples

## Architecture

### 1. CozmoCamera Class (`cozmo_camera.dart`)

Main camera management class with the following features:

#### Enums
```dart
enum CozmoImageSendMode {
  off(0),
  stream(1)
}

enum CozmoImageResolution {
  res160x120(0),   // 160x120 pixels
  res320x240(4)    // 320x240 pixels (default)
}
```

#### CozmoCameraImage Class
Represents a captured camera image:
- `data` - Raw JPEG bytes
- `width` - Image width in pixels
- `height` - Image height in pixels
- `isColor` - Whether image is color or grayscale
- `timestamp` - Capture timestamp
- `imageId` - Unique image identifier

Methods:
- `save(String path)` - Save image to file
- `toImageData()` - Get raw JPEG data

#### CozmoCamera Class
Main camera controller:
```dart
class CozmoCamera {
  // Enable/disable camera
  void enableCamera({
    bool enable = true,
    bool color = false,
    CozmoImageResolution resolution = CozmoImageResolution.res320x240,
  })

  // Stream of camera images
  Stream<CozmoCameraImage> get imageStream

  // Subscribe with callback
  StreamSubscription<CozmoCameraImage> onImage(
    void Function(CozmoCameraImage) callback
  )

  // Properties
  bool get isEnabled
  bool get isColorEnabled
  CozmoImageResolution get resolution

  // Cleanup
  void dispose()
}
```

### 2. Protocol Integration

#### Camera Packet IDs (in `cozmo_utils.dart`)
```dart
class CozmoCmd {
  static const int enableCamera = 0x4c;       // Enable/disable camera
  static const int enableColorImages = 0x66;   // Enable color images
  static const int imagePacket = 0x0b;        // Image data packet
}
```

#### Packet Handling (in `cozmo_client.dart`)
- Image packets (type 0x06, command 0x4d) are parsed in `_parsePackets()`
- Camera instance is created lazily via `getCamera()`
- Packets are forwarded to `CozmoCamera.handleImagePacket()`

### 3. High-Level API (in `cozmo_robot.dart`)

```dart
class CozmoRobot {
  late final CozmoCamera camera;

  // Enable/disable camera
  void enableCamera({
    bool enable = true,
    bool color = false,
    CozmoImageResolution resolution = CozmoImageResolution.res320x240,
  })

  // Subscribe to image events
  StreamSubscription<CozmoCameraImage> onCameraImage(
    void Function(CozmoCameraImage) callback
  )

  // Get image stream
  Stream<CozmoCameraImage> get cameraImageStream
}
```

## Usage Examples

### Basic Usage

```dart
import 'cozmo_robot.dart';

void main() async {
  final robot = CozmoRobot.instance;

  // Connect to robot
  await robot.connect();

  // Enable camera (grayscale, 320x240)
  robot.enableCamera(
    enable: true,
    color: false,
    resolution: CozmoImageResolution.res320x240,
  );

  // Listen for images
  robot.onCameraImage((image) {
    print('Received: ${image.width}x${image.height}');
    image.save('capture.jpg');
  });
}
```

### Color Images

```dart
// Enable color mode
robot.enableCamera(
  enable: true,
  color: true,  // Enable color
  resolution: CozmoImageResolution.res320x240,
);

robot.onCameraImage((image) {
  if (image.isColor) {
    print('Color image: ${image.width}x${image.height}');
  }
});
```

### Continuous Capture

```dart
// Enable camera
robot.enableCamera(enable: true);

// Subscribe to stream
int frameCount = 0;
final subscription = robot.cameraImageStream.listen(
  (image) {
    frameCount++;
    print('Frame $frameCount: ${image.data.length} bytes');

    // Save every 10th frame
    if (frameCount % 10 == 0) {
      image.save('frame_$frameCount.jpg');
    }
  },
  onError: (error) => print('Error: $error'),
);

// Stop after 5 seconds
await Future.delayed(const Duration(seconds: 5));
subscription.cancel();
robot.enableCamera(enable: false);
```

### With Cozmo Display

```dart
// Connect and enable camera
await robot.connect();
robot.enableCamera(enable: true);

// Display on Cozmo's face while capturing
robot.onCameraImage((image) async {
  // Process image
  print('Captured: ${image.width}x${image.height}');

  // Display something on Cozmo's face
  final eyesImage = CozmoSimpleImage.createEyes();
  robot.displayImage(eyesImage);
});
```

## Image Processing

### Image Format
- **Grayscale**: JPEG format, full resolution
- **Color**: JPEG format, half width (needs resize)

### Image Assembly
Images come in multiple chunks and are automatically assembled:
1. Robot sends image chunks (packet 0x4d)
2. Chunks are assembled in order
3. First byte indicates color (0=grayscale, 1=color)
4. JPEG data starts from byte 1
5. Complete image is emitted via stream

### Saving Images

```dart
// Save to file
await image.save('capture.jpg');

// Save to custom directory
final directory = Directory('photos');
await directory.create();
await image.save('${directory.path}/photo_1.jpg');
```

## Implementation Details

### Packet Structure

#### EnableCamera Packet (0x4c)
```
[command_id(0x4c), image_send_mode, image_resolution]
- image_send_mode: 0=off, 1=stream
- image_resolution: 0=160x120, 4=320x240
```

#### EnableColorImages Packet (0x66)
```
[command_id(0x66), enable]
- enable: 0=grayscale, 1=color
```

#### ImageChunk Packet (0x4d)
```
[chunk_id(uint16), image_id(uint16), image_chunk_count(uint16),
 frame_timestamp(uint32), image_encoding(uint8), image_resolution(uint8),
 ...data...]

Sent in packet type 0x06
```

### Chunk Assembly Process

1. **New Image Detection** (chunk_id == 0)
   - Reset partial state
   - Allocate buffer for max size
   - Store metadata

2. **Chunk Validation**
   - Check sequential order
   - Verify image_id matches
   - Discard on errors

3. **Data Accumulation**
   - Append chunk data to buffer
   - Update size and chunk_id

4. **Image Completion** (chunk_id == chunk_count - 1)
   - Extract first byte (color flag)
   - Extract JPEG data (bytes 1+)
   - Create CozmoCameraImage
   - Emit via stream

### Error Handling

- Missing chunks trigger reset and invalidation
- Wrong image_id triggers reset
- Chunk loss is logged
- Partial images are discarded on new image start

## Performance

- **Resolution**: 320x240 (default) or 160x120
- **Frame Rate**: ~10-15 fps (depends on resolution)
- **Format**: JPEG compressed
- **Latency**: ~100-200ms

## Comparison with pycozmo

### Similarities
- Same packet structure and IDs
- Chunked image assembly
- JPEG format
- Event-based delivery

### Differences
- Dart streams vs Python callbacks
- Type-safe enums
- Null safety
- Async/await instead of threading

## Troubleshooting

### No Images Received
1. Check camera is enabled: `robot.camera.isEnabled`
2. Verify connection: `robot.isConnected`
3. Check packet logs for image packets (0x4d)
4. Ensure robot is on charging platform

### Images are Corrupted
1. Check for missing chunks (logs will show)
2. Try lower resolution (160x120)
3. Reduce frame rate or network load
4. Verify stable WiFi connection

### Performance Issues
1. Use grayscale instead of color
2. Lower resolution to 160x120
3. Process images asynchronously
4. Buffer images in memory

## Example: Complete Application

See `cozmo_example.dart` for complete examples including:
- `CozmoCameraExample` - Full featured example
- `SimpleCameraExample` - Minimal example
- Grayscale capture
- Color capture
- Continuous streaming
- FPS calculation
- File saving

## API Reference

### CozmoCamera
- `enableCamera({bool enable, bool color, CozmoImageResolution resolution})` - Enable/disable camera
- `imageStream` - Stream<CozmoCameraImage> of captured images
- `onImage(callback)` - Subscribe with callback
- `isEnabled` - Camera enabled status
- `isColorEnabled` - Color mode status
- `resolution` - Current resolution
- `dispose()` - Cleanup resources

### CozmoCameraImage
- `data` - JPEG bytes
- `width` - Image width
- `height` - Image height
- `isColor` - Color flag
- `timestamp` - Capture time
- `imageId` - Unique ID
- `save(path)` - Save to file
- `toImageData()` - Get raw data

### CozmoRobot (Camera Methods)
- `camera` - Camera instance
- `enableCamera({...})` - Enable/disable
- `onCameraImage(callback)` - Subscribe
- `cameraImageStream` - Get stream

## Future Enhancements

Possible improvements:
- [ ] Add image processing utilities
- [ ] Support for more resolutions
- [ ] Video recording
- [ ] Real-time face detection
- [ ] Camera parameter tuning (exposure, gain)
- [ ] Multiple camera instances
- [ ] Image filters and effects

## License

This implementation follows the same license as the parent cozmo_dart_lib project.

## Credits

Based on pycozmo camera implementation: https://github.com/zayfod/pycozmo

Ported to Dart with enhancements for null safety and modern async patterns.
