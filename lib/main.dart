import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Usage analytics: off unless the build carries ET_APP_ID + ET_WRITE_KEY
  // (core/telemetry.dart). Waits at most 2 s, never throws.
  await Telemetry.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF070611),
  ));
  runApp(const ProviderScope(child: PfepApp()));
}
