library cozmo_camera;

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';

/// Image send mode for camera
enum CozmoImageSendMode {
  off(0),
  stream(1);

  final int value;
  const CozmoImageSendMode(this.value);
}

/// Image resolution
enum CozmoImageResolution {
  res160x120(0),  // 160x120
  res320x240(4);  // 320x240 (default)

  final int value;
  const CozmoImageResolution(this.value);

  int get width {
    switch (this) {
      case CozmoImageResolution.res160x120:
        return 160;
      case CozmoImageResolution.res320x240:
        return 320;
    }
  }

  int get height {
    switch (this) {
      case CozmoImageResolution.res160x120:
        return 120;
      case CozmoImageResolution.res320x240:
        return 240;
    }
  }
}

/// Represents a camera image captured from Cozmo
class CozmoCameraImage {
  /// The image data as bytes (miniJPEG format - needs conversion!)
  final Uint8List data;

  /// Image width in pixels (for color images, this is HALF of original width)
  final int width;

  /// Image height in pixels
  final int height;

  /// Original image width (from camera settings, before any color halving)
  final int originalWidth;

  /// Whether this is a color image
  final bool isColor;

  /// Timestamp when the image was captured
  final DateTime timestamp;

  /// Image ID
  final int imageId;

  CozmoCameraImage({
    required this.data,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.isColor,
    required this.timestamp,
    required this.imageId,
  });

  /// Save the image to a file
  Future<void> save(String path) async {
    final file = File(path);
    await file.writeAsBytes(data);
  }

  /// Get the raw image data (JPEG format)
  Uint8List toImageData() {
    return data;
  }

  @override
  String toString() {
    return 'CozmoCameraImage(id: $imageId, ${width}x$height (original: ${originalWidth}x$height), color: $isColor, ${data.length} bytes)';
  }
}

/// Image chunk received from Cozmo
class _ImageChunk {
  final int chunkId;
  final int imageId;
  final int imageChunkCount;
  final int frameTimestamp;
  final int imageEncoding;
  final int imageResolution;
  final Uint8List data;

  _ImageChunk({
    required this.chunkId,
    required this.imageId,
    required this.imageChunkCount,
    required this.frameTimestamp,
    required this.imageEncoding,
    required this.imageResolution,
    required this.data,
  });
}

/// Manages Cozmo's camera functionality
class CozmoCamera {
  final CozmoClient _client;

  bool _isEnabled = false;
  bool _isColorEnabled = false;
  CozmoImageResolution _resolution = CozmoImageResolution.res320x240;

  // Partial image state
  int? _partialImageId;
  Uint8List? _partialData;
  int _partialSize = 0;
  int _lastChunkId = -1;
  DateTime? _partialTimestamp;
  bool _partialInvalid = false;

  // Image callback
  final StreamController<CozmoCameraImage> _imageController = StreamController<CozmoCameraImage>.broadcast();

  CozmoCamera(this._client);

  /// Stream of camera images
  Stream<CozmoCameraImage> get imageStream => _imageController.stream;

  /// Whether camera is currently enabled
  bool get isEnabled => _isEnabled;

  /// Whether color mode is enabled
  bool get isColorEnabled => _isColorEnabled;

  /// Current image resolution
  CozmoImageResolution get resolution => _resolution;

  /// Enable or disable the camera
  ///
  /// [enable] - true to enable camera, false to disable
  /// [color] - true to enable color images (default: grayscale)
  /// [resolution] - image resolution (default: 320x240)
  void enableCamera({
    bool enable = true,
    bool color = false,
    CozmoImageResolution resolution = CozmoImageResolution.res320x240,
  }) {
    _isEnabled = enable;
    _isColorEnabled = color;
    _resolution = resolution;

    if (enable) {
      // Send EnableCamera packet
      // Packet structure: [command_id(0x4c), image_send_mode, image_resolution]
      final mode = CozmoImageSendMode.stream.value;
      _client.sendCommand(0x4c, [mode, resolution.value]);

      // Send EnableColorImages packet
      // Packet structure: [command_id(0x66), enable]
      _client.sendCommand(0x66, [color ? 1 : 0]);

      print('📷 Camera enabled: ${resolution.width}x${resolution.height}, color: $color');
    } else {
      // Disable camera
      _client.sendCommand(0x4c, [CozmoImageSendMode.off.value, 0]);
      _resetPartialImage();
      print('📷 Camera disabled');
    }
  }

