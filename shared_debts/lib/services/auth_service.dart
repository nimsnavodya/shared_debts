import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _customAuth = auth,
        _customGoogleSignIn = googleSignIn;

  final FirebaseAuth? _customAuth;
  final GoogleSignIn? _customGoogleSignIn;
  bool _initialized = false;

  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;
  GoogleSignIn get _googleSignIn =>
      _customGoogleSignIn ?? GoogleSignIn.instance;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _googleSignIn.initialize();
    } catch (e) {
      debugPrint('AuthService: initialize note: $e');
    }
    _initialized = true;
  }

  Stream<User?> get authStateChanges {
    try {
      return _auth.authStateChanges();
    } catch (_) {
      return Stream.value(null);
    }
  }

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    debugPrint('AuthService: Ensuring GoogleSignIn is initialized...');
    await _ensureInitialized();

    try {
      debugPrint('AuthService: Calling GoogleSignIn.instance.authenticate()...');
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      debugPrint('AuthService: Account received: ${account.email}');

      final String? idToken = account.authentication.idToken;
      debugPrint('AuthService: idToken present: ${idToken != null}');

      String? accessToken;
      try {
        final clientAuth = await account.authorizationClient
            .authorizationForScopes(['email', 'profile']);
        accessToken = clientAuth?.accessToken;
      } catch (e) {
        debugPrint('AuthService: Scopes authorization note: $e');
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      debugPrint('AuthService: Signing in with credential in FirebaseAuth...');
      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      debugPrint('AuthService: GoogleSignInException: [${e.code}] ${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
