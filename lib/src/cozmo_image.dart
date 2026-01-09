library cozmo_image;

import 'dart:typed_data';

class CozmoImage {
  static const int WIDTH = 128;
  static const int HEIGHT = 64;
  static const int SIZE = WIDTH * HEIGHT;

  final Uint8List _pixels;

  CozmoImage() : _pixels = Uint8List(SIZE) {
    clear();
  }

  /// Очистить экран (залить черным)
  void clear() {
    for (int i = 0; i < SIZE; i++) {
      _pixels[i] = 0;
    }
  }

  /// Залить белым
  void fill() {
    for (int i = 0; i < SIZE; i++) {
      _pixels[i] = 255;
    }
  }

  /// Установить пиксель
  /// [x]: 0-127
  /// [y]: 0-63
  /// [brightness]: 0 (черный) - 255 (белый)
  void setPixel(int x, int y, int brightness) {
    if (x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT) return;
    _pixels[y * WIDTH + x] = brightness.clamp(0, 255);
  }

  /// Нарисовать линию (Алгоритм Брезенхема)
  void drawLine(int x0, int y0, int x1, int y1, [int brightness = 255]) {
    int dx = (x1 - x0).abs();
    int dy = (y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;

    while (true) {
      setPixel(x0, y0, brightness);
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

  /// Нарисовать прямоугольник
  void drawRect(int x, int y, int w, int h, [int brightness = 255]) {
    drawLine(x, y, x + w, y, brightness);         // Верх
    drawLine(x, y + h, x + w, y + h, brightness); // Низ
    drawLine(x, y, x, y + h, brightness);         // Лево
    drawLine(x + w, y, x + w, y + h, brightness); // Право
  }

  /// Нарисовать крест (для теста)
  void drawX() {
    drawLine(0, 0, WIDTH - 1, HEIGHT - 1);
    drawLine(0, HEIGHT - 1, WIDTH - 1, 0);
  }

  /// RLE Кодирование (Run-Length Encoding)
  /// Превращает 8192 байта пикселей в сжатый массив.
  /// Формат: [Количество, Значение, Количество, Значение...]
  List<int> encode() {
    List<int> rleData = [];
    
    if (_pixels.isEmpty) return rleData;

    int i = 0;
    while (i < _pixels.length) {
      int value = _pixels[i];
      int count = 1;

      // Считаем, сколько одинаковых пикселей идет подряд
      // Максимум 255, так как count должен влезть в 1 байт
      while ((i + count) < _pixels.length && 
             _pixels[i + count] == value && 
             count < 255) {
        count++;
      }

      // Записываем пару: [Сколько, Чего]
      rleData.add(count);
      rleData.add(value);

      i += count;
    }

    return rleData;
  }
  
  /// Подготавливает полный пакет для команды 0x97 (DisplayImage)
  /// Добавляет заголовок чанка.
  /// ВНИМАНИЕ: Работает только если сжатая картинка < 900 байт!
  List<int> getCommandPayload() {
    final rle = encode();
    
    // Проверка на размер (чтобы влезло в один UDP пакет)
    if (rle.length > 900) {
      print('⚠️ ВНИМАНИЕ: Картинка слишком сложная (${rle.length} байт)!');
      print('   Попробуйте уменьшить количество деталей (больше черного фона).');
      // В реальном проекте тут нужен Chunking, но пока вернем как есть,
      // надеясь, что пролезет или обрежется.
    }

    // Структура заголовка DisplayImage (упрощенная для 1 чанка):
    // [Flags (1 byte)] - обычно 0x01 (Last Chunk) или 0x00
    // [ImageID (1 byte)] - произвольный ID
    // [ChunkID (1 byte)] - 0
    // ... RLE Data ...
    
    // В pycozmo часто используется формат без заголовков чанков для простых картинок,
    // но самый надежный способ для "однопакетной" картинки:
    
    // Байт 0: 0x3f (Специальный флаг "Single Chunk Compressed")
    // Далее: RLE данные
    
    return [0x3f, ...rle];
  }
}