class AppUser {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final bool isSelf;
  final bool hasVoiceprint;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.isSelf = false,
    this.hasVoiceprint = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      isSelf: json['isSelf'] as bool? ?? false,
      hasVoiceprint: json['hasVoiceprint'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'isSelf': isSelf,
      'hasVoiceprint': hasVoiceprint,
    };
  }

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    bool? isSelf,
    bool? hasVoiceprint,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isSelf: isSelf ?? this.isSelf,
      hasVoiceprint: hasVoiceprint ?? this.hasVoiceprint,
    );
  }

  /// Returns initials when no avatar is available
  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }
}
