import 'package:equatable/equatable.dart';

class ProductivityPayload {
  const ProductivityPayload({
    required this.timeZone,
    required this.range,
    required this.days,
  });

  final String timeZone;
  final int range;
  final List<ProductivityDayModel> days;
}

class ProductivityDayModel extends Equatable {
  const ProductivityDayModel({
    required this.date,
    required this.planned,
    required this.completed,
    required this.rate,
  });

  final String date;
  final int planned;
  final int completed;
  final double rate;

  factory ProductivityDayModel.fromJson(Map<String, dynamic> j) {
    return ProductivityDayModel(
      date: j['date'] as String,
      planned: (j['planned'] as num).toInt(),
      completed: (j['completed'] as num).toInt(),
      rate: (j['rate'] as num).toDouble(),
    );
  }

  @override
  List<Object?> get props => [date, planned, completed, rate];
}
