import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user.dart';
import '../theme/app_theme.dart';

/// A horizontal stack of overlapping circular avatars.
///
/// Displays up to [maxDisplay] avatars with a +N overflow indicator
/// when there are more participants than can be shown.
class AvatarStack extends StatelessWidget {
  final List<AppUser> users;
  final int maxDisplay;
  final double size;

  const AvatarStack({
    super.key,
    required this.users,
    this.maxDisplay = 3,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = users.length > maxDisplay ? maxDisplay : users.length;
    final overflow = users.length - maxDisplay;
    final double overlap = 8.0;

    // Total width: first avatar full size, each subsequent avatar overlaps by `overlap`
    final int totalItems = displayCount + (overflow > 0 ? 1 : 0);
    final double totalWidth = totalItems > 0
        ? size + (totalItems - 1) * (size - overlap)
        : 0;

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < displayCount; i++)
            Positioned(
              left: i * (size - overlap),
              child: _AvatarCircle(
                user: users[i],
                size: size,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: displayCount * (size - overlap),
              child: _OverflowCircle(
                count: overflow,
                size: size,
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final AppUser user;
  final double size;

  const _AvatarCircle({
    required this.user,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.colors.surface,
          width: 2,
        ),
        color: context.colors.border,
      ),
      child: ClipOval(
        child: user.avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: user.avatarUrl!,
                width: size - 4, // account for border
                height: size - 4,
                fit: BoxFit.cover,
                placeholder: (context, url) => _InitialsView(
                  initials: user.initials,
                  size: size - 4,
                ),
                errorWidget: (context, url, error) => _InitialsView(
                  initials: user.initials,
                  size: size - 4,
                ),
              )
            : _InitialsView(
                initials: user.initials,
                size: size - 4,
              ),
      ),
    );
  }
}

class _InitialsView extends StatelessWidget {
  final String initials;
  final double size;

  const _InitialsView({
    required this.initials,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Color(0xFFD1D1D6),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: context.colors.textMain,
        ),
      ),
    );
  }
}

class _OverflowCircle extends StatelessWidget {
  final int count;
  final double size;

  const _OverflowCircle({
    required this.count,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.colors.surface,
          width: 2,
        ),
        color: Color(0xFFD1D1D6),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: GoogleFonts.plusJakartaSans(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
          color: context.colors.textMain,
        ),
      ),
    );
  }
}
