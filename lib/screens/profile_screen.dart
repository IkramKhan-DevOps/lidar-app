// =============================================================
// PROFILE EDIT SCREEN (UI Refreshed)
// Design aligned with simplified Settings & PasswordChange screens:
// - Background image + dark gradient overlay
// - Center semi-transparent rounded card with subtle border & shadow
// - iOS-style back button
// - Consistent field styling + primary accent (light blue)
// - Business logic / provider calls unchanged
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/providers/auth_provider.dart';
import '../view_model/states/rofile_edit_state.dart'; // (Keeping original import path / filename)

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();

  bool _loadedInitial = false;
  bool _showLocalSuccess = false;

  @override
  void initState() {
    super.initState();
    // Trigger load after first frame
    Future.microtask(() {
      ref.read(profileEditViewModelProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _usernameCtl.dispose();
    super.dispose();
  }

  void _syncControllers(ProfileEditState state) {
    if (_loadedInitial) return;
    if (state.original != null && !state.loading) {
      _firstNameCtl.text = state.original?.firstName ?? '';
      _lastNameCtl.text = state.original?.lastName ?? '';
      _usernameCtl.text = state.original?.username ?? '';
      _loadedInitial = true;
      setState(() {});
    }
  }

  bool _isDirty(ProfileEditState st) {
    final o = st.original;
    if (o == null) return false;
    return _firstNameCtl.text.trim() != (o.firstName ?? '') ||
        _lastNameCtl.text.trim() != (o.lastName ?? '') ||
        _usernameCtl.text.trim() != (o.username ?? '');
  }

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
    final editState = ref.watch(profileEditViewModelProvider);
    _syncControllers(editState);

    final profile = editState.original;
    final email = profile?.email ?? '';
    final canSave = !editState.loading && !editState.saving && _isDirty(editState);

    return Stack(
      children: [
        Scaffold(
          body: Stack(
            children: [
              // Background image (same as Settings / PasswordChange)
              Positioned.fill(
                child: Image.asset(
                  'lib/assets/images/login_image.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Dark overlay gradient
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
                                ? const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                                : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
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

                                // Error / success inline
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

                                // Email (read only)
                                _ReadOnlyField(
                                  label: 'Email',
                                  value: email,
                                ),
                                const SizedBox(height: 16),
                                _EditableField(
                                  label: 'First Name',
                                  controller: _firstNameCtl,
                                  hint: 'First name',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                _EditableField(
                                  label: 'Last Name',
                                  controller: _lastNameCtl,
                                  hint: 'Last name',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                _EditableField(
                                  label: 'Username (optional)',
                                  controller: _usernameCtl,
                                  hint: 'username',
                                  onChanged: (_) => setState(() {}),
                                ),

                                const SizedBox(height: 30),
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
        if (editState.loading && profile != null)
        // Light overlay while reloading (if necessary)
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