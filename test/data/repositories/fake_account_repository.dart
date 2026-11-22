import 'dart:async';

import 'package:smart_scrolling/data/repositories/account_repository.dart';

/// Stands in for Supabase in tests: one person, one profile row, one device row.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.signedIn = true, this.follows = true});

  bool follows;

  @override
  Future<bool> hasFollows() async => follows;

  bool signedIn, googleOpened = false, failLoad = false;
  final _auth = StreamController<String?>.broadcast();
  final deviceSaves = <Map<String, dynamic>>[];
  Map<String, dynamic> profile = {
    'user_id': 'user-1',
    'languages': ['en'],
    'discover_filter': 'mix',
    'practice_filter': 'mix',
    'revision': 1,
  };
  Map<String, dynamic> device = {
    'user_id': 'user-1',
    'installation_id': 'phone',
    'theme_mode': 'system',
    'reduce_motion': false,
    'high_contrast': false,
    'text_scale': 1,
    'offline_mode': 'standard',
    'download_on_mobile_data': false,
    'revision': 1,
  };

  @override
  bool get isSignedIn => signedIn;
  @override
  String? get email => signedIn ? 'agent@smartscrolling.test' : null;
  @override
  String? get userId => signedIn ? 'user-1' : null;
  @override
  Stream<String?> get authChanges => _auth.stream;

  @override
  Future<void> signInWithGoogle() async => googleOpened = true;

  @override
  Future<void> signInWithPassword(String email, String password) async {
    signedIn = true;
    _auth.add(userId);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _auth.add(null);
  }

  @override
  Future<Map<String, dynamic>> exportData() async => {
    'profiles': [profile],
    'devices': [device],
  };

  @override
  Future<void> deleteData() async {
    profile = {
      ...profile,
      'weekly_goal_days': null,
      'discover_filter': 'mix',
      'practice_filter': 'mix',
      'revision': (profile['revision'] as int) + 1,
    };
    device = {
      ...device,
      'reminder_time': null,
      'theme_mode': 'system',
      'reduce_motion': false,
      'high_contrast': false,
      'text_scale': 1,
      'offline_mode': 'standard',
      'download_on_mobile_data': false,
      'revision': (device['revision'] as int) + 1,
    };
    follows = false;
  }

  @override
  Future<AccountRows> load(String installation) async {
    if (failLoad) throw Exception('offline');
    return (profile: {...profile}, device: {...device});
  }

  @override
  Future<Map<String, dynamic>> saveProfile(
    Map<String, dynamic> changes,
    int revision,
  ) async {
    if (revision != profile['revision']) throw const AccountConflict();
    profile = {...profile, ...changes, 'revision': revision + 1};
    return {...profile};
  }

  @override
  Future<Map<String, dynamic>> saveDevice(
    String installation,
    Map<String, dynamic> changes,
    int revision,
  ) async {
    deviceSaves.add(changes);
    if (revision != device['revision']) throw const AccountConflict();
    device = {...device, ...changes, 'revision': revision + 1};
    return {...device};
  }
}
