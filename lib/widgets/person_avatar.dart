import 'package:flutter/material.dart';

import '../app/theme/hearth_colors.dart';
import '../services/people.dart';

const kPresenceHome = Color(0xFF66BB6A); // theme-exempt: data color
const kPresenceAway = Color(0xFF9E9E9E); // theme-exempt: data color
const kPresenceZone = Color(0xFFFFB74D); // theme-exempt: data color

/// A person's `entity_picture`, or their initial on their colour, with a
/// presence dot when HA knows where they are.
class PersonAvatar extends StatelessWidget {
  final PersonView view;
  final double size;

  /// A badge with an icon for where they are instead of the dot. For large
  /// avatars only: below about 48 the icon is too small to read.
  final bool presenceIcon;

  const PersonAvatar({
    super.key,
    required this.view,
    this.size = 28,
    this.presenceIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = _Initial(view: view, size: size);
    final url = view.avatarUrl;
    final presence = view.presence;
    final dot = size * (presenceIcon ? 0.4 : 0.34);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: url == null
                ? initial
                : Image.network(
                    url,
                    key: ValueKey(url),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => initial,
                  ),
          ),
          if (presence != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Tooltip(
                message: presence,
                child: Container(
                  key: ValueKey(
                      presenceIcon ? 'presence-icon' : 'presence-dot'),
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: presenceColor(presence),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.hearthColors.canvas, width: 1.5),
                  ),
                  child: presenceIcon
                      ? Icon(
                          presenceIconData(presence),
                          size: dot * 0.62,
                          color: Colors.black87, // theme-exempt: on a data color
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color presenceColor(String presence) => switch (presence) {
      'Home' => kPresenceHome,
      'Away' => kPresenceAway,
      _ => kPresenceZone,
    };

/// Any zone gets the pin until zones show their own HA icon.
IconData presenceIconData(String presence) => switch (presence) {
      'Home' => Icons.home_rounded,
      'Away' => Icons.directions_walk,
      _ => Icons.place,
    };

class _Initial extends StatelessWidget {
  final PersonView view;
  final double size;
  const _Initial({required this.view, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: Color(view.color),
        child: Text(
          view.initial,
          style: TextStyle(
            color: Colors.white, // theme-exempt: data color
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      );
}
