import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:langchain_core/chat_models.dart';

class AiChatHistoryEntry {
  const AiChatHistoryEntry({
    required this.id,
    required this.serviceId,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.completed,
    this.bookId,
    this.bookTitle,
  });

  final String id;
  final String serviceId;
  final String model;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;
  final bool completed;
  final int? bookId;
  final String? bookTitle;

  AiChatHistoryEntry copyWith({
    List<ChatMessage>? messages,
    int? updatedAt,
    bool? completed,
    String? model,
    int? bookId,
    String? bookTitle,
  }) {
    return AiChatHistoryEntry(
      id: id,
      serviceId: serviceId,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      completed: completed ?? this.completed,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceId': serviceId,
      'model': model,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completed': completed,
      'bookId': bookId,
      'bookTitle': bookTitle,
      'messages': messages.map((m) => m.toMap()).toList(growable: false),
    };
  }

  factory AiChatHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(ChatMessage.fromMap(item));
        } else if (item is Map) {
          messages.add(ChatMessage.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ));
        }
      }
    }

    return AiChatHistoryEntry(
      id: json['id']?.toString() ?? '',
      serviceId: json['serviceId']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      completed: json['completed'] == true,
      bookId: json['bookId'] is int ? json['bookId'] as int : null,
      bookTitle: json['bookTitle']?.toString(),
      messages: messages,
    );
  }
}

class AiHistoryStore {
  static const String historyFileName = 'ai_history.json';

  static Future<List<AiChatHistoryEntry>> readHistory() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return <AiChatHistoryEntry>[];
    }

    try {
      final content = await file.readAsString();
      final decoded = json.decode(content);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.fromEntries(
                  e.entries.map(
                    (entry) => MapEntry(entry.key.toString(), entry.value),
                  ),
                ))
            .map(AiChatHistoryEntry.fromJson)
            .toList(growable: false);
      }
    } catch (_) {
      await file.delete();
    }
    return <AiChatHistoryEntry>[];
  }

  static Future<void> upsertEntry(AiChatHistoryEntry entry) async {
    final file = await _resolveFile();
    final history = List<AiChatHistoryEntry>.from(await readHistory());
    final existingIndex =
        history.indexWhere((element) => element.id == entry.id);

    if (existingIndex >= 0) {
      history[existingIndex] = entry;
    } else {
      history.add(entry);
    }

    history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final maxCount = Prefs().maxAiCacheCount;
    final limit = maxCount <= 0 ? history.length : maxCount;
    final limited = history.take(limit).toList(growable: false);

    await file.writeAsString(
      json.encode(limited.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  static Future<void> removeEntry(String id) async {
    final file = await _resolveFile();
    final history = List<AiChatHistoryEntry>.from(await readHistory());
    final filtered =
        history.where((element) => element.id != id).toList(growable: false);
    await file.writeAsString(
      json.encode(filtered.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  static Future<void> clear() async {
    final file = await _resolveFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> _resolveFile() async {
    final aiDir = getAiDir();
    if (!await aiDir.exists()) {
      await aiDir.create(recursive: true);
    }
    final targetFile = File('${aiDir.path}/$historyFileName');

    // Migration from old cache directory if exists
    if (!await targetFile.exists()) {
      try {
        final oldCacheDir = await getAnxCacheDir();
        final oldFile = File('${oldCacheDir.path}/$historyFileName');
        if (await oldFile.exists()) {
          await oldFile.copy(targetFile.path);
          await oldFile.delete();
        }
      } catch (_) {}
    }

    return targetFile;
  }
}
