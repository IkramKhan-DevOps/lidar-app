// =============================================================
// PROFILE EDIT SCREEN (UI Refreshed)
// Design aligned with simplified Settings & PasswordChange screens:
// - Background image + dark gradient overlay
// - Center semi-transparent rounded card with subtle border & shadow
// - iOS-style back button
// - Consistent field styling + primary accent (light blue)
// - Business logic / provider calls unchanged
// =============================================================
//
// FLOW OVERVIEW
// - On first frame, ViewModel.load() fetches the current profile.
// - When data arrives, controllers are populated once (_syncControllers).
// - User edits fields; "Save" is enabled only when form is dirty and idle.
// - On save, ViewModel.save(...) is called; success shows local banner+snack,
//   and resets the saved flag; errors show inline + snackbar.
//
// INTEGRATION
// - profileEditViewModelProvider exposes ProfileEditState and actions
//   (load, save, clearSavedFlag).
//
// UI LAYERS
// - Fullscreen background image
// - Vertical dark gradient overlay
// - SafeArea with custom Cupertino-like back button
// - Center card with inputs and a primary action button
//
// SAFETY
// - Controllers disposed in dispose().
// - mounted checks before UI feedback / state changes.
//
// TWEAKS
// - Update colors/opacity to match brand.
// - Add validation if needed before calling save(...).
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/providers/auth_provider.dart';
import '../view_model/states/profile_edit_state.dart'; // (Keeping original import path / filename)

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  // -------------------- TEXT CONTROLLERS --------------------
  // Hold the user's editable profile fields.
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();

  // Ensures initial data is written to controllers only once.
  bool _loadedInitial = false;

  // Controls display of a transient local success banner after saving.
  bool _showLocalSuccess = false;

  @override
  void initState() {
    super.initState();
    // Trigger load after first frame; keeps initState clean and avoids
    // synchronous provider reads during build.
    Future.microtask(() {
      ref.read(profileEditViewModelProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    // Always dispose controllers to prevent memory leaks.
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _usernameCtl.dispose();
    super.dispose();
  }

  // =============================================================
  // Populate controllers when original profile data becomes available.
  // Runs only once per screen lifecycle due to _loadedInitial guard.
  // =============================================================
  void _syncControllers(ProfileEditState state) {
    if (_loadedInitial) return;
    if (state.original != null && !state.loading) {
      _firstNameCtl.text = state.original?.firstName ?? '';
      _lastNameCtl.text = state.original?.lastName ?? '';
      _usernameCtl.text = state.original?.username ?? '';
      _loadedInitial = true;
      setState(() {}); // Refresh to update canSave, etc.
    }
  }

  // =============================================================
  // Check if any field differs from the originally loaded profile.
  // Used to enable/disable the Save button.
  // =============================================================
  bool _isDirty(ProfileEditState st) {
    final o = st.original;
    if (o == null) return false;
    return _firstNameCtl.text.trim() != (o.firstName ?? '') ||
        _lastNameCtl.text.trim() != (o.lastName ?? '') ||
        _usernameCtl.text.trim() != (o.username ?? '');
  }

  // =============================================================
  // Save handler:
  // - Calls ViewModel.save(...) with trimmed inputs.
  // - On success: show local success banner + snackbar, then hide banner.
  // - On error: show snackbar with error message.
  // =============================================================
  Future<void> _onSave() async {
    final notifier = ref.read(profileEditViewModelProvider.notifier);
    await notifier.save(
      firstName: _firstNameCtl.text.trim(),
      lastName: _lastNameCtl.text.trim(),
      username: _usernameCtl.text.trim().isEmpty ? null : _usernameCtl.text.trim(),
    );
    final st = ref.read(profileEditViewModelProvider);
    if (st.saved && mounted) {
      setState(() {
        _showLocalSuccess = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: Colors.green,
        ),
      );
      notifier.clearSavedFlag();
      // Hide local banner after a short delay.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showLocalSuccess = false);
      });
    } else if (st.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(st.error!),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Observe state; will rebuild UI on changes (loading/saving/errors).
    final editState = ref.watch(profileEditViewModelProvider);

    // Sync controllers once when data is loaded.
    _syncControllers(editState);

    // Convenience locals
    final profile = editState.original;
    final email = profile?.email ?? '';

    // Save button is enabled only when not loading/saving and form is dirty.
    final canSave = !editState.loading && !editState.saving && _isDirty(editState);

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
                        Colors.black.withOpacity(0.65),
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
                child: Column(
                  children: [
                    // Top bar with back button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        children: [
                          _CupertinoBackButton(
                            onTap: () => Navigator.maybePop(context),
                            label: 'Back',
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
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
                            child: profile == null && editState.loading
                            // Initial loading state (no data yet).
                                ? const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                                : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ---------- Title ----------
                                Row(
                                  children: const [
                                    Icon(Icons.person_outline,
                                        color: Colors.lightBlueAccent, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'Edit Profile',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Update your personal information below.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // ---------- Inline error / success ----------
                                if (editState.error != null)
                                  _InlineMessage(
                                    text: editState.error!,
                                    color: Colors.redAccent,
                                    icon: Icons.error_outline,
                                  )
                                else if (_showLocalSuccess)
                                  _InlineMessage(
                                    text: 'Profile updated successfully',
                                    color: Colors.greenAccent,
                                    icon: Icons.check_circle_outline,
                                  ),
                                if (editState.error != null || _showLocalSuccess)
                                  const SizedBox(height: 20),

                                // ---------- Fields ----------
                                // Email (read only)
                                _ReadOnlyField(
                                  label: 'Email',
                                  value: email,
                                ),
                                const SizedBox(height: 16),

                                // First Name
                                _EditableField(
                                  label: 'First Name',
                                  controller: _firstNameCtl,
                                  hint: 'First name',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),

                                // Last Name
                                _EditableField(
                                  label: 'Last Name',
                                  controller: _lastNameCtl,
                                  hint: 'Last name',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),

                                // Username (optional)
                                _EditableField(
                                  label: 'Username (optional)',
                                  controller: _usernameCtl,
                                  hint: 'username',
                                  onChanged: (_) => setState(() {}),
                                ),

                                const SizedBox(height: 30),

                                // ---------- Primary action ----------
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: canSave ? _onSave : null,
                                    icon: editState.saving
                                        ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                        : const Icon(Icons.save_outlined),
                                    label: Text(
                                      editState.saving ? 'Saving...' : 'Save Changes',
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF008CFF),
                                      disabledBackgroundColor: Colors.blueGrey.shade600,
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
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
            ],
          ),
        ),

        // Optional: lightweight overlay when a background refresh occurs
        // (i.e., loading but we still have existing profile data).
        if (editState.loading && profile != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.black26,
              ),
            ),
          ),
      ],
    );
  }
}

/* ---------------------------- Helper Widgets ---------------------------- */

// =============================================================
// Cupertino-like "Back" button with subtle glass styling.
// =============================================================
class _CupertinoBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;
  const _CupertinoBackButton({required this.onTap, this.label = 'Back'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Back',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Inline banner for success/error messages within the card.
// =============================================================
class _InlineMessage extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _InlineMessage({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Read-only value field styled to match editable inputs.
// =============================================================
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return _FieldWrapper(
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Text(
          value,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}

// =============================================================
// Labeled editable text field with glass styling and hint.
// =============================================================
class _EditableField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;

  const _EditableField({
    required this.label,
    required this.controller,
    this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return _FieldWrapper(
      label: label,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.07),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFF008CFF), width: 1.4),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Shared label + field wrapper for consistent spacing/typography.
// =============================================================
class _FieldWrapper extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldWrapper({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.white70,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}