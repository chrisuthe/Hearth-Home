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

  const PersonAvatar({super.key, required this.view, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final initial = _Initial(view: view, size: size);
    final url = view.avatarUrl;
    final presence = view.presence;
    final dot = size * 0.34;
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
                  key: const ValueKey('presence-dot'),
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: presenceColor(presence),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.hearthColors.canvas, width: 1.5),
                  ),
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
            color: context.hearthColors.text,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      );
}
