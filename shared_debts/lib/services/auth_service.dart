import 'package:firebase_auth/firebase_auth.dart';
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
    } catch (_) {
      // Ignored if already initialized
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
    await _ensureInitialized();

    try {
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      final String? idToken = account.authentication.idToken;

      String? accessToken;
      try {
        final clientAuth = await account.authorizationClient
            .authorizationForScopes(['email', 'profile']);
        accessToken = clientAuth?.accessToken;
      } catch (_) {
        // Access token is optional for Firebase Auth when idToken is present
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User canceled sign-in
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
