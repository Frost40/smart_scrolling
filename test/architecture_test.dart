// The rule robot: fails when code breaks docs/ARCHITECTURE.md (folders, names,
// file size, widget classes, theme values, layer imports, LEGO catalogue).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _slash(String path) => path.replaceAll(r'\', '/');

final List<String> _dartFiles = Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => _slash(f.path))
    .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
    .toList();

const _plainFolders = {
  'config',
  'routing',
  'core/theme',
  'core/widgets',
  'domain',
  'domain/models',
  'data/services',
  'data/repositories',
  'data/local',
};

const _outsideSystems = [
  'package:supabase_flutter',
  'package:supabase/',
  'package:shared_preferences',
  'package:drift',
];

String _read(String path) => File(path).readAsStringSync();

/// Screen files and LEGO pieces: the files that must follow the widget and theme rules.
bool _isUi(String p) =>
    (p.startsWith('lib/screens/') && !p.endsWith('_provider.dart')) ||
    p.startsWith('lib/core/widgets/');

bool _allowedPlace(String p) {
  if (p == 'lib/main.dart' || p == 'lib/app.dart') return true;
  final parts = p.split('/');
  final name = parts.last;
  if (!RegExp(r'^[a-z0-9_]+\.dart$').hasMatch(name)) return false;
  if (_plainFolders.contains(parts.sublist(1, parts.length - 1).join('/'))) {
    return true;
  }
  if (parts.length == 4 && parts[1] == 'screens') {
    final screen = parts[2];
    return name == '${screen}_screen.dart' || name == '${screen}_provider.dart';
  }
  return parts.length == 5 && parts[1] == 'screens' && parts[3] == 'widgets';
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      out.add(part);
    }
  }
  return out.join('/');
}

/// Imports and exports of [p]. 'dart:' and 'package:' URIs stay as they are;
/// this app's own files become lib-relative paths such as 'data/services/x.dart'.
List<String> _imports(String p) {
  final dir = p.substring(0, p.lastIndexOf('/'));
  return RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(_read(p)).map((m) => m.group(1)!).map((uri) {
    if (uri.startsWith('package:smart_scrolling/')) {
      return uri.substring('package:smart_scrolling/'.length);
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
    return _normalize('$dir/$uri').replaceFirst(RegExp(r'^lib/'), '');
  }).toList();
}

List<String> _screenFolders() => Directory('lib/screens').existsSync()
    ? Directory('lib/screens')
          .listSync()
          .whereType<Directory>()
          .map((d) => _slash(d.path).split('/').last)
          .toList()
    : <String>[];

/// Import prefixes the file [p] must not use (see docs/ARCHITECTURE.md).
List<String> _forbiddenImports(String p) {
  if (p.startsWith('lib/domain/')) {
    return [
      'package:',
      'core/',
      'data/',
      'screens/',
      'routing/',
      'config/',
      'app.dart',
    ];
  }
  if (p.startsWith('lib/core/')) {
    return [..._outsideSystems, 'data/', 'screens/', 'routing/'];
  }
  if (p.startsWith('lib/data/')) {
    return ['screens/', 'core/widgets/', 'routing/'];
  }
  if (p.startsWith('lib/screens/')) {
    final own = p.split('/')[2];
    return [
      ..._outsideSystems,
      'data/services/',
      'data/local/',
      for (final screen in _screenFolders())
        if (screen != own) 'screens/$screen/',
    ];
  }
  if (p.startsWith('lib/routing/') ||
      p.startsWith('lib/config/') ||
      p == 'lib/app.dart') {
    return _outsideSystems;
  }
  return const [];
}

void main() {
  test(
    'every file is in an allowed folder with a lowercase_with_underscores name',
    () {
      final wrong = _dartFiles.where((p) => !_allowedPlace(p)).toList();
      expect(
        wrong,
        isEmpty,
        reason: 'Move these files. See "Where does this go?" in docs/ARCHITECTURE.md.',
      );
    },
  );

  test('every screen folder has its <name>_screen.dart', () {
    final missing = _screenFolders()
        .where((s) => !File('lib/screens/$s/${s}_screen.dart').existsSync())
        .toList();
    expect(missing, isEmpty);
  });

  test('screen and LEGO files have at most 250 lines', () {
    final long = _dartFiles
        .where(
          (p) =>
              p.startsWith('lib/screens/') || p.startsWith('lib/core/widgets/'),
        )
        .where((p) => File(p).readAsLinesSync().length > 250)
        .toList();
    expect(long, isEmpty, reason: 'Split them into smaller widget classes.');
  });

  test('UI pieces are widget classes, not helper methods', () {
    final helper = RegExp(
      r'^\s*(?:static\s+)?Widget\??\s+(?:get\s+\w+|(?!build\b)\w+\s*[(<])',
      multiLine: true,
    );
    final bad = _dartFiles
        .where(_isUi)
        .where((p) => helper.hasMatch(_read(p)))
        .toList();
    expect(
      bad,
      isEmpty,
      reason: 'Turn each "Widget something(...)" into a StatelessWidget or StatefulWidget class.',
    );
  });

  test('colors, text styles, sizes and times come from lib/core/theme', () {
    final raw = RegExp(
      r'Color\(\s*0x|Color\.from(?:ARGB|RGBO)\(|\bColors\.(?!transparent\b)\w|\bTextStyle\(|'
      r'\b\w*(?:[wW]idth|[hH]eight|[sS]ize|[rR]adius|[eE]levation|[sS]pacing)\s*:\s*(?:[1-9]|0\.\d)|'
      r'\b(?:horizontal|vertical|left|right|top|bottom)\s*:\s*(?:[1-9]|0\.\d)|'
      r'\b(?:EdgeInsets(?:Directional)?\.(?:all|fromLTRB|fromSTEB)|BorderRadius\.circular|Radius\.circular|Size)\(\s*(?:[1-9]|0\.\d)|'
      r'\bDuration\(\s*(?:milliseconds|seconds)\s*:\s*[1-9]',
    );
    final bad = <String>[];
    for (final p in _dartFiles.where(_isUi)) {
      final text = _read(p);
      for (final m in raw.allMatches(text)) {
        final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
        bad.add('$p:$line  ${m.group(0)}');
      }
    }
    expect(
      bad,
      isEmpty,
      reason: 'Use context.colors, textTheme, AppSpacing, AppRadius, AppSizes or AppDurations.',
    );
  });

  test('folders import only what docs/ARCHITECTURE.md allows', () {
    final bad = <String>[
      for (final p in _dartFiles)
        for (final target in _imports(p))
          if (_forbiddenImports(p).any(target.startsWith)) '$p imports $target',
    ];
    expect(bad, isEmpty);
  });

  test('every LEGO piece is listed in lib/core/widgets/README.md', () {
    final readme = File('lib/core/widgets/README.md');
    final text = readme.existsSync() ? readme.readAsStringSync() : '';
    final missing = _dartFiles
        .where((p) => p.startsWith('lib/core/widgets/'))
        .map((p) => p.split('/').last)
        .where((name) => !text.contains(name))
        .toList();
    expect(
      missing,
      isEmpty,
      reason: 'Add one line per piece to lib/core/widgets/README.md.',
    );
  });
}
