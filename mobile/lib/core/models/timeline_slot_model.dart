import 'package:equatable/equatable.dart';

class TimelineSlotModel extends Equatable {
  const TimelineSlotModel({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    this.iconKey,
    this.tag,
    this.soundLabel,
    required this.status,
    this.linkedTaskId,
    required this.sortOrder,
    this.isMit = false,
    this.taskNotes,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String title;
  final String? iconKey;
  final String? tag;
  final String? soundLabel;
  final String status;
  final String? linkedTaskId;
  final int sortOrder;
  final bool isMit;
  final String? taskNotes;

  bool get isDone => status == 'DONE';
  bool get isMissed => status == 'MISSED';
  bool get isActive => status == 'ACTIVE';
  bool get isUpcoming => status == 'UPCOMING';

  Duration get plannedDuration => endsAt.difference(startsAt);

  factory TimelineSlotModel.fromJson(Map<String, dynamic> j) {
    return TimelineSlotModel(
      id: j['id'] as String,
      startsAt: DateTime.parse(j['startsAt'] as String),
      endsAt: DateTime.parse(j['endsAt'] as String),
      title: j['title'] as String,
      iconKey: j['iconKey'] as String?,
      tag: j['tag'] as String?,
      soundLabel: j['soundLabel'] as String?,
      status: j['status'] as String,
      linkedTaskId: j['linkedTaskId'] as String?,
      sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      isMit: j['isMit'] as bool? ?? false,
      taskNotes: j['taskNotes'] as String?,
    );
  }

  TimelineSlotModel copyWith({
    String? id,
    DateTime? startsAt,
    DateTime? endsAt,
    String? title,
    String? iconKey,
    String? tag,
    String? soundLabel,
    String? status,
    String? linkedTaskId,
    int? sortOrder,
    bool? isMit,
    String? taskNotes,
  }) {
    return TimelineSlotModel(
      id: id ?? this.id,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      title: title ?? this.title,
      iconKey: iconKey ?? this.iconKey,
      tag: tag ?? this.tag,
      soundLabel: soundLabel ?? this.soundLabel,
      status: status ?? this.status,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
      sortOrder: sortOrder ?? this.sortOrder,
      isMit: isMit ?? this.isMit,
      taskNotes: taskNotes ?? this.taskNotes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'title': title,
        'iconKey': iconKey,
        'tag': tag,
        'soundLabel': soundLabel,
        'status': status,
        'linkedTaskId': linkedTaskId,
        'sortOrder': sortOrder,
        'isMit': isMit,
        if (taskNotes != null) 'taskNotes': taskNotes,
      };

  @override
  List<Object?> get props => [id, startsAt, endsAt, status, isMit, taskNotes];
}
