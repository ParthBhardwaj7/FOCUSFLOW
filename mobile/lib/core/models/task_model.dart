import 'package:equatable/equatable.dart';

class TaskModel extends Equatable {
  const TaskModel({
    required this.id,
    required this.title,
    this.notes,
    required this.scheduledOn,
    required this.sortOrder,
    required this.isMit,
  });

  final String id;
  final String title;
  final String? notes;
  final DateTime scheduledOn;
  final int sortOrder;
  final bool isMit;

  factory TaskModel.fromJson(Map<String, dynamic> j) {
    return TaskModel(
      id: j['id'] as String,
      title: j['title'] as String,
      notes: j['notes'] as String?,
      scheduledOn: DateTime.parse(j['scheduledOn'] as String),
      sortOrder: (j['sortOrder'] as num).toInt(),
      isMit: j['isMit'] as bool,
    );
  }

  @override
  List<Object?> get props => [id, title, scheduledOn, sortOrder, isMit];
}
