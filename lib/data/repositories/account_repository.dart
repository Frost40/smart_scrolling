import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by a save when the row was saved elsewhere first (its revision moved on).
class AccountConflict implements Exception {
  const AccountConflict();
}

/// The person's profile row and this phone's devices row, as loaded.
typedef AccountRows = ({
  Map<String, dynamic> profile,
  Map<String, dynamic> device,
});

/// The only door to sign-in and to the person's `profiles` and `devices` rows.
class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentUser != null;
  String? get email => _client.auth.currentUser?.email;
  String? get userId => _client.auth.currentUser?.id;

  /// The signed-in user id after every auth event, or null when signed out.
  Stream<String?> get authChanges =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
    OAuthProvider.google,
    scopes: 'openid',
    redirectTo: 'com.smartscrolling.app://login-callback',
    authScreenLaunchMode: LaunchMode.externalApplication,
  );

  /// Only for the debug Test login (A3-8).
  Future<void> signInWithPassword(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);

  Future<Map<String, dynamic>> exportData() async =>
      Map<String, dynamic>.from(await _client.rpc('export_my_data') as Map);

  Future<void> deleteData() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Sign in first');
    // Keep this destructive request bound to the confirming account across auth changes.
    return _client
        .rpc('delete_my_data')
        .setHeader('Authorization', 'Bearer $token');
  }

  /// Loads the profile and this phone's settings; both rows are made on first sign-in.
  Future<AccountRows> load(String installation) async {
    final me = userId!;
    await _client
        .from('profiles')
        .upsert({'user_id': me}, onConflict: 'user_id', ignoreDuplicates: true);
    await _client
        .from('devices')
        .upsert(
          {'user_id': me, 'installation_id': installation},
          onConflict: 'user_id,installation_id',
          ignoreDuplicates: true,
        );
    final profile = await _client
        .from('profiles')
        .select()
        .eq('user_id', me)
        .single();
    final device = await _client
        .from('devices')
        .select()
        .eq('user_id', me)
        .eq('installation_id', installation)
        .single();
    return (profile: profile, device: device);
  }

  Future<bool> hasFollows() async {
    for (final table in ['user_topics', 'user_sources']) {
      final rows = await _client
          .from(table)
          .select('user_id')
          .eq('user_id', userId!)
          .eq('choice', 'follow')
          .limit(1);
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  /// Saves [changes] only if the row is still at [revision] (A3-14).
  Future<Map<String, dynamic>> saveProfile(
    Map<String, dynamic> changes,
    int revision,
  ) => _guarded(
    _client
        .from('profiles')
        .update(changes)
        .eq('user_id', userId!)
        .eq('revision', revision)
        .select(),
  );

  /// Saves [changes] to this phone's row only if it is still at [revision] (A3-14).
  Future<Map<String, dynamic>> saveDevice(
    String installation,
    Map<String, dynamic> changes,
    int revision,
  ) => _guarded(
    _client
        .from('devices')
        .update(changes)
        .eq('user_id', userId!)
        .eq('installation_id', installation)
        .eq('revision', revision)
        .select(),
  );

  Future<Map<String, dynamic>> _guarded(
    Future<List<Map<String, dynamic>>> update,
  ) async {
    final rows = await update;
    if (rows.isEmpty) throw const AccountConflict();
    return rows.first;
  }
}
