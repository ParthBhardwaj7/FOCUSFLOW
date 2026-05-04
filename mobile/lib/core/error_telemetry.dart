import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Technical detail for the admin ErrorLog (never shown raw to the user).
String describeErrorForAdmin(Object error) {
  if (error is AsyncError) {
    return describeErrorForAdmin(error.error);
  }
  if (error is DioException) {
    final ro = error.requestOptions;
    final uri = ro.uri;
    final buf = StringBuffer()
      ..write('${ro.method} ')
      ..write(uri)
      ..write(' | dioType=${error.type.name}');
    if (error.response != null) {
      buf.write(' | status=${error.response!.statusCode}');
      final data = error.response!.data;
      if (data is Map<String, dynamic>) {
        try {
          buf.write(' | body=${jsonEncode(data)}');
        } catch (_) {
          buf.write(' | body=<map>');
        }
      } else if (data != null) {
        buf.write(' | body=$data');
      }
    }
    buf.write(' | dioMessage=${error.message}');
    return buf.toString();
  }
  if (error is PlatformException) {
    return 'PlatformException code=${error.code} message=${error.message} '
        'details=${error.details}';
  }
  if (error is FileSystemException) {
    return 'FileSystemException path=${error.path} osError=${error.osError} '
        'message=${error.message}';
  }
  if (error is StateError) {
    return 'StateError: ${error.message}';
  }
  if (error is FormatException) {
    return 'FormatException: ${error.message} source=${error.source} offset=${error.offset}';
  }
  return error.toString();
}
