import 'package:flutter/material.dart';

/// Curated emoji groups for the task icon picker (sections, not the full Unicode set).
/// Emojis are chosen for broad font support; avoid rare ZWJ sequences where possible.
class TaskEmojiSection {
  const TaskEmojiSection({
    required this.title,
    required this.icon,
    required this.emojis,
  });

  final String title;
  final IconData icon;
  final List<String> emojis;
}

/// Section headers use Material icons; cells use [emojis] only.
const List<TaskEmojiSection> kTaskEmojiSections = [
  TaskEmojiSection(
    title: 'Health & wellness',
    icon: Icons.favorite_rounded,
    emojis: ['❤️', '🩺', '💊', '🧬', '🫀', '🏥', '🧴', '☀️'],
  ),
  TaskEmojiSection(
    title: 'Fitness',
    icon: Icons.fitness_center_rounded,
    emojis: ['🏋️', '🏃', '🚴', '🤸', '⚽', '🏀', '🧗', '🥊'],
  ),
  TaskEmojiSection(
    title: 'Learning & skills',
    icon: Icons.school_rounded,
    emojis: ['📚', '✏️', '📝', '🎓', '📖', '🔬', '🧮', '💡'],
  ),
  TaskEmojiSection(
    title: 'Productivity',
    icon: Icons.task_alt_rounded,
    emojis: ['✅', '📋', '🗂️', '⏱️', '🎯', '📌', '✉️', '📅'],
  ),
  TaskEmojiSection(
    title: 'Creative & arts',
    icon: Icons.palette_rounded,
    emojis: ['🎨', '🖌️', '🎭', '🎬', '🎵', '📷', '✍️', '🧵'],
  ),
  TaskEmojiSection(
    title: 'Food & nutrition',
    icon: Icons.restaurant_rounded,
    emojis: ['🍎', '🥗', '🍳', '🥤', '🍽️', '🥦', '🧃', '🍞'],
  ),
  TaskEmojiSection(
    title: 'Social & relationships',
    icon: Icons.groups_rounded,
    emojis: ['👥', '💬', '🤝', '☕', '🎉', '💐', '📞', '🫂'],
  ),
  TaskEmojiSection(
    title: 'Finance & money',
    icon: Icons.account_balance_rounded,
    emojis: ['💰', '💳', '📊', '🧾', '💵', '🏦', '📈', '💼'],
  ),
  TaskEmojiSection(
    title: 'Environment & nature',
    icon: Icons.park_rounded,
    emojis: ['🌿', '🌳', '🌍', '🌧️', '🦋', '🌸', '♻️', '🌊'],
  ),
  TaskEmojiSection(
    title: 'Transportation',
    icon: Icons.directions_car_rounded,
    emojis: ['🚗', '🚲', '✈️', '🚌', '🚆', '🛵', '🚇', '⛽'],
  ),
  TaskEmojiSection(
    title: 'Home & lifestyle',
    icon: Icons.home_rounded,
    emojis: ['🏠', '🛋️', '🧹', '🛒', '🔑', '🪴', '🛏️', '🍳'],
  ),
  TaskEmojiSection(
    title: 'Mental & spiritual',
    icon: Icons.self_improvement_rounded,
    emojis: ['🧘', '🕯️', '📿', '🌙', '☮️', '🧠', '📝', '🫶'],
  ),
  TaskEmojiSection(
    title: 'Technology & digital',
    icon: Icons.computer_rounded,
    emojis: ['💻', '📱', '⌨️', '🖥️', '📡', '🔒', '💾', '🎮'],
  ),
];
