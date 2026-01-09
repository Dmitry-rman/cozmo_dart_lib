library cozmo_audio;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'cozmo_client.dart';
import 'cozmo_utils.dart';
import 'cozmo_anim_controller.dart';

class CozmoAudio {
  final CozmoClient _client;
  final CozmoAnimController _animController;
  
  static const int _SAMPLE_RATE = 22050;
  static const int _PACKET_SAMPLES = 744;

  CozmoAudio(this._client, this._animController);

  /// Воспроизводит WAV файл с диска
  Future<void> playWav(String path, {void Function(double)? onProgress}) async {
    if (!_client.isConnected) throw CozmoException('Not connected');
    final file = File(path);
    if (!await file.exists()) throw CozmoException('File not found');

    print('🔊 Audio File: $path');
    final audioData = await _loadWavFile(path);
    final packets = _convertAudioToPackets(audioData);
    
    await _streamPackets(packets, onProgress: onProgress);
  }

  /// Воспроизводит сырые PCM данные (16-bit, 22050Hz, Mono)
  /// Полезно для TTS (OpenAI, Google и т.д.)
  Future<void> playPCMData(List<int> pcmData, {void Function(double)? onProgress}) async {
    if (!_client.isConnected) throw CozmoException('Not connected');

    print('🔊 Audio PCM: ${pcmData.length} bytes');
    final packets = _convertAudioToPackets(Uint8List.fromList(pcmData));

    await _streamPackets(packets, onProgress: onProgress);
  }

  /// Воспроизводит PCM данные с автоматической конвертацией частоты
  /// Поддерживает 16kHz, 24kHz, 44.1kHz, 48kHz → автоматически конвертирует в 22.05kHz
  Future<void> playPCMAudio(Uint8List pcmData, {int sampleRate = 24000}) async {
    if (!_client.isConnected) throw CozmoException('Not connected');

    print('🔊 Audio PCM: ${pcmData.length} bytes @ ${sampleRate}Hz');

    // Конвертируем частоту если нужно
    Uint8List convertedData;
    if (sampleRate != _SAMPLE_RATE) {
      convertedData = _resamplePCM(pcmData, sampleRate, _SAMPLE_RATE);
      print('🔄 Resampled: ${pcmData.length} → ${convertedData.length} bytes');
    } else {
      convertedData = pcmData;
    }

    final packets = _convertAudioToPackets(convertedData);
    await _streamPackets(packets);
  }

  /// Общая логика потоковой отправки (Skip-to-Live)
  Future<void> _streamPackets(List<List<int>> packets, {void Function(double)? onProgress}) async {
    // 1. ЗАХВАТЫВАЕМ КОНТРОЛЬ (Контроллер перестает слать Silence)
    _animController.setAudioBusy(true);
    print('📦 Packets: ${packets.length}');

    _client.sendCommand(CozmoCmd.enableAnimState, [1]);

    final packetDurationUs = (_PACKET_SAMPLES * 1000000 / _SAMPLE_RATE).round();
    final startTime = DateTime.now().microsecondsSinceEpoch;
    int skipped = 0;

    print('⏱️ Starting packet stream: ${_PACKET_SAMPLES} samples/packet, ${packetDurationUs}μs/packet');

    for (int i = 0; i < packets.length; i++) {
      final now = DateTime.now().microsecondsSinceEpoch;
      final targetTime = startTime + (i * packetDurationUs);
      final diff = targetTime - now;

      // Skip-to-Live: Если отстаем больше чем на 66мс (2 пакета)
      if (diff < -66000) {
        skipped++;
        continue;
      }

      // Backpressure: Ждем, если очередь отправки переполнена (как в старом коде - 50)
      while (_client.outboundQueueLength > 50) {
        await Future.delayed(const Duration(milliseconds: 5));
      }

      // ВАЖНО: Отправляем ПРЯМО В ОЧЕРЕДЬ (пакеты УЖЕ содержат commandID!)
      _client.sendRawPacket(packets[i]);

      if (i == 0) {
        print('🚵 First packet sent! Queue length: ${_client.outboundQueueLength}');
      }

      if (onProgress != null && i % 10 == 0) {
        onProgress((i + 1) / packets.length);
      }

      // Точное ожидание
      if (diff > 0) await Future.delayed(Duration(microseconds: diff));
    }

    print('✅ Audio streaming complete. Skipped: $skipped packets');

    // Ждем пока очередь И отправленные пакеты опустеют (ВАЖНО! как в старом коде)
    print('⏳ Waiting for all packets to be sent and acknowledged...');
    while (_client.outboundQueueLength > 0 || _client.inflightPacketsCount > 0) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print('✅ All packets sent and acknowledged');

    // Финализация
    print('🏁 Sending audio finalization commands...');
    _client.sendCommand(CozmoCmd.outputSilence, []);
    await Future.delayed(const Duration(milliseconds: 50));
    _client.sendCommand(CozmoCmd.endAnimation, []);

    // ВОЗВРАЩАЕМ КОНТРОЛЬ
    _animController.setAudioBusy(false);
    print('✅ Audio finalized');
  }

