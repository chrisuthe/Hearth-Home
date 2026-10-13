/// Which server keeps the kiosk when more than one connects to it.
///
/// Only matters in listening mode (no server URL configured), where any
/// Sendspin server on the network may open a connection. The rules are
/// Sendspin 1.0.0-rc1's "Multiple servers (server-initiated)": a client holds
/// one admitted connection, ranked by its declared activities.
library;

/// What the kiosk knows about a connection when it is arbitrated: the
/// activities from its `server/activate` and the server's identity.
class AdmissionCandidate {
  final Set<String> activities;
  final String? serverId;

  const AdmissionCandidate({required this.activities, required this.serverId});

  /// `playback` outranks `pairing`, which outranks declaring nothing.
  int get rank => activities.contains('playback')
      ? 2
      : activities.contains('pairing')
          ? 1
          : 0;
}

enum AdmissionDecision {
  /// Nothing is admitted yet; the incoming connection takes the kiosk.
  admit,

  /// The incoming connection takes the kiosk from the current holder.
  displaceCurrent,

  /// The current holder keeps the kiosk; the incoming connection is refused.
  rejectIncoming,
}

/// Decides between the [current] holder and an [incoming] connection that
/// has just sent its first `server/activate`.
///
/// [lastPlaybackServerId] is the server that most recently held the kiosk
/// while declaring `playback`. It breaks the tie between two idle servers, so
/// the one that was last playing gets the kiosk back after a restart.
AdmissionDecision decideAdmission({
  required AdmissionCandidate? current,
  required AdmissionCandidate incoming,
  required String? lastPlaybackServerId,
}) {
  if (current == null) return AdmissionDecision.admit;

  // A pairing attempt in progress is never interrupted.
  if (current.activities.contains('pairing')) {
    return AdmissionDecision.rejectIncoming;
  }

  if (current.activities.isEmpty && incoming.activities.isEmpty) {
    final incomingWasLast = lastPlaybackServerId != null &&
        incoming.serverId == lastPlaybackServerId;
    final currentWasLast = lastPlaybackServerId != null &&
        current.serverId == lastPlaybackServerId;
    return incomingWasLast && !currentWasLast
        ? AdmissionDecision.displaceCurrent
        : AdmissionDecision.rejectIncoming;
  }

  return incoming.rank >= current.rank
      ? AdmissionDecision.displaceCurrent
      : AdmissionDecision.rejectIncoming;
}
