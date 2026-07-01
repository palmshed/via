import 'dart:convert';

class MediaPlaybackState {
  const MediaPlaybackState({required this.hasPlayingMedia});

  final bool hasPlayingMedia;
}

MediaPlaybackState? parseMediaPlaybackStateMessage(String message) {
  try {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['type'] != 'playback') return null;
    final hasPlayingMedia = decoded['hasPlayingMedia'];
    if (hasPlayingMedia is! bool) return null;
    return MediaPlaybackState(hasPlayingMedia: hasPlayingMedia);
  } catch (_) {
    return null;
  }
}