  // --- UTILS ---

  Future<Uint8List> _loadWavFile(String path) async {
     final bytes = await File(path).readAsBytes();
     int offset = 12;
     while (offset < bytes.length) {
       if (bytes[offset] == 0x64 && bytes[offset+1] == 0x61 && bytes[offset+2] == 0x74 && bytes[offset+3] == 0x61) {
          final size = _byteDataGetUint32(bytes, offset + 4);
          return bytes.sublist(offset + 8, offset + 8 + size);
       }
       final size = _byteDataGetUint32(bytes, offset + 4);
       offset += 8 + size;
     }
     throw CozmoException('No data chunk');
  }

  List<List<int>> _convertAudioToPackets(Uint8List data) {
    final packets = <List<int>>[];
    for (int i = 0; i < data.length; i += AUDIO_PACKET_SAMPLES * 2) {
      int len = (AUDIO_PACKET_SAMPLES * 2).clamp(0, data.length - i);
      var chunk = data.sublist(i, i + len);
      if (len < AUDIO_PACKET_SAMPLES * 2) {
         final p = Uint8List(AUDIO_PACKET_SAMPLES * 2); p.setAll(0, chunk); chunk = p;
      }
      // ВАЖНО: Создаем ПОЛНЫЙ пакет [commandID + uLawData]
      final ulawData = _convertToULaw(chunk);
      final packet = Uint8List(1 + ulawData.length);
      packet[0] = CozmoCmd.outputAudio; // 0x8e
      packet.setAll(1, ulawData);
      packets.add(packet);
    }
    print('📦 Created ${packets.length} packets, each ${packets[0].length} bytes (0x${packets[0][0].toRadixString(16)} + ${packets[0].length - 1} bytes uLaw)');
    return packets;
  }

  Uint8List _convertToULaw(Uint8List pcm) {
    final u = Uint8List(AUDIO_PACKET_SAMPLES);
    for (int i = 0; i < AUDIO_PACKET_SAMPLES; i++) {
      int sample = (pcm[i*2+1] << 8) | pcm[i*2];
      if (sample > 32767) sample -= 65536;
      u[i] = _uLawEncode(sample);
    }
    return u;
  }

  int _uLawEncode(int sample) {
    const int MAX = 0x7FFF; const int BIAS = 132; int mask = 0x4000; int pos = 14; int sign = 0;
    if (sample < 0) { sample = -sample; sign = 0x80; }
    sample += BIAS; if (sample > MAX) sample = MAX;
    while ((sample & mask) != mask && pos >= 7) { mask >>= 1; pos--; }
    int lsb = (sample >> (pos - 4)) & 0x0f;
    return -(~(sign | ((pos - 7) << 4) | lsb));
  }

  int _byteDataGetUint32(Uint8List b, int o) => b[o] | (b[o+1] << 8) | (b[o+2] << 16) | (b[o+3] << 24);

  /// Ресемплинг PCM данных (линейная интерполяция)
  /// Конвертирует из любой частоты в 22050Hz
  Uint8List _resamplePCM(Uint8List inputData, int inputRate, int outputRate) {
    // Конвертируем байты в сэмплы (16-bit signed little-endian)
    final inputSamples = _bytesToInt16List(inputData);

    // Вычисляем коэффициент ресемплинга
    final ratio = inputRate / outputRate;
    final outputLength = (inputSamples.length / ratio).round();
    final outputSamples = Int16List(outputLength);

    // Линейная интерполяция
    for (int i = 0; i < outputLength; i++) {
      final pos = i * ratio;
      final index = pos.floor();
      final frac = pos - index;

      if (index + 1 < inputSamples.length) {
        final sample1 = inputSamples[index];
        final sample2 = inputSamples[index + 1];
        outputSamples[i] = (sample1 + (sample2 - sample1) * frac).clamp(-32768, 32767).toInt();
      } else {
        outputSamples[i] = inputSamples[inputSamples.length - 1];
      }
    }

    // Конвертируем обратно в байты
    return _int16ListToBytes(outputSamples);
  }

  /// Конвертирует байты в Int16 список
  Int16List _bytesToInt16List(Uint8List bytes) {
    final samples = Int16List(bytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = (bytes[i * 2] | (bytes[i * 2 + 1] << 8));
      if (samples[i] >= 32768) samples[i] -= 65536;
    }
    return samples;
  }

  /// Конвертирует Int16 список в байты
  Uint8List _int16ListToBytes(Int16List samples) {
    final bytes = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      int sample = samples[i];
      if (sample < 0) sample += 65536;
      bytes[i * 2] = sample & 0xFF;
      bytes[i * 2 + 1] = (sample >> 8) & 0xFF;
    }
    return bytes;
  }
}