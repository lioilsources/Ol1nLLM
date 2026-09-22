import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/constants/theme.dart';

/// Shorter than this the server rejects the sample (`MIN_SOURCE_SECONDS`
/// in AiStack `vibe/sample.py`): not enough for tempo nor for the LM.
const kMinRecordSeconds = 5;

/// The server only ever uses the loudest 60 s window (`MAX_SRC_SECONDS`),
/// so recording longer would just be a bigger upload.
const kMaxRecordSeconds = 60;

/// Records a sample from the microphone — music playing around the phone
/// (radio, a speaker) — and pops with the path of the finished .m4a, or null
/// when cancelled. The caller copies the file, like a picked one.
class SampleRecorderSheet extends StatefulWidget {
  const SampleRecorderSheet({super.key});

  @override
  State<SampleRecorderSheet> createState() => _SampleRecorderSheetState();
}

class _SampleRecorderSheetState extends State<SampleRecorderSheet> {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _ticker;
  final _clock = Stopwatch();
  bool _recording = false;
  bool _finishing = false;
  String? _error;

  /// 0–1, smoothed so the meter doesn't flicker.
  double _level = 0;

  int get _seconds => _clock.elapsed.inSeconds;

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    // Sheet swiped away mid-recording: throw the file away.
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await _recorder.hasPermission()) {
        setState(
          () => _error =
              'Bez přístupu k mikrofonu to nejde — povol ho v Nastavení.',
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rec-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        // Music, not speech: the voice processing (AGC, echo cancel, noise
        // suppression) would pump the loudness and eat the instruments the
        // server is supposed to hear. All three default to off; spelled out
        // so nobody "fixes" it for a voice use case.
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 192000,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: path,
      );
      _clock
        ..reset()
        ..start();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
            // dBFS → 0–1 over a −50…0 dB range.
            final v = ((a.current + 50) / 50).clamp(0.0, 1.0);
            if (mounted) setState(() => _level = _level * 0.6 + v * 0.4);
          });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (_seconds >= kMaxRecordSeconds) {
          _stop();
        } else {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    } catch (e) {
      setState(() => _error = 'Nahrávání se nepodařilo spustit: $e');
    }
  }

  Future<void> _stop() async {
    if (_finishing || !_recording) return;
    _finishing = true;
    _ticker?.cancel();
    await _ampSub?.cancel();
    _clock.stop();
    try {
      final path = await _recorder.stop();
      _recording = false;
      if (!mounted) return;
      if (path == null || !File(path).existsSync()) {
        setState(() {
          _error = 'Nahrávka se neuložila.';
          _finishing = false;
        });
        return;
      }
      Navigator.of(context).pop(path);
    } catch (e) {
      _recording = false;
      if (mounted) {
        setState(() {
          _error = 'Nahrávku se nepodařilo dokončit: $e';
          _finishing = false;
        });
      }
    }
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final canStop = _recording && _seconds >= kMinRecordSeconds;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nahrát z okolí',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _recording
                  ? (canStop
                        ? 'Stačí 15–30 s. Po minutě se nahrávání zastaví samo.'
                        : 'Nahrávám… zastavit jde po $kMinRecordSeconds s.')
                  : 'Podrž telefon u reproduktoru (rádio, repro) a klepni na '
                        'mikrofon. Studio pak z nahrávky vyčte žánr, tempo '
                        'a náladu jako u souboru.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _LevelMeter(level: _recording ? _level : 0),
            const SizedBox(height: 12),
            Text(
              '${_fmt(_seconds)} / ${_fmt(kMaxRecordSeconds)}',
              style: TextStyle(
                color: _recording
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 72,
              height: 72,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: _recording
                      ? Colors.red[700]
                      : AppTheme.accent,
                  disabledBackgroundColor: Colors.red[900],
                ),
                onPressed: _finishing
                    ? null
                    : !_recording
                    ? _start
                    : canStop
                    ? _stop
                    : null,
                child: _finishing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _recording ? Icons.stop_rounded : Icons.mic,
                        size: 34,
                        color: Colors.white,
                      ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red[300]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row of bars that fills with the input level — enough to see that the
/// phone actually hears the music and isn't clipping.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  static const _bars = 24;

  @override
  Widget build(BuildContext context) {
    final lit = (level * _bars).round();
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _bars; i++)
            Container(
              width: 6,
              height: 8 + 24 * math.sin((i + 1) / _bars * math.pi / 2),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i < lit
                    ? (i >= _bars - 2 ? Colors.orange : AppTheme.accent)
                    : AppTheme.surfaceAlt,
              ),
            ),
        ],
      ),
    );
  }
}
