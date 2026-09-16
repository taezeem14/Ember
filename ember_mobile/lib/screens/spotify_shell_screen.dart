import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/ember_theme.dart';
import '../widgets/mini_player.dart';
import 'tabs/spotify_home_tab.dart';
import 'tabs/spotify_search_tab.dart';
import 'tabs/spotify_library_tab.dart';

class SpotifyShellScreen extends StatefulWidget {
  const SpotifyShellScreen({super.key});

  @override
  State<SpotifyShellScreen> createState() => _SpotifyShellScreenState();
}

class _SpotifyShellScreenState extends State<SpotifyShellScreen> {
  int _currentIndex = 0;

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmberColors.obsidianBase,
      body: Stack(
        children: [
          // 1. Tab Views
          IndexedStack(
            index: _currentIndex,
            children: [
              SpotifyHomeTab(
                onOpenSearch: () => _onTabTapped(1),
                onOpenLibrary: () => _onTabTapped(2),
              ),
              const SpotifySearchTab(),
              const SpotifyLibraryTab(),
            ],
          ),

          // 2. Docked Mini Player & Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Floating MiniPlayer docked above nav bar
                const MiniPlayer(),

                // Spotify Bottom Navigation Bar in Electric Blue
                Container(
                  decoration: BoxDecoration(
                    color: EmberColors.obsidianBase.withValues(alpha: 0.98),
                    border: Border(
                      top: BorderSide(
                        color: EmberColors.glassBorder.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _BottomNavItem(
                            icon: FontAwesomeIcons.house,
                            activeIcon: FontAwesomeIcons.house,
                            label: 'Home',
                            isSelected: _currentIndex == 0,
                            onTap: () => _onTabTapped(0),
                          ),
                          _BottomNavItem(
                            icon: FontAwesomeIcons.magnifyingGlass,
                            activeIcon: FontAwesomeIcons.magnifyingGlass,
                            label: 'Search',
                            isSelected: _currentIndex == 1,
                            onTap: () => _onTabTapped(1),
                          ),
                          _BottomNavItem(
                            icon: FontAwesomeIcons.linesLeaning,
                            activeIcon: FontAwesomeIcons.linesLeaning,
                            label: 'Your Library',
                            isSelected: _currentIndex == 2,
                            onTap: () => _onTabTapped(2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final FaIconData icon;
  final FaIconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? EmberColors.electricBlue : EmberColors.textSecondary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              isSelected ? activeIcon : icon,
              size: 20,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
