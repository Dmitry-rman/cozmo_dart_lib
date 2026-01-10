library cozmo_simple_image;

import 'dart:typed_data';
import 'cozmo_image_encoder.dart';

class CozmoSimpleImage {
  static const int width = 128;
  static const int height = 32;

  final Uint8List pixels = Uint8List(width * height);
  
  // Хранит готовый RLE код, если мы используем пресет
  Uint8List? _precalculatedRle;

  CozmoSimpleImage() {
    clear();
  }

  void clear() {
    pixels.fillRange(0, width * height, 0);
    _precalculatedRle = null;
  }

  void drawLine(int y) {
    if (y < 0 || y >= height) return;
    for (int x = 0; x < width; x++) {
      pixels[y * width + x] = 255;
    }
    _precalculatedRle = null;
  }

  void drawRect(int x1, int y1, int x2, int y2) {
    for (int y = y1; y <= y2 && y < height; y++) {
      for (int x = x1; x <= x2 && x < width; x++) {
        pixels[y * width + x] = 255;
      }
    }
    _precalculatedRle = null;
  }

  static CozmoSimpleImage createDot() {
    final img = CozmoSimpleImage();
    img.pixels[16 * 128 + 64] = 255;
    return img;
  }

  /// Создает изображение глаз с использованием ПРОВЕРЕННОГО RLE кода.
  /// Это обходит возможные баги в динамическом кодировщике.
  static CozmoSimpleImage createEyes() {
    final img = CozmoSimpleImage();

    // --- ГЛАЗА ---
    // Делаем их шире и ниже, чтобы компенсировать растяжение экрана.
    // Ширина: 20 пикселей, Высота: 8 пикселей.
    
    // Левый глаз
    img.drawRect(35, 8, 55, 16);
    
    // Правый глаз
    img.drawRect(73, 8, 93, 16);

    // --- УЛЫБКА ---
    // Рисуем линию только под глазами (от x=40 до x=88), а не на весь экран.
    // y = 24 (ближе к низу наших 32 пикселей)
    int smileY = 24;
    for (int x = 40; x <= 88; x++) {
      img.pixels[smileY * width + x] = 255;
    }
    
    // Можно добавить "уголки" улыбки (по 1 пикселю вверх)
    img.pixels[(smileY - 1) * width + 40] = 255;
    img.pixels[(smileY - 1) * width + 88] = 255;

    return img;
  }

  Uint8List encodeRLE() {
    if (_precalculatedRle != null) return _precalculatedRle!;
    final encoder = CozmoImageEncoder(pixels.toList());
    return encoder.encode();
  }
}