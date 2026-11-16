import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/contact_model.dart';
import '../theme/app_theme.dart';

const List<String> kPresetAvatars = [
  '👨', '👩', '🧑', '👴', '👵', '👶',
  '💼', '👔', '🎓', '💻', '🩺', '🎨',
  '⚽', '🚀', '🌟', '🐱', '🐶', '☕',
  '🚗', '🏡', '🎧', '🎸', '✈️', '🔥',
];

class ContactAvatar extends StatelessWidget {
  final String? avatar;
  final String initials;
  final Color categoryColor;
  final double radius;
  final VoidCallback? onTap;
  final bool showEditBadge;

  const ContactAvatar({
    super.key,
    this.avatar,
    required this.initials,
    required this.categoryColor,
    this.radius = 24,
    this.onTap,
    this.showEditBadge = false,
  });

  factory ContactAvatar.fromContact({
    Key? key,
    required AddressContact contact,
    required Color categoryColor,
    double radius = 24,
    VoidCallback? onTap,
    bool showEditBadge = false,
  }) {
    return ContactAvatar(
      key: key,
      avatar: contact.avatar,
      initials: contact.initials,
      categoryColor: categoryColor,
      radius: radius,
      onTap: onTap,
      showEditBadge: showEditBadge,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget avatarWidget;

    if (avatar != null && avatar!.trim().isNotEmpty) {
      final av = avatar!.trim();
      if (av.startsWith('preset:')) {
        final emoji = av.replaceFirst('preset:', '');
        avatarWidget = Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: categoryColor.withValues(alpha: 0.25),
            border: Border.all(color: categoryColor.withValues(alpha: 0.6), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            emoji,
            style: TextStyle(fontSize: radius * 1.05),
          ),
        );
      } else {
        final file = File(av);
        if (file.existsSync()) {
          avatarWidget = Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: categoryColor.withValues(alpha: 0.7), width: 1.5),
              image: DecorationImage(
                image: FileImage(file),
                fit: BoxFit.cover,
              ),
            ),
          );
        } else {
          avatarWidget = _buildInitials();
        }
      }
    } else {
      avatarWidget = _buildInitials();
    }

    if (!showEditBadge && onTap == null) {
      return avatarWidget;
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarWidget,
          if (showEditBadge)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0A1020), width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 14,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInitials() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: categoryColor.withValues(alpha: 0.2),
        border: Border.all(color: categoryColor.withValues(alpha: 0.5), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.bold,
          color: categoryColor,
        ),
      ),
    );
  }
}

Future<String?> showAvatarPickerSheet({
  required BuildContext context,
  String? currentAvatar,
}) async {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF121A31),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.face_retouching_natural, color: AppColors.primary),
                SizedBox(width: 10),
                Text(
                  'Wybierz awatar kontaktu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Source options (Gallery / Camera)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A1020),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    icon: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                    label: const Text('Galeria', style: TextStyle(fontSize: 13)),
                    onPressed: () async {
                      final picker = ImagePicker();
                      try {
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 800,
                          maxHeight: 800,
                          imageQuality: 85,
                        );
                        if (picked != null && ctx.mounted) {
                          Navigator.of(ctx).pop(picked.path);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Błąd wyboru zdjęcia: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A1020),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                    label: const Text('Aparat', style: TextStyle(fontSize: 13)),
                    onPressed: () async {
                      final picker = ImagePicker();
                      try {
                        final picked = await picker.pickImage(
                          source: ImageSource.camera,
                          maxWidth: 800,
                          maxHeight: 800,
                          imageQuality: 85,
                        );
                        if (picked != null && ctx.mounted) {
                          Navigator.of(ctx).pop(picked.path);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Błąd aparatu: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Text(
              'LUB WYBIERZ GOTOWY AWATAR',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            // Preset Avatars Grid
            Container(
              height: 170,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1020),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: GridView.builder(
                itemCount: kPresetAvatars.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final emoji = kPresetAvatars[index];
                  final isSelected = currentAvatar == 'preset:$emoji';

                  return InkWell(
                    onTap: () => Navigator.of(ctx).pop('preset:$emoji'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Remove avatar option
            if (currentAvatar != null && currentAvatar.isNotEmpty)
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(''), // empty string means remove avatar
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                  label: const Text(
                    'Usuń awatar (użyj inicjałów)',
                    style: TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
