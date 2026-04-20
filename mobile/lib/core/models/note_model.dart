import 'package:equatable/equatable.dart';

class NoteModel extends Equatable {
  const NoteModel({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NoteModel.fromJson(Map<String, dynamic> j) {
    return NoteModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      pinned: j['pinned'] as bool? ?? false,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, title, body, pinned, createdAt, updatedAt];
}
