import 'package:flutter/material.dart';

import 'app_theme.dart';

ThemeData lightMode({bool highContrast = false}) =>
    buildTheme(Brightness.light, highContrast: highContrast);
