library cozmo_image_encoder;

import 'dart:typed_data';

class CozmoImageEncoder {
  static const int WIDTH = 128;
  static const int HEIGHT = 32;

  final List<int> _pixels;

  CozmoImageEncoder(this._pixels) {
    if (_pixels.length < WIDTH * HEIGHT) {
      throw ArgumentError('Image must be at least ${WIDTH}x$HEIGHT pixels');
    }
  }

  Uint8List encode() {
    List<int> finalBuffer = [];
    List<int> prevColData = [];
    int skipCounter = 0;
    int repeatCounter = 0;

    for (int x = 0; x < WIDTH; x++) {
      List<int> colData = _encodeColumnPixels(x);

      if (colData.isEmpty) {
        // Столбец пустой -> SKIP
        _flushRepeat(finalBuffer, repeatCounter); 
        repeatCounter = 0;
        
        skipCounter++;
        prevColData = []; 
      } else {
        // Столбец с данными -> DRAW
        _flushSkip(finalBuffer, skipCounter); 
        skipCounter = 0;

        // БЕЗОПАСНЫЙ РЕЖИМ: Отключаем Repeat для непустых столбцов.
        // Мы всегда считаем столбцы "разными", даже если они одинаковые.
        // Это увеличивает размер пакета, но предотвращает краши робота из-за багов Repeat.
        bool isSame = false; // _listEquals(colData, prevColData); <--- ОТКЛЮЧЕНО

        if (isSame) {
          repeatCounter++;
        } else {
          _flushRepeat(finalBuffer, repeatCounter); 
          repeatCounter = 0;
          
          finalBuffer.addAll(colData);
          prevColData = colData;
        }
      }
    }
    
    _flushRepeat(finalBuffer, repeatCounter);
    _flushSkip(finalBuffer, skipCounter);

    return Uint8List.fromList(finalBuffer);
  }

  List<int> _encodeColumnPixels(int x) {
    List<int> res = [];
    int y = 0;
    bool hasWhite = false;

    for(int i=0; i<HEIGHT; i++) {
      if (_getPixel(x, i) > 0) {
        hasWhite = true;
        break;
      }
    }
    if (!hasWhite) return []; 

    while (y < HEIGHT) {
      int color = _getPixel(x, y) > 0 ? 1 : 0;
      int count = 1;
      
      while (y + count < HEIGHT && (_getPixel(x, y + count) > 0 ? 1 : 0) == color) {
        count++;
      }

      int remaining = count;
      while (remaining > 0) {
        int chunk = remaining > 31 ? 31 : remaining;
        
        int cmd;
        if (chunk <= 15) {
          cmd = 0x80 | ((chunk << 2) & 0x3C) | (color & 0x01);
        } else {
          cmd = 0xC0 | (((chunk - 16) << 2) & 0x3C) | (color & 0x01);
        }
        
        res.add(cmd);
        remaining -= chunk;
      }

      y += count;
    }
    return res;
  }

  void _flushSkip(List<int> buf, int count) {
    while (count > 0) {
      int chunk = count > 64 ? 64 : count;
      buf.add(chunk - 1); 
      count -= chunk;
    }
  }

  void _flushRepeat(List<int> buf, int count) {
    while (count > 0) {
      int chunk = count > 64 ? 64 : count;
      buf.add(0x40 | (chunk - 1)); 
      count -= chunk;
    }
  }

  int _getPixel(int x, int y) {
    return _pixels[y * WIDTH + x];
  }

  // Метод оставлен, но не используется в безопасном режиме
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty && b.isEmpty) return true;
    if (a.isEmpty || b.isEmpty) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}