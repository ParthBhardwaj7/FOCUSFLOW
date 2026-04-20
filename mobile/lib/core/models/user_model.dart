import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  const UserModel({
    required this.id,
    required this.email,
    this.onboardingCompletedAt,
    this.timeZone,
    this.profileSummary,
    this.createdAt,
  });

  final String id;
  final String email;
  final DateTime? onboardingCompletedAt;
  final String? timeZone;
  final String? profileSummary;
  final DateTime? createdAt;

  bool get needsOnboarding => onboardingCompletedAt == null;

  factory UserModel.fromJson(Map<String, dynamic> j) {
    return UserModel(
      id: j['id'] as String,
      email: j['email'] as String,
      onboardingCompletedAt: j['onboardingCompletedAt'] != null
          ? DateTime.tryParse(j['onboardingCompletedAt'] as String)
          : null,
      timeZone: j['timeZone'] as String?,
      profileSummary: j['profileSummary'] as String?,
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (onboardingCompletedAt != null)
          'onboardingCompletedAt': onboardingCompletedAt!.toUtc().toIso8601String(),
        if (timeZone != null) 'timeZone': timeZone,
        if (profileSummary != null) 'profileSummary': profileSummary,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  UserModel copyWith({
    DateTime? onboardingCompletedAt,
    String? timeZone,
    String? profileSummary,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id,
      email: email,
      onboardingCompletedAt: onboardingCompletedAt ?? this.onboardingCompletedAt,
      timeZone: timeZone ?? this.timeZone,
      profileSummary: profileSummary ?? this.profileSummary,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, email, onboardingCompletedAt, timeZone, profileSummary, createdAt];
}
