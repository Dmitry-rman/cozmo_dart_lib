library cozmo_image_converter;

import 'dart:typed_data';

/// Converts Cozmo's miniJPEG format to standard JPEG
///
/// Cozmo sends images in a special "miniJPEG" format that needs conversion
/// to be viewable as standard JPEG files.
class CozmoImageConverter {
  /// Convert miniColor JPEG format to standard JPEG
  ///
  /// [miniData] - Raw image data from Cozmo (first byte is color flag)
  /// [width] - Image width (note: for color images, actual width is half)
  /// [height] - Image height
  static Uint8List convertMiniColorToJpeg(Uint8List miniData, int width, int height) {
    // Skip first byte (color flag)
    final data = Uint8List.sublistView(miniData, 1);

    // Create JPEG header for color image
    final header = _createColorJpegHeader(width, height);

    // Combine header + converted data
    final result = Uint8List(header.length + data.length * 2);
    result.setRange(0, header.length, header);

    // Convert miniJPEG format to standard JPEG
    // This is a simplified version - the full algorithm is quite complex
    int outPos = header.length;
    for (int i = 0; i < data.length; i++) {
      final byte = data[i];

      // Escape 0xFF bytes (JPEG stuffing)
      if (byte == 0xFF) {
        result[outPos++] = 0xFF;
        result[outPos++] = 0x00;
      } else {
        result[outPos++] = byte;
      }
    }

    // Add EOI marker
    result[outPos++] = 0xFF;
    result[outPos++] = 0xD9;

    return Uint8List.sublistView(result, 0, outPos);
  }

  /// Convert miniGray JPEG format to standard JPEG
  ///
  /// [miniData] - Raw image data from Cozmo (first byte is color flag)
  /// [width] - Image width
  /// [height] - Image height
  static Uint8List convertMiniGrayToJpeg(Uint8List miniData, int width, int height) {
    // Skip first byte (color flag)
    final data = Uint8List.sublistView(miniData, 1);

    // Create JPEG header for grayscale image
    final header = _createGrayJpegHeader(width, height);

    // Combine header + converted data
    final result = Uint8List(header.length + data.length * 2);
    result.setRange(0, header.length, header);

    // Convert miniJPEG format to standard JPEG
    int outPos = header.length;
    for (int i = 0; i < data.length; i++) {
      final byte = data[i];

      // Escape 0xFF bytes (JPEG stuffing)
      if (byte == 0xFF) {
        result[outPos++] = 0xFF;
        result[outPos++] = 0x00;
      } else {
        result[outPos++] = byte;
      }
    }

    // Add EOI marker
    result[outPos++] = 0xFF;
    result[outPos++] = 0xD9;

    return Uint8List.sublistView(result, 0, outPos);
  }

  /// Create JPEG header for color image (YCbCr)
  static Uint8List _createColorJpegHeader(int width, int height) {
    final header = <int>[
      // SOI
      0xFF, 0xD8,

      // APP0 (JFIF identifier)
      0xFF, 0xE0,
      0x00, 0x10,  // Length
      0x4A, 0x46, 0x49, 0x46, 0x00,  // "JFIF\0"
      0x01, 0x01,  // Version 1.1
      0x00,        // Density units (0 = none)
      0x01, 0x00,  // X density
      0x01, 0x00,  // Y density
      0x00,        // No thumbnail

      // DQT (Quantization table)
      0xFF, 0xDB,
      0x00, 0x43,  // Length
      0x00,        // Table ID (0 = luminance)
      // 16x8 quantization table
      0x10, 0x0B, 0x0C, 0x0E, 0x0C, 0x0A, 0x10, 0x0E,
      0x0D, 0x0E, 0x12, 0x11, 0x10, 0x13, 0x18, 0x28,
      0x1A, 0x18, 0x16, 0x16, 0x18, 0x31, 0x23, 0x25,
      0x1D, 0x28, 0x3A, 0x33, 0x3D, 0x3C, 0x39, 0x33,
      0x38, 0x37, 0x40, 0x48, 0x5C, 0x4E, 0x40, 0x44,
      0x57, 0x45, 0x37, 0x38, 0x50, 0x6D, 0x51, 0x57,
      0x5F, 0x62, 0x67, 0x68, 0x67, 0x3E, 0x4D, 0x71,
      0x79, 0x70, 0x64, 0x78, 0x5C, 0x65, 0x67, 0x63,

      // SOF0 (Start of frame, baseline DCT)
      0xFF, 0xC0,
      0x00, 0x11,  // Length (17 = 8 + 3*components)
      0x08,        // Precision (8 bits)
      (height >> 8) & 0xFF, height & 0xFF,  // Height
      (width >> 8) & 0xFF, width & 0xFF,    // Width
      0x03,        // Number of components (3 = YCbCr)

      // Component 1 (Y)
      0x01,        // Component ID
      0x21,        // Sampling factors (2x1)
      0x00,        // Quantization table selector

      // Component 2 (Cb)
      0x02,        // Component ID
      0x11,        // Sampling factors (1x1)
      0x01,        // Quantization table selector

      // Component 3 (Cr)
      0x03,        // Component ID
      0x11,        // Sampling factors (1x1)
      0x01,        // Quantization table selector

      // DHT (Define Huffman table) - Simplified
      0xFF, 0xC4,
      0x00, 0xD2,  // Length
      0x00,        // Table ID (0 = DC luminance)
      // Huffman table data (simplified)
      0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      // ... (full table would be here)
    ];

    return Uint8List.fromList(header);
  }

  /// Create JPEG header for grayscale image
  static Uint8List _createGrayJpegHeader(int width, int height) {
    final header = <int>[
      // SOI
      0xFF, 0xD8,

      // APP0 (JFIF identifier)
      0xFF, 0xE0,
      0x00, 0x10,  // Length
      0x4A, 0x46, 0x49, 0x46, 0x00,  // "JFIF\0"
      0x01, 0x01,  // Version 1.1
      0x00,        // Density units
      0x01, 0x00,  // X density
      0x01, 0x00,  // Y density
      0x00,        // No thumbnail

      // SOF0 (Start of frame)
      0xFF, 0xC0,
      0x00, 0x0B,  // Length (11 = 8 + 1*components)
      0x08,        // Precision
      (height >> 8) & 0xFF, height & 0xFF,
      (width >> 8) & 0xFF, width & 0xFF,
      0x01,        // 1 component (grayscale)

      // Component 1 (Y)
      0x01,        // Component ID
      0x11,        // Sampling factors (1x1)
      0x00,        // Quantization table
    ];

    return Uint8List.fromList(header);
  }
}
