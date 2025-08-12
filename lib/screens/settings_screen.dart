import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_channel_swift_demo/core/configs/app_routes.dart';

import '../settings/providers/auth_provider.dart';

// =============================================================
// SETTINGS SCREEN (Polished UI)
// Lightweight visual pass that keeps your original layout and
// logic intact. Adds consistent spacing, subtle feedback, and
// helpful comments.
//
// FLOW OVERVIEW
// - Header with app branding
// - User card (initials avatar, name, email, "Profile" chip)
// - Navigation items:
//     * My Profile -> AppRoutes.profileChangeScreen
//     * History    -> AppRoutes.homeScreen (placeholder target)
//     * Change Password -> AppRoutes.passwordChangeScreen
// - Preferences section: Dark Mode (placeholder), Language row
// - Session section with "Log out" button
// - Shows full-screen dim overlay while logging out
//
// INTEGRATION
// - authViewModelProvider for profile/auth state and logout()
// - profileNotifierProvider for up-to-date profile details
//
// UI LAYERS
// - Background image
// - Vertical dark gradient overlay
// - Centered translucent card with subtle border + shadow
//
// SAFETY
// - Uses context.mounted before navigating post-logout
//
// TWEAKS
// - Replace background asset, colors, and opacity to match branding
// - Wire Dark Mode and Language rows to real settings when ready
// =============================================================
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observe auth + profile state
    final auth = ref.watch(authViewModelProvider);
    final profileState = ref.watch(profileNotifierProvider);
    final profile = profileState.profile ?? auth.profile;

    // Derive display data from profile safely
    final displayName = (profile?.displayName ?? 'Guest User').trim();
    final email = profile?.email ?? 'unknown@email.com';

    // Compute "initials" (first letters of up to two name parts)
    final initials = displayName.isNotEmpty
        ? displayName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join()
        : 'GU';

    return Stack(
      children: [
        Scaffold(
          body: Stack(
            children: [
              // -------------------- LAYER 1: BACKGROUND IMAGE --------------------
              Positioned.fill(
                child: Image.asset(
                  'lib/assets/images/login_image.png',
                  fit: BoxFit.cover,
                ),
              ),
              // -------------------- LAYER 2: DARK GRADIENT OVERLAY --------------------
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.65), // slightly softened
                        Colors.black.withOpacity(0.45),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // -------------------- MAIN CONTENT --------------------
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Container(
                      margin:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.48),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ---------- Brand row ----------
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'lib/assets/images/modelCraft.png',
                                height: 30,
                                width: 30,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'WebGIS 3D',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // ---------- User card ----------
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.07),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Initials avatar
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: const Color(0xFF2296F3),
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Name + email
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        email,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Simple "Profile" chip (non-interactive label)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Profile',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ---------- Navigation items ----------
                          _SettingsItem(
                            icon: Icons.person_outline,
                            label: 'My Profile',
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.profileChangeScreen,
                            ),
                          ),
                          _SettingsItem(
                            icon: Icons.history,
                            label: 'History',
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.homeScreen, // Placeholder target
                            ),
                          ),
                          _SettingsItem(
                            icon: Icons.lock_reset,
                            label: 'Change Password',
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.passwordChangeScreen,
                            ),
                          ),

                          const SizedBox(height: 12),
                          _SectionDivider(label: 'Preferences'),

                          // ---------- Preferences ----------
                          _ToggleSetting(
                            icon: Icons.brightness_6_outlined,
                            label: 'Dark Mode',
                            value: true,
                            onChanged: (val) {
                              // Placeholder: hook into theme provider when available
                            },
                          ),
                          // Language row (display only)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 26),
                            child: Row(
                              children: const [
                                Icon(Icons.language, size: 22,
                                    color: Colors.lightBlueAccent),
                                SizedBox(width: 16),
                                Text(
                                  'Language:',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'EN | DE',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),

                          const SizedBox(height: 18),
                          _SectionDivider(label: 'Session'),
                          const SizedBox(height: 12),

                          // ---------- Logout ----------
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: auth.isLoggingOut
                                  ? null
                                  : () async {
                                // Trigger logout via ViewModel, then wipe nav stack
                                await ref
                                    .read(authViewModelProvider.notifier)
                                    .logout();
                                if (context.mounted) {
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    AppRoutes.loginScreen,
                                        (r) => false,
                                  );
                                }
                              },
                              icon: auth.isLoggingOut
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                                  : const Icon(
                                Icons.logout,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                auth.isLoggingOut
                                    ? 'Logging out...'
                                    : 'Log out',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 12),
                                backgroundColor:
                                Colors.blue.withOpacity(0.30),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ---------- Version footer ----------
                          const Text(
                            'App Version 1.0.0',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // -------------------- LOGOUT OVERLAY --------------------
        if (auth.isLoggingOut)
        // Simple full-screen dim overlay with spinner to indicate progress
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}

/* --------------------------- Helper Widgets --------------------------- */

// Thin labeled divider between groups, using semi-transparent lines.
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.white.withOpacity(0.15),
            thickness: 1,
            endIndent: 12,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
          ),
        ),
        Expanded(
          child: Divider(
            color: Colors.white.withOpacity(0.15),
            thickness: 1,
            indent: 12,
          ),
        ),
      ],
    );
  }
}

// Single settings row with icon, label, and chevron, with tactile Ink ripple.
class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _SettingsItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.white.withOpacity(0.06);
    return Material(
      color: selected ? Colors.white.withOpacity(0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: ListTile(
            minLeadingWidth: 0,
            dense: true,
            leading: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.lightBlueAccent,
                size: 22,
              ),
            ),
            title: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            contentPadding: EdgeInsets.zero,
            horizontalTitleGap: 14,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white54,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// Switch row with leading icon and label, styled to match other rows.
class _ToggleSetting extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSetting({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = Colors.white.withOpacity(0.06);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        activeColor: Colors.lightBlueAccent,
        inactiveThumbColor: Colors.grey,
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: Colors.lightBlueAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}