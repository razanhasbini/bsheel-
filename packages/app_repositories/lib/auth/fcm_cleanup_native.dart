import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> deleteLocalFcmToken() async {
  await FirebaseMessaging.instance.deleteToken();
}
