# Camera Quick Start Guide

## 5-Minute Setup

### 1. Import Required Files
```dart
import 'cozmo_robot.dart';
import 'cozmo_camera.dart';
```

### 2. Connect and Enable Camera
```dart
final robot = CozmoRobot.instance;
await robot.connect();

// Enable camera (grayscale, 320x240)
robot.enableCamera(enable: true);
```

### 3. Capture Images
```dart
robot.onCameraImage((image) {
  print('Got image: ${image.width}x${image.height}');
  image.save('my_photo.jpg');
});
```

## Common Patterns

### Pattern 1: Capture Single Image
```dart
robot.enableCamera(enable: true);

final subscription = robot.onCameraImage((image) {
  image.save('single.jpg');
  subscription.cancel();
  robot.enableCamera(enable: false);
});
```

### Pattern 2: Capture N Images
```dart
robot.enableCamera(enable: true);

int count = 0;
final subscription = robot.onCameraImage((image) {
  image.save('image_$count.jpg');
  count++;

  if (count >= 10) {
    subscription.cancel();
    robot.enableCamera(enable: false);
  }
});
```

### Pattern 3: Color Images
```dart
robot.enableCamera(
  enable: true,
  color: true,  // Enable color
);

robot.onCameraImage((image) {
  print('Color: ${image.isColor}');
  image.save('color.jpg');
});
```

### Pattern 4: Low Resolution
```dart
robot.enableCamera(
  enable: true,
  resolution: CozmoImageResolution.res160x120,
);
```

### Pattern 5: Continuous Stream
```dart
robot.enableCamera(enable: true);

robot.cameraImageStream.listen((image) {
  // Process each frame
  print('Frame: ${image.data.length} bytes');
});
```

## Resolution Options

```dart
CozmoImageResolution.res160x120  // 160x120 pixels
CozmoImageResolution.res320x240  // 320x240 pixels (default)
```

## Camera Modes

```dart
// Grayscale (faster, less data)
robot.enableCamera(enable: true, color: false);

// Color (slower, more data)
robot.enableCamera(enable: true, color: true);
```

## Image Properties

```dart
robot.onCameraImage((image) {
  print('Size: ${image.width}x${image.height}');
  print('Bytes: ${image.data.length}');
  print('Color: ${image.isColor}');
  print('Time: ${image.timestamp}');
  print('ID: ${image.imageId}');
});
```

## Saving Images

```dart
// Save to current directory
await image.save('photo.jpg');

// Save to subdirectory
final dir = Directory('photos');
await dir.create();
await image.save('${dir.path}/photo.jpg');

// Custom naming
final timestamp = DateTime.now().millisecondsSinceEpoch;
await image.save('img_$timestamp.jpg');
```

## Error Handling

```dart
robot.onCameraImage(
  (image) {
    image.save('photo.jpg').catchError((e) {
      print('Save error: $e');
    });
  },
  onError: (error) {
    print('Camera error: $error');
  },
);
```

## Cleanup

```dart
// Always cleanup when done
subscription.cancel();
robot.enableCamera(enable: false);
robot.disconnect();
```

## Complete Example

```dart
import 'cozmo_robot.dart';
import 'cozmo_camera.dart';

void main() async {
  final robot = CozmoRobot.instance;

  try {
    // Connect
    await robot.connect();

    // Enable camera
    robot.enableCamera(enable: true, color: false);

    // Capture 5 images
    int count = 0;
    final subscription = robot.onCameraImage((image) {
      image.save('image_$count.jpg');
      print('Saved image $count');
      count++;

      if (count >= 5) {
        subscription.cancel();
        robot.enableCamera(enable: false);
        robot.disconnect();
      }
    });

  } catch (e) {
    print('Error: $e');
  }
}
```

## Tips

1. **Start with grayscale** - Faster and more reliable
2. **Use 320x240** - Best quality/speed balance
3. **Handle errors** - Network can be unreliable
4. **Cancel subscriptions** - Prevent memory leaks
5. **Disable camera** - When not in use saves battery

## Troubleshooting

**No images?**
- Check `robot.isConnected`
- Check `robot.camera.isEnabled`
- Wait 1-2 seconds after enabling

**Images corrupted?**
- Try lower resolution
- Use grayscale
- Check WiFi signal

**Slow performance?**
- Use grayscale
- Lower resolution
- Process images asynchronously
