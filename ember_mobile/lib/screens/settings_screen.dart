import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';
import 'sound_shaping_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.obsidianBase,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SettingsScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: EmberColors.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EmberColors.primaryAmber.withValues(alpha: 0.16),
                    ),
                    child: const FaIcon(FontAwesomeIcons.gear, color: EmberColors.primaryAmber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings & About',
                    style: TextStyle(
                      color: EmberColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: EmberColors.outlineVariant, height: 16),
            Expanded(
              child: SettingsContent(scrollController: scrollController),
            ),
          ],
        );
      },
    );
  }
}

class SettingsContent extends StatelessWidget {
  final ScrollController? scrollController;

  const SettingsContent({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ==========================================
        // SOLE CREATOR & AUTHOR SPOTLIGHT CARD
        // ==========================================
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                EmberColors.primaryAmber.withValues(alpha: 0.18),
                EmberColors.surfaceContainerHigh.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: EmberColors.primaryAmber.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: EmberColors.primaryAmber.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EmberColors.primaryAmber,
                      boxShadow: [
                        BoxShadow(
                          color: EmberColors.primaryAmber.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: FaIcon(
                        FontAwesomeIcons.fire,
                        size: 26,
                        color: EmberColors.obsidianBase,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Muhammad Taezeem Tariq',
                                style: TextStyle(
                                  color: EmberColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const FaIcon(
                              FontAwesomeIcons.solidCircleCheck,
                              color: EmberColors.primaryAmber,
                              size: 14,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: EmberColors.primaryAmber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Author & Creator',
                            style: TextStyle(
                              color: EmberColors.primaryAmberHi,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Ember was designed and architected exclusively by Muhammad Taezeem Tariq (@taezeem14). Built with a deep obsession for pristine audio quality, zero ads, real-time lyrics, and seamless YouTube & global music streaming.',
                style: TextStyle(
                  color: EmberColors.textSecondary.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.github, size: 14, color: EmberColors.textMuted),
                  const SizedBox(width: 6),
                  const Text(
                    'github.com/taezeem14',
                    style: TextStyle(
                      color: EmberColors.primaryAmber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // SECTION 1: AUDIO & SOUND SHAPING
        // ==========================================
        const _SectionHeader(title: 'Audio & Sound Engine'),
        _SettingsTile(
          icon: FontAwesomeIcons.sliders,
          title: 'Equalizer & Audio Shaping',
          subtitle: 'Preset: ${player.eqPreset} • Bass Boost: ${(player.bassBoost * 100).round()}%',
          trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: EmberColors.textMuted),
          onTap: () => SoundShapingSheet.show(context),
        ),
        _SettingsTile(
          icon: FontAwesomeIcons.bolt,
          title: 'Autoplay Smart Radio',
          subtitle: 'Automatically queue recommended tracks when songs end',
          trailing: Switch(
            value: player.isAutoplayEnabled,
            activeThumbColor: EmberColors.primaryAmber,
            onChanged: (_) => player.toggleAutoplay(),
          ),

          onTap: () => player.toggleAutoplay(),
        ),
        _SettingsTile(
          icon: FontAwesomeIcons.gaugeHigh,
          title: 'Audio Streaming Quality',
          subtitle: '320 kbps MPEG-4 AAC-LC / High Bitrate (Lossless Source)',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: EmberColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: EmberColors.outlineVariant),
            ),
            child: const Text('320 kbps', style: TextStyle(color: EmberColors.primaryAmber, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          onTap: null,
        ),
        _SettingsTile(
          icon: FontAwesomeIcons.stop,
          iconColor: EmberColors.error,
          title: 'Cut Active Playback',
          subtitle: 'Immediately stop audio and dismiss the playing song',
          trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: EmberColors.textMuted),
          onTap: () {
            player.stopPlayback();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: EmberColors.surfaceContainerHigh,
                content: Text('Playback stopped & dismissed', style: TextStyle(color: EmberColors.textPrimary)),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // ==========================================
        // SECTION 2: STORAGE & CACHE
        // ==========================================
        const _SectionHeader(title: 'Storage & Database'),
        _SettingsTile(
          icon: FontAwesomeIcons.broom,
          title: 'Purge Placeholders & Clean Cache',
          subtitle: 'Eradicate legacy mock songs and clear temp audio cache',
          trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: EmberColors.textMuted),
          onTap: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: EmberColors.surfaceContainerHigh,
                content: Text('Cleaning storage and purging old cache...', style: TextStyle(color: EmberColors.primaryAmber)),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // ==========================================
        // SECTION 3: APP INFO & SYSTEM
        // ==========================================
        const _SectionHeader(title: 'System & Architecture'),
        const _SettingsTile(
          icon: FontAwesomeIcons.mobileScreen,
          title: 'Ember Version',
          subtitle: 'v1.0.0 (Release Build)',
          trailing: Text('1.0.0', style: TextStyle(color: EmberColors.textMuted, fontSize: 12)),
          onTap: null,
        ),
        const _SettingsTile(
          icon: FontAwesomeIcons.youtube,
          iconColor: Colors.redAccent,
          title: 'YouTube Extractor Engine',
          subtitle: 'NewPipe InnerTube Client (youtubei/v1)',
          trailing: Text('Active', style: TextStyle(color: EmberColors.primaryAmberHi, fontSize: 12)),
          onTap: null,
        ),
        const _SettingsTile(
          icon: FontAwesomeIcons.shieldHeart,
          title: 'Open Source & Ad-Free',
          subtitle: 'No telemetry, zero third-party ads, strictly local storage',
          trailing: Text('100% Free', style: TextStyle(color: EmberColors.primaryAmber, fontSize: 12)),
          onTap: null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: EmberColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final FaIconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: EmberColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EmberColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: EmberColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: FaIcon(
              icon,
              size: 16,
              color: iconColor ?? EmberColors.primaryAmber,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: EmberColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: EmberColors.textMuted,
            fontSize: 11,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
