import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

class WaveformVisualizer extends StatefulWidget {
  final double height;
  final int barCount;
  final Stream<double>? amplitudeStream;

  const WaveformVisualizer({
    super.key,
    this.height = 128,
    this.barCount = 40,
    this.amplitudeStream,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer> {
  List<double> _amplitudes = [];
  StreamSubscription<double>? _subscription;

  @override
  void initState() {
    super.initState();
    _amplitudes = List.filled(widget.barCount, 0.1);
    
    if (widget.amplitudeStream != null) {
      _subscription = widget.amplitudeStream!.listen((amplitude) {
        setState(() {
          _amplitudes.removeAt(0);
          _amplitudes.add(amplitude);
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amplitudeStream != widget.amplitudeStream) {
      _subscription?.cancel();
      if (widget.amplitudeStream != null) {
        _subscription = widget.amplitudeStream!.listen((amplitude) {
          setState(() {
            _amplitudes.removeAt(0);
            _amplitudes.add(amplitude);
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          if (widget.amplitudeStream != null) {
            return _RealTimeWaveformBar(
              targetAmplitude: _amplitudes[index],
              maxHeight: widget.height,
            );
          } else {
            return _RandomWaveformBar(
              index: index,
              maxHeight: widget.height,
              barCount: widget.barCount,
            );
          }
        }),
      ),
    );
  }
}

class _RealTimeWaveformBar extends StatelessWidget {
  final double targetAmplitude;
  final double maxHeight;

  const _RealTimeWaveformBar({
    required this.targetAmplitude,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final barWidth = 2.5;
    final gap = 1.5;

    // Use AnimatedContainer to smoothly transition between amplitudes
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap / 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: barWidth,
        height: (maxHeight * targetAmplitude).clamp(maxHeight * 0.1, maxHeight),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(2),
          ),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              context.colors.primary.withValues(alpha: 0.8),
              context.colors.primary,
            ],
          ),
        ),
      ),
    );
  }
}

class _RandomWaveformBar extends StatelessWidget {
  final int index;
  final double maxHeight;
  final int barCount;

  const _RandomWaveformBar({
    required this.index,
    required this.maxHeight,
    required this.barCount,
  });

  @override
  Widget build(BuildContext context) {
    final random = Random(index * 42 + 7);
    final initialHeight = 0.1 + random.nextDouble() * 0.9;
    final targetHeight = 0.1 + random.nextDouble() * 0.9;
    final barWidth = 2.5;
    final gap = 1.5;
    final duration = 600 + random.nextInt(800);
    final delay = random.nextInt(500);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap / 2),
      child: Container(
        width: barWidth,
        height: maxHeight * initialHeight,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(2),
          ),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              context.colors.primary.withValues(alpha: 0.8),
              context.colors.primary,
            ],
          ),
        ),
      )
          .animate(
            onPlay: (controller) => controller.repeat(reverse: true),
          )
          .custom(
            delay: Duration(milliseconds: delay),
            duration: Duration(milliseconds: duration),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              final animatedHeight = maxHeight *
                  (initialHeight + (targetHeight - initialHeight) * value);
              return Container(
                width: barWidth,
                height: animatedHeight.clamp(maxHeight * 0.1, maxHeight),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      context.colors.primary.withValues(alpha: 0.8),
                      context.colors.primary,
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}
