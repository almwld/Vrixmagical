/// Deterministic ownership policy for XPBD's one-contact-per-vertex API.
///
/// The native solver currently stores a single contact constraint per vertex.
/// If two rigid bodies touch the same soft-body vertex in one frame, the body
/// with the lexicographically smaller stable ID owns that vertex. Repeated
/// events from the owner update its contact; events from the other body cannot
/// overwrite it. Once the owner contact ends, a still-active competing contact
/// can be accepted again on its next Jolt contact-stay event.
class SoftBodyContactPolicy {
  const SoftBodyContactPolicy._();

  static bool shouldAcceptContact({
    required String? currentBodyId,
    required String incomingBodyId,
  }) {
    if (incomingBodyId.isEmpty) return false;
    if (currentBodyId == null || currentBodyId == incomingBodyId) return true;
    return incomingBodyId.compareTo(currentBodyId) < 0;
  }
}
