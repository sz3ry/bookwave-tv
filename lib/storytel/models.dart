class ShelfBook {
  ShelfBook({
    required this.consumableId,
    required this.title,
    required this.authors,
    required this.kidsBook,
    required this.durationMs,
    this.coverUrl,
    this.positionMs,
    this.positionUpdatedTime,
    this.stateUpdateTime,
  });

  factory ShelfBook.fromJson(Map<String, dynamic> json) => ShelfBook(
    consumableId: json['consumableId'] as String,
    title: json['title'] as String,
    authors: json['authors'] as String,
    kidsBook: json['kidsBook'] as bool,
    coverUrl: json['coverUrl'] as String?,
    durationMs: json['durationMs'] as int,
    positionMs: json['positionMs'] as int?,
    positionUpdatedTime: _date(json['positionUpdatedTime']),
    stateUpdateTime: _date(json['stateUpdateTime']),
  );

  final String consumableId;
  final String title;

  /// Author names joined by `', '`.
  final String authors;
  final bool kidsBook;
  final String? coverUrl;
  final int durationMs;
  final int? positionMs;
  final DateTime? positionUpdatedTime;
  final DateTime? stateUpdateTime;

  Map<String, dynamic> toJson() => {
    'consumableId': consumableId,
    'title': title,
    'authors': authors,
    'kidsBook': kidsBook,
    'coverUrl': coverUrl,
    'durationMs': durationMs,
    'positionMs': positionMs,
    'positionUpdatedTime': positionUpdatedTime?.toIso8601String(),
    'stateUpdateTime': stateUpdateTime?.toIso8601String(),
  };
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class RemotePosition {
  RemotePosition(this.positionMs, this.updatedTime);

  final int positionMs;
  final DateTime? updatedTime;
}

class StorytelCredentials {
  StorytelCredentials({required this.email, required this.encryptedPassword});

  final String email;
  final String encryptedPassword;
}

/// The login call succeeded (2xx) but returned no jwt.
class StorytelLoginException implements Exception {
  @override
  String toString() => 'StorytelLoginException: login returned no token';
}
