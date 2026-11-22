import 'package:flutter/material.dart';

import 'app_theme.dart';

ThemeData darkMode({bool highContrast = false}) =>
    buildTheme(Brightness.dark, highContrast: highContrast);