  /// Handle incoming image packet from Cozmo
  void handleImagePacket(Uint8List packet) {
    if (!_isEnabled) return;

    try {
      final reader = ByteReader(packet, 0);

      // Skip packet_id (0xf2) - first byte
      reader.readUint8();

      // Parse image chunk header (18 bytes total)
      // Based on pycozmo ImageChunk structure:
      // frame_timestamp (uint32), image_id (uint32), chunk_debug (uint32),
      // image_encoding (uint8), image_resolution (uint8),
      // image_chunk_count (uint8), chunk_id (uint8), status (uint16)
      final frameTimestamp = reader.readUint32();
      final imageId = reader.readUint32();
      reader.readUint32(); // chunk_debug (unused)
      final imageEncoding = reader.readUint8();
      final imageResolution = reader.readUint8();
      final imageChunkCount = reader.readUint8();
      final chunkId = reader.readUint8();
      reader.readUint16(); // status (unused)

      // Remaining data is the image chunk
      const dataOffset = 1 + 4 + 4 + 4 + 1 + 1 + 1 + 1 + 2; // 19 bytes (1 for packet_id + 18 header)
      final data = Uint8List.sublistView(packet, dataOffset);

      final chunk = _ImageChunk(
        chunkId: chunkId,
        imageId: imageId,
        imageChunkCount: imageChunkCount,
        frameTimestamp: frameTimestamp,
        imageEncoding: imageEncoding,
        imageResolution: imageResolution,
        data: data,
      );

      _processImageChunk(chunk);
    } catch (e) {
      print('⚠️ Error parsing image packet: $e');
      _resetPartialImage();
    }
  }

  /// Process an image chunk
  void _processImageChunk(_ImageChunk chunk) {
    // Check if this is a new image
    if (_partialImageId != null && chunk.chunkId == 0) {
      if (!_partialInvalid) {
        print('⚠️ Lost final chunk of image - discarding');
      }
      _partialImageId = null;
    }

    // If we don't have a partial image, start a new one
    if (_partialImageId == null) {
      if (chunk.chunkId != 0) {
        if (!_partialInvalid) {
          print('⚠️ Received chunk of broken image');
        }
        _partialInvalid = true;
        return;
      }

      // Start new image
      _resetPartialImage();
      _partialImageId = chunk.imageId;
      _partialTimestamp = DateTime.fromMillisecondsSinceEpoch(chunk.frameTimestamp);

      // Calculate max size (width * height * 3 for RGB)
      final resolution = CozmoImageResolution.values.firstWhere(
        (r) => r.value == chunk.imageResolution,
        orElse: () => CozmoImageResolution.res320x240,
      );
      final maxSize = resolution.width * resolution.height * 3;
      _partialData = Uint8List(maxSize);
      _partialSize = 0;
      _lastChunkId = -1;
      _partialInvalid = false;
    }

    // Check for missing chunks or wrong image
    if (chunk.chunkId != (_lastChunkId + 1) || chunk.imageId != _partialImageId) {
      print('⚠️ Image missing chunks - discarding (chunkId: ${chunk.chunkId}, expected: ${_lastChunkId + 1})');
      _resetPartialImage();
      _partialInvalid = true;
      return;
    }

    // Append chunk data
    final offset = _partialSize;
    _partialData!.setRange(offset, offset + chunk.data.length, chunk.data);
    _partialSize += chunk.data.length;
    _lastChunkId = chunk.chunkId;

    // Check if this is the last chunk
    if (chunk.chunkId == chunk.imageChunkCount - 1) {
      _processCompletedImage(chunk);
      _resetPartialImage();
    }
  }

  /// Process a completed image
  void _processCompletedImage(_ImageChunk finalChunk) {
    if (_partialData == null || _partialSize == 0) return;

    try {
      // Extract the actual image data
      final imageData = Uint8List.sublistView(_partialData!, 0, _partialSize);

      // First byte indicates if it's a color image
      final isColorImage = imageData[0] != 0;

      // The actual JPEG data starts after the first byte
      final jpegData = Uint8List.sublistView(imageData, 1);

      // Get resolution
      final resolution = CozmoImageResolution.values.firstWhere(
        (r) => r.value == finalChunk.imageResolution,
        orElse: () => CozmoImageResolution.res320x240,
      );

      // Store original width before any color halving
      final originalWidth = resolution.width;
      final height = resolution.height;

      // Color images are half width in the data
      final width = isColorImage ? originalWidth ~/ 2 : originalWidth;

      // Create camera image object
      final cameraImage = CozmoCameraImage(
        data: jpegData,
        width: width,
        height: height,
        originalWidth: originalWidth,
        isColor: isColorImage,
        timestamp: _partialTimestamp ?? DateTime.now(),
        imageId: _partialImageId ?? 0,
      );

      // Emit image event
      if (!_imageController.isClosed) {
        _imageController.add(cameraImage);
      }

      //print('📷 Received image: ${cameraImage.width}x${cameraImage.height}, ${jpegData.length} bytes, color: $isColorImage');
    } catch (e) {
      print('⚠️ Error processing completed image: $e');
    }
  }

  /// Reset partial image state
  void _resetPartialImage() {
    _partialImageId = null;
    _partialData = null;
    _partialSize = 0;
    _lastChunkId = -1;
    _partialTimestamp = null;
    _partialInvalid = false;
  }

  /// Dispose of the camera and release resources
  void dispose() {
    enableCamera(enable: false);
    _imageController.close();
  }

  /// Subscribe to image events with a callback
  StreamSubscription<CozmoCameraImage> onImage(void Function(CozmoCameraImage) callback) {
    return imageStream.listen(callback);
  }
}
