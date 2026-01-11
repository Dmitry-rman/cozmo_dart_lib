/// Процедурная генерация лиц для Cozmo
///
/// Генерирует изображения лиц 128x64 для отображения на экране Cozmo
library cozmo_face;

import 'dart:typed_data';

// ============================================================
// КОНСТАНТЫ
// ============================================================

const int FACE_WIDTH = 48; // Уменьшено для избежания MTU
const int FACE_HEIGHT = 24; // Уменьшено для избежания MTU
const int FACE_SIZE = FACE_WIDTH * FACE_HEIGHT;

// Параметры глаз по умолчанию
const double DEFAULT_EYE_X = 0.5; // Положение глаз по X (0.0 - 1.0)
const double DEFAULT_EYE_Y = 0.5; // Положение глаз по Y (0.0 - 1.0)
const double DEFAULT_EYE_SIZE = 0.25; // Размер глаз (0.0 - 1.0)

// ============================================================
// ПРОЦЕДУРНОЕ ЛИЦО
// ============================================================

class CozmoFace {
  final Uint8List _pixels;

  // Параметры глаз
  double _leftEyeX = 0.35; // Левый глаз X (35% от ширины)
  double _leftEyeY = 0.5; // Левый глаз Y (50% от высоты)
  double _leftEyeSize = 0.25; // Размер левого глаза

  double _rightEyeX = 0.65; // Правый глаз X (65% от ширины)
  double _rightEyeY = 0.5; // Правый глаз Y (50% от высоты)
  double _rightEyeSize = 0.25; // Размер правого глаза

  // Веки
  double _leftEyelid = 0.0; // Левое веко (0.0 = открыто, 1.0 = закрыто)
  double _rightEyelid = 0.0; // Правое веко (0.0 = открыто, 1.0 = закрыто)

  CozmoFace() : _pixels = Uint8List(FACE_SIZE) {
    clear();
  }

  /// Очищает экран (черный)
  void clear() {
    for (int i = 0; i < FACE_SIZE; i++) {
      _pixels[i] = 0;
    }
  }

  /// Устанавливает пиксель (x, y) в значение value (0-255)
  void _setPixel(int x, int y, int value) {
    if (x < 0 || x >= FACE_WIDTH || y < 0 || y >= FACE_HEIGHT) return;
    _pixels[y * FACE_WIDTH + x] = value.clamp(0, 255);
  }

  /// Рисует закрашенный овал
  void _drawOval(
      int centerX, int centerY, int radiusX, int radiusY, int value) {
    for (int y = -radiusY; y <= radiusY; y++) {
      for (int x = -radiusX; x <= radiusX; x++) {
        // Проверяем, находится ли точка внутри эллипса
        if ((x * x) / (radiusX * radiusX) + (y * y) / (radiusY * radiusY) <=
            1.0) {
          _setPixel(centerX + x, centerY + y, value);
        }
      }
    }
  }

