import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';

class SoundShapingSheet extends StatelessWidget {
  const SoundShapingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SoundShapingSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final equalizer = player.audioHandler.equalizer;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: EmberColors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: EmberColors.primaryAmber.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const FaIcon(FontAwesomeIcons.sliders, size: 16, color: EmberColors.primaryAmber),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sound Shaping & EQ',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: EmberColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Analog Warmth & Multi-Band DSP',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: EmberColors.textMuted,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Switch(
                    value: player.eqEnabled,
                    activeTrackColor: EmberColors.primaryAmber,
                    onChanged: (val) => player.setEqualizerEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Presets
              const Text('ACOUSTIC PROFILES', style: TextStyle(color: EmberColors.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in ['Warm Tape', 'Lo-Fi', 'Bass Boost', 'Vocal Air', 'Acoustic', 'Flat'])
                    ChoiceChip(
                      label: Text(p),
                      selected: player.eqPreset == p,
                      selectedColor: EmberColors.primaryAmber,
                      labelStyle: TextStyle(
                        color: player.eqPreset == p ? EmberColors.obsidianBase : EmberColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      backgroundColor: EmberColors.surfaceContainerLow,
                      onSelected: (_) => player.setEqualizerPreset(p),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Bass Boost / Sub-Warmth Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Hearth Bass Boost', style: TextStyle(color: EmberColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${(player.bassBoost * 100).toInt()}%', style: const TextStyle(color: EmberColors.primaryAmber, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: EmberColors.primaryAmber,
                  thumbColor: EmberColors.primaryAmberHi,
                  inactiveTrackColor: EmberColors.surfaceContainerHigh,
                ),
                child: Slider(
                  value: player.bassBoost.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) => player.setBassBoost(val),
                ),
              ),

              const SizedBox(height: 16),
              // Multi-Band Frequency Sliders
              const Text('FREQUENCY BANDS', style: TextStyle(color: EmberColors.textMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              FutureBuilder<AndroidEqualizerParameters>(
                future: equalizer.parameters,
                builder: (context, snapshot) {
                  final params = snapshot.data;
                  if (params == null || params.bands.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      alignment: Alignment.center,
                      child: const Text('Hardware equalizer ready on playback', style: TextStyle(color: EmberColors.textMuted, fontSize: 12)),
                    );
                  }

                  return Column(
                    children: [
                      for (int i = 0; i < params.bands.length; i++)
                        _BandSlider(
                          band: params.bands[i],
                          minDecibels: params.minDecibels,
                          maxDecibels: params.maxDecibels,
                          onChanged: (gain) => player.setBandGain(i, gain),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandSlider extends StatefulWidget {
  final AndroidEqualizerBand band;
  final double minDecibels;
  final double maxDecibels;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.band,
    required this.minDecibels,
    required this.maxDecibels,
    required this.onChanged,
  });

  @override
  State<_BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<_BandSlider> {
  late double _gain;

  @override
  void initState() {
    super.initState();
    _gain = widget.band.gain;
  }

  @override
  Widget build(BuildContext context) {
    final freq = widget.band.centerFrequency;
    final freqStr = freq >= 1000 ? '${(freq / 1000).toStringAsFixed(1)} kHz' : '${freq.round()} Hz';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 65,
            child: Text(
              freqStr,
              style: const TextStyle(color: EmberColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: EmberColors.primaryAmber,
                thumbColor: EmberColors.textPrimary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                inactiveTrackColor: EmberColors.surfaceContainerHigh,
              ),
              child: Slider(
                value: _gain.clamp(widget.minDecibels, widget.maxDecibels),
                min: widget.minDecibels,
                max: widget.maxDecibels,
                onChanged: (val) {
                  setState(() => _gain = val);
                  widget.onChanged(val);
                },
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${_gain >= 0 ? '+' : ''}${_gain.toStringAsFixed(1)} dB',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: _gain.abs() > 0.5 ? EmberColors.primaryAmber : EmberColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
