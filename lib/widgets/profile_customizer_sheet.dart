import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

class ProfileCustomizerSheet extends ConsumerStatefulWidget {
  final AppUser user;

  const ProfileCustomizerSheet({super.key, required this.user});

  static Future<void> show(BuildContext context, {required AppUser user}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileCustomizerSheet(user: user),
    );
  }

  @override
  ConsumerState<ProfileCustomizerSheet> createState() => _ProfileCustomizerSheetState();
}

class _ProfileCustomizerSheetState extends ConsumerState<ProfileCustomizerSheet> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  String? _selectedAvatarUrl;
  bool _isSaving = false;

  // Preset avatar styles (clean, transparent DiceBear vectors)
  final List<Map<String, String>> _presetAvatars = const [
    {
      'label': 'Adventurer',
      'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=Felix&backgroundColor=b6e3f4',
    },
    {
      'label': 'Product Lead',
      'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=Aneka&backgroundColor=ffdfbf',
    },
    {
      'label': 'Tech Architect',
      'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=Sara&backgroundColor=c0aede',
    },
    {
      'label': 'Creative Designer',
      'url': 'https://api.dicebear.com/7.x/lorelei/png?seed=Liam&backgroundColor=ffd5dc',
    },
    {
      'label': 'AI Assistant / Bot',
      'url': 'https://api.dicebear.com/7.x/bottts/png?seed=Alex&backgroundColor=d1d4f9',
    },
    {
      'label': 'Notionist',
      'url': 'https://api.dicebear.com/7.x/notionists/png?seed=Oliver&backgroundColor=ffdfbf',
    },
    {
      'label': 'Fun Star',
      'url': 'https://api.dicebear.com/7.x/fun-emoji/png?seed=Sparky&backgroundColor=ffd5dc',
    },
    {
      'label': 'Executive',
      'url': 'https://api.dicebear.com/7.x/lorelei/png?seed=Milo&backgroundColor=b6e3f4',
    },
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _selectedAvatarUrl = widget.user.avatarUrl;
    _urlController = TextEditingController(text: widget.user.avatarUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authUser = ref.read(authRepositoryProvider).currentUser;
      final finalAvatarUrl = _selectedAvatarUrl?.trim().isEmpty == true ? null : _selectedAvatarUrl?.trim();

      if (authUser != null) {
        if (newName != authUser.displayName) {
          await authUser.updateDisplayName(newName);
        }
        if (finalAvatarUrl != authUser.photoURL) {
          await authUser.updatePhotoURL(finalAvatarUrl);
        }
        await authUser.reload();
      }

      final updatedUser = widget.user.copyWith(
        name: newName,
        avatarUrl: finalAvatarUrl,
      );

      await ref.read(firestoreRepositoryProvider).createUser(updatedUser);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile & Avatar updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Customize Profile & Avatar',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMain,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Live Preview Card
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.colors.primaryLight,
                            border: Border.all(color: context.colors.primary, width: 2.5),
                            boxShadow: AppShadows.card,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildAvatarPreview(),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _nameController.text.isEmpty ? 'Your Name' : _nameController.text,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textMain,
                          ),
                        ),
                        Text(
                          widget.user.email,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Display Name Input
                  Text(
                    'DISPLAY NAME',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Enter full name',
                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                      filled: true,
                      fillColor: context.colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Preset Avatars
                  Text(
                    'CHOOSE PRESET AVATAR',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // Option 1: Monogram Initials (Clear photo)
                      _buildPresetTile(
                        isSelected: _selectedAvatarUrl == null || _selectedAvatarUrl!.isEmpty,
                        label: 'Initials',
                        onTap: () {
                          setState(() {
                            _selectedAvatarUrl = null;
                            _urlController.clear();
                          });
                        },
                        child: Center(
                          child: Text(
                            widget.user.initials,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              color: context.colors.primary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),

                      // Curated presets
                      for (final preset in _presetAvatars)
                        _buildPresetTile(
                          isSelected: _selectedAvatarUrl == preset['url'],
                          label: preset['label']!,
                          onTap: () {
                            setState(() {
                              _selectedAvatarUrl = preset['url'];
                              _urlController.text = preset['url']!;
                            });
                          },
                          child: CachedNetworkImage(
                            imageUrl: preset['url']!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            errorWidget: (_, _, _) => const Icon(Icons.person),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Custom Image URL Input
                  Text(
                    'OR CUSTOM IMAGE URL',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    onChanged: (val) {
                      setState(() {
                        _selectedAvatarUrl = val.trim().isEmpty ? null : val.trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'https://example.com/my-photo.jpg',
                      prefixIcon: const Icon(Icons.link_rounded, size: 20),
                      filled: true,
                      fillColor: context.colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Bottom Action Buttons
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: context.colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Save Profile',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
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

  Widget _buildAvatarPreview() {
    if (_selectedAvatarUrl != null && _selectedAvatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _selectedAvatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, _, _) => Center(
          child: Text(
            widget.user.initials,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: context.colors.primary,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Text(
        widget.user.initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: context.colors.primary,
        ),
      ),
    );
  }

  Widget _buildPresetTile({
    required bool isSelected,
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.surface,
              border: Border.all(
                color: isSelected ? context.colors.primary : context.colors.border,
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: context.colors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? context.colors.primary : context.colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
