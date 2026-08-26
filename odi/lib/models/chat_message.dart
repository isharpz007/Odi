/// A single bubble in the chat thread.
///
/// Most bubbles are normal (user or AI text). The optional flags below
/// let the UI distinguish the few special cases — currently just error
/// bubbles — without forcing every callsite to subclass or wrap.
class ChatMessage {
  /// The text shown inside the bubble.
  final String text;

  /// True for user-typed messages, false for AI replies, error notices,
  /// and the welcome greeting.
  final bool isUser;

  /// IMPORTANT: Task 26 — when true the bubble is rendered with the
  /// error styling (warm-red border, optional Retry button). The text
  /// is the friendly error sentence the user should see.
  final bool isError;

  /// IMPORTANT: Task 26 — a stable identity for bubbles that need to
  /// be referenced later (e.g. the user message we want to retry). It
  /// is intentionally not derived from `text` because two retries of
  /// the same text would collapse; instead we generate a unique id at
  /// insertion time and use it to look the message back up.
  final String id;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    String? id,
  }) : id = id ?? _generateId();

  /// Reserved-suffix id for the welcome greeting (stable across mounts
  /// so callers can recognize it).
  static const String welcomeId = '__welcome__';

  static int _seq = 0;
  static String _generateId() {
    _seq += 1;
    return 'm$_seq';
  }
}