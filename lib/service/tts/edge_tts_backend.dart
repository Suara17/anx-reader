import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Microsoft Edge online neural TTS provider.
///
/// Uses the same free ReadAloud WebSocket endpoint that the Edge browser
/// exposes. No API key is required. Voices such as 晓晓 / 云希 / 云扬 come from
/// Microsoft's high quality neural voice bank.
class EdgeTtsProvider extends TtsServiceProvider {
  static final EdgeTtsProvider _instance = EdgeTtsProvider._internal();

  factory EdgeTtsProvider() {
    return _instance;
  }

  EdgeTtsProvider._internal();

  static const String _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _chromiumVersion = '143.0.3650.75';
  static const String _chromiumMajor = '143';
  static const String _secMsGecVersion = '1-$_chromiumVersion';
  static const String _wssUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const String _defaultVoice = 'zh-CN-XiaoxiaoNeural';
  static const String _outputFormat = 'audio-24khz-48kbitrate-mono-mp3';

  @override
  TtsService get service => TtsService.edge;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateEdgeTts;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).settingsNarrateEdgeTts,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateEdgeHelpText,
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    if (config.isEmpty) {
      return {'voice': _defaultVoice};
    }
    return {
      'voice': config['voice'] ?? _defaultVoice,
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final String resolvedVoice = resolveVoice(voice);
    await _syncClockSkew();
    final String url = _buildUrl();
    final BytesBuilder audioBuffer = BytesBuilder(copy: false);
    final Completer<Uint8List> completer = Completer<Uint8List>();

    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        url,
        headers: _requestHeaders(),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Edge TTS 连接失败: $e');
    }

    ws.listen(
      (dynamic data) {
        if (data is String) {
          if (data.contains('Path:turn.end')) {
            if (!completer.isCompleted) {
              completer.complete(audioBuffer.takeBytes());
            }
            ws.close();
          }
        } else if (data is List<int>) {
          // Binary frame: first 2 bytes are a big-endian header length.
          if (data.length > 2) {
            final int headerLength = (data[0] << 8) | data[1];
            final int audioStart = headerLength + 2;
            if (data.length > audioStart) {
              audioBuffer.add(data.sublist(audioStart));
            }
          }
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(audioBuffer.takeBytes());
        }
      },
      cancelOnError: true,
    );

    final String timestamp = _nowTimestamp();

    // 1. Send the speech.config frame.
    ws.add(
      'X-Timestamp:$timestamp\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":'
      '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
      '"outputFormat":"$_outputFormat"}}}',
    );

    // 2. Send the SSML frame.
    final String requestId = _randomHex(16);
    final String ssml = _buildSsml(text, resolvedVoice, rate, pitch);
    ws.add(
      'X-RequestId:$requestId\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${timestamp}Z\r\n'
      'Path:ssml\r\n\r\n'
      '$ssml',
    );

    final Uint8List result =
        await completer.future.timeout(const Duration(seconds: 30));

    if (result.isEmpty) {
      throw Exception('Edge TTS 未返回音频数据');
    }
    return result;
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    return const [
      TtsVoice(
          shortName: 'zh-CN-XiaoxiaoNeural',
          name: '晓晓 (温暖亲切 · 推荐)',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-YunxiNeural',
          name: '云希 (阳光沉稳 · 推荐)',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunyangNeural',
          name: '云扬 (专业新闻播音)',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-XiaohanNeural',
          name: '晓涵 (知性温柔)',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaomengNeural',
          name: '晓梦 (生动自然)',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoyiNeural',
          name: '晓伊 (灵动清亮)',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-YunjianNeural',
          name: '云健 (影视解说音)',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunxiaNeural',
          name: '云夏 (少年活力)',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-HK-HiuMaanNeural',
          name: '晓曼 (粤语)',
          locale: 'zh-HK',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-TW-HsiaoChenNeural',
          name: '晓臻 (台湾国语)',
          locale: 'zh-TW',
          gender: 'Female'),
      TtsVoice(
          shortName: 'en-US-JennyNeural',
          name: 'Jenny (自然美语 · 推荐)',
          locale: 'en-US',
          gender: 'Female'),
      TtsVoice(
          shortName: 'en-US-GuyNeural',
          name: 'Guy (稳重男声)',
          locale: 'en-US',
          gender: 'Male'),
      TtsVoice(
          shortName: 'en-US-AriaNeural',
          name: 'Aria (生动女声)',
          locale: 'en-US',
          gender: 'Female'),
      TtsVoice(
          shortName: 'en-GB-SoniaNeural',
          name: 'Sonia (标准英音)',
          locale: 'en-GB',
          gender: 'Female'),
      TtsVoice(
          shortName: 'ja-JP-NanamiNeural',
          name: '七海 (日语女声)',
          locale: 'ja-JP',
          gender: 'Female'),
      TtsVoice(
          shortName: 'ja-JP-KeitaNeural',
          name: '圭太 (日语男声)',
          locale: 'ja-JP',
          gender: 'Male'),
    ];
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final config = getConfig();
    final voice = config['voice']?.toString() ?? '';
    if (voice.isNotEmpty) return voice;
    return _defaultVoice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Cached offset between the local clock and Microsoft's server clock.
  /// A skewed clock makes the `Sec-MS-GEC` token invalid and yields HTTP 403.
  double _clockSkewSeconds = 0.0;
  bool _clockSynced = false;

  /// Fetch the server `Date` header once to correct local clock skew.
  Future<void> _syncClockSkew() async {
    if (_clockSynced) return;
    _clockSynced = true;
    try {
      final http.Response resp = await http.get(
        Uri.parse(
            'https://speech.platform.bing.com/consumer/speech/synthesize/'
            'readaloud/voices/list?trustedclienttoken=$_trustedClientToken'),
        headers: _requestHeaders(),
      ).timeout(const Duration(seconds: 10));
      final String? dateStr = resp.headers['date'];
      if (dateStr != null) {
        final DateTime serverTime = HttpDate.parse(dateStr).toUtc();
        final DateTime clientTime = DateTime.now().toUtc();
        _clockSkewSeconds =
            serverTime.difference(clientTime).inMilliseconds / 1000.0;
      }
    } catch (_) {
      // Best effort only; fall back to the local clock.
      _clockSynced = false;
    }
  }

  String _buildUrl() {
    final String secMsGec = _generateSecMsGec();
    final String connectionId = _randomHex(16);
    return '$_wssUrl'
        '?TrustedClientToken=$_trustedClientToken'
        '\u0026Sec-MS-GEC=$secMsGec'
        '\u0026Sec-MS-GEC-Version=$_secMsGecVersion'
        '\u0026ConnectionId=$connectionId';
  }

  Map<String, String> _requestHeaders() {
    final String muid = _randomHex(16).toUpperCase();
    return {
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': 'muid=$muid;',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/$_chromiumMajor.0.0.0 Safari/537.36 '
              'Edg/$_chromiumMajor.0.0.0',
    };
  }

  /// Computes the `Sec-MS-GEC` anti-abuse token required by the Edge endpoint.
  ///
  /// The value is `SHA256(ticks + TRUSTED_CLIENT_TOKEN)`, where `ticks` is the
  /// current time expressed in 100ns units since 1601, rounded down to the
  /// nearest 5 minutes.
  String _generateSecMsGec() {
    const int winEpochSeconds = 11644473600; // 1601-01-01 -> 1970-01-01
    double ticks =
        DateTime.now().millisecondsSinceEpoch / 1000.0 + winEpochSeconds;
    ticks += _clockSkewSeconds;
    ticks -= ticks % 300; // round down to nearest 5 minutes
    final int ticksInt = (ticks * 10000000).round();
    final String strToHash = '$ticksInt$_trustedClientToken';
    final Digest digest = sha256.convert(ascii.encode(strToHash));
    return digest.toString().toUpperCase();
  }

  String _nowTimestamp() => DateTime.now().toUtc().toIso8601String();

  String _randomHex(int byteLength) {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < byteLength; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _formatRate(double rate) {
    final int percent = ((rate - 1.0) * 100).round();
    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  String _formatPitch(double pitch) {
    final int hz = ((pitch - 1.0) * 50).round();
    return hz >= 0 ? '+${hz}Hz' : '${hz}Hz';
  }

  String _escapeSsml(String text) {
    return text
        .replaceAll('\u0026', '\u0026amp;')
        .replaceAll('\u003C', '\u0026lt;')
        .replaceAll('\u003E', '\u0026gt;')
        .replaceAll('\u0022', '\u0026quot;')
        .replaceAll('\u0027', '\u0026apos;');
  }

  String _buildSsml(String text, String voice, double rate, double pitch) {
    final String rateStr = _formatRate(rate);
    final String pitchStr = _formatPitch(pitch);
    return '\u003Cspeak version=\u00271.0\u0027 '
        'xmlns=\u0027http://www.w3.org/2001/10/synthesis\u0027 '
        'xml:lang=\u0027en-US\u0027\u003E'
        '\u003Cvoice name=\u0027$voice\u0027\u003E'
        '\u003Cprosody pitch=\u0027$pitchStr\u0027 rate=\u0027$rateStr\u0027 '
        'volume=\u0027+0%\u0027\u003E'
        '${_escapeSsml(text)}'
        '\u003C/prosody\u003E'
        '\u003C/voice\u003E'
        '\u003C/speak\u003E';
  }
}
