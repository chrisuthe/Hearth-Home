import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens/tokens.dart';
import '../../config/hub_config.dart';
import '../../config/person.dart';
import 'chores_view.dart' show ChorePersonMark;
import 'lists_providers.dart';

/// Same as the Home clock's, for legibility over full-bleed photos.
const _textShadows = [
  Shadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0xB4000000)),
  Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x82000000)),
];

/// Today's open chores on the idle Home screen, above the calendar glance.
/// Draws nothing when the glance is off, no list is a chore list, or nothing
/// is open for today.
class ChoreGlance extends ConsumerWidget {
  /// Opens the Lists page; null when it is not in the swipe row.
  final VoidCallback? onTap;

  const ChoreGlance({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      hubConfigProvider.select(
        (c) => c.todoChoreGlance && c.todoLists.any((l) => l.isChore),
      ),
    );
    // Off means unwatched, so no chore list is subscribed for the glance.
    if (!shown) return const SizedBox.shrink();

    // A record compares by value, so a push that leaves the first three and
    // the count unchanged does not rebuild.
    final next = ref.watch(
      choresTodayProvider.select(
        (c) => (
          c.isNotEmpty ? c[0] : null,
          c.length > 1 ? c[1] : null,
          c.length > 2 ? c[2] : null,
          c.length,
        ),
      ),
    );
    final people = ref.watch(hubConfigProvider.select((c) => c.people));
    final lines = [next.$1, next.$2, next.$3].nonNulls.toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final more = next.$4 - lines.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: HearthSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, line) in lines.indexed)
              _GlanceLine(
                line: line,
                person: personById(people, line.list.personId),
                more: i == lines.length - 1 ? more : 0,
              ),
          ],
        ),
      ),
    );
  }
}

class _GlanceLine extends StatelessWidget {
  final ChoreLine line;

  /// Null only for a list whose person has just been removed.
  final Person? person;
  final int more;

  const _GlanceLine({
    required this.line,
    required this.person,
    required this.more,
  });

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.8);
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.x1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (person?.isLinked ?? false)
            ChorePersonMark(person: person!, size: 24)
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Color(person?.color ?? line.list.color),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Color(0x82000000)),
                ],
              ),
            ),
          const SizedBox(width: HearthSpacing.x3),
          // A long name gives way to the summary rather than overflowing.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              person?.name ?? line.list.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: HearthFont.title,
                color: dim,
                shadows: _textShadows,
              ),
            ),
          ),
          const SizedBox(width: HearthSpacing.x3),
          Flexible(
            child: Text(
              line.late ? '${line.item.summary} · late' : line.item.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: HearthFont.title,
                shadows: _textShadows,
              ),
            ),
          ),
          if (more > 0) ...[
            const SizedBox(width: HearthSpacing.x3),
            Text(
              '+$more more',
              style: TextStyle(
                fontSize: HearthFont.title,
                color: dim,
                shadows: _textShadows,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