  /// Рисует линию
  void _drawLine(int x0, int y0, int x1, int y1, int value) {
    int dx = (x1 - x0).abs();
    int dy = (y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;

    while (true) {
      _setPixel(x0, y0, value);
      if (x0 == x1 && y0 == y1) break;
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  /// Рисует горизонтальную линию (для век)
  void _drawHorizontalLine(int y, int x1, int x2, int value) {
    for (int x = x1; x <= x2; x++) {
      _setPixel(x, y, value);
    }
  }

  /// Рендерит лицо в буфер пикселей
  void render() {
    clear();

    // Размеры глаз в пикселях
    int leftEyeRadiusX = (FACE_WIDTH * _leftEyeSize / 2).round();
    int leftEyeRadiusY = (FACE_HEIGHT * _leftEyeSize / 2).round();
    int rightEyeRadiusX = (FACE_WIDTH * _rightEyeSize / 2).round();
    int rightEyeRadiusY = (FACE_HEIGHT * _rightEyeSize / 2).round();

    // Позиции глаз
    int leftEyeX = (FACE_WIDTH * _leftEyeX).round();
    int leftEyeY = (FACE_HEIGHT * _leftEyeY).round();
    int rightEyeX = (FACE_WIDTH * _rightEyeX).round();
    int rightEyeY = (FACE_HEIGHT * _rightEyeY).round();

    // Рисуем глаза (белые, значение 255)
    _drawOval(leftEyeX, leftEyeY, leftEyeRadiusX, leftEyeRadiusY, 255);
    _drawOval(rightEyeX, rightEyeY, rightEyeRadiusX, rightEyeRadiusY, 255);

    // Рисуем веки (черные линии, если закрыты)
    if (_leftEyelid > 0.0) {
      int lidY = leftEyeY - (leftEyeRadiusY * _leftEyelid).round();
      int lidX1 = leftEyeX - leftEyeRadiusX;
      int lidX2 = leftEyeX + leftEyeRadiusX;
      for (int i = 0; i < (_leftEyelid * 5).round(); i++) {
        _drawHorizontalLine(lidY + i, lidX1, lidX2, 0);
      }
    }

    if (_rightEyelid > 0.0) {
      int lidY = rightEyeY - (rightEyeRadiusY * _rightEyelid).round();
      int lidX1 = rightEyeX - rightEyeRadiusX;
      int lidX2 = rightEyeX + rightEyeRadiusX;
      for (int i = 0; i < (_rightEyelid * 5).round(); i++) {
        _drawHorizontalLine(lidY + i, lidX1, lidX2, 0);
      }
    }
  }

  /// Возвращает закодированное изображение для отправки в DisplayImage (0x97)
  Uint8List encode() {
    // Простая кодировка: 1 байт на пиксель + размер в начале (2 байта)
    final encoded = Uint8List(FACE_SIZE + 2);

    // Размер изображения (little-endian)
    encoded[0] = FACE_SIZE & 0xFF;
    encoded[1] = (FACE_SIZE >> 8) & 0xFF;

    // Пиксели
    for (int i = 0; i < FACE_SIZE; i++) {
      encoded[i + 2] = _pixels[i];
    }

    return encoded;
  }

  // ============================================================
  // СЕТТЕРЫ ДЛЯ ЭМОЦИЙ
  // ============================================================

  /// Нейтральное лицо
  void setNeutral() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.25;
    _leftEyelid = 0.0;

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.25;
    _rightEyelid = 0.0;
  }

  /// Счастливое лицо (большие глаза, приподнятые веки)
  void setHappy() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.28; // Чуть больше
    _leftEyelid = -0.1; // Приподняты

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.28;
    _rightEyelid = -0.1;
  }

  /// Грустное лицо (опущенные веки)
  void setSad() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.55; // Чуть ниже
    _leftEyeSize = 0.25;
    _leftEyelid = 0.3; // Опущены

    _rightEyeX = 0.65;
    _rightEyeY = 0.55;
    _rightEyeSize = 0.25;
    _rightEyelid = 0.3;
  }

  /// Удивленное лицо (очень большие глаза)
  void setSurprised() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.35; // Очень большие!
    _leftEyelid = 0.0;

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.35;
    _rightEyelid = 0.0;
  }

  /// Задумчивое лицо (глаза чуть прищурены)
  void setThinking() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.25;
    _leftEyelid = 0.15; // Чуть прищурены

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.25;
    _rightEyelid = 0.15;
  }

  /// Приветственное лицо (счастливое, глаза сияют)
  void setGreeting() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.30; // Большие сияющие глаза
    _leftEyelid = -0.15; // Приподняты

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.30;
    _rightEyelid = -0.15;
  }

  /// Спящее лицо (закрытые глаза)
  void setSleepy() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.25;
    _leftEyelid = 0.9; // Почти закрыты

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.25;
    _rightEyelid = 0.9;
  }

  /// Испуганное лицо (очень большие, немного прищурены)
  void setScared() {
    _leftEyeX = 0.35;
    _leftEyeY = 0.5;
    _leftEyeSize = 0.32; // Огромные глаза
    _leftEyelid = 0.1; // Чуть прищурены от страха

    _rightEyeX = 0.65;
    _rightEyeY = 0.5;
    _rightEyeSize = 0.32;
    _rightEyelid = 0.1;
  }
  
  // ============================================================
  // ПУБЛИЧНЫЕ СЕТТЕРЫ ДЛЯ КОМПОНЕНТОВ
  // ============================================================
  
  /// Сеттеры для параметров глаз
  
  // Левый глаз
  void setLeftEyeX(double value) => _leftEyeX = value.clamp(0.0, 1.0);
  void setLeftEyeY(double value) => _leftEyeY = value.clamp(0.0, 1.0);
  void setLeftEyeSize(double value) => _leftEyeSize = value.clamp(0.0, 0.5);
  void setLeftEyelid(double value) => _leftEyelid = value.clamp(-0.5, 1.0);
  
  // Правый глаз
  void setRightEyeX(double value) => _rightEyeX = value.clamp(0.0, 1.0);
  void setRightEyeY(double value) => _rightEyeY = value.clamp(0.0, 1.0);
  void setRightEyeSize(double value) => _rightEyeSize = value.clamp(0.0, 0.5);
  void setRightEyelid(double value) => _rightEyelid = value.clamp(-0.5, 1.0);
  
  // Геттеры
  double get leftEyeX => _leftEyeX;
  double get leftEyeY => _leftEyeY;
  double get leftEyeSize => _leftEyeSize;
  double get leftEyelid => _leftEyelid;
  
  double get rightEyeX => _rightEyeX;
  double get rightEyeY => _rightEyeY;
  double get rightEyeSize => _rightEyeSize;
  double get rightEyelid => _rightEyelid;
}