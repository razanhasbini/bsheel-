import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A sign-in failure that must survive the navigation that follows it.
///
/// The phone callback discovers the failure on a route it is about to leave,
/// so anything shown from that context — a snackbar in particular — is
/// attached to a widget being disposed and never appears. That is exactly
/// what happened: a refused number bounced silently back to the login page
/// with nothing said, which reads as the app doing nothing at all.
///
/// Parking the code here instead lets the destination raise it once it is
/// actually on screen, and lets it be a dialog the user has to acknowledge
/// rather than a toast that can be missed.
final pendingAuthErrorProvider = StateProvider<String?>((ref) => null);
