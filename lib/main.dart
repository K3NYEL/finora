import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app/app.dart';

void main() {
	if (Platform.isLinux) {
		sqfliteFfiInit();
		databaseFactory = databaseFactoryFfi;
	}
	runApp(const ProviderScope(child: FinoraApp()));
}
