import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Android's notification permission and app-notification settings.
/// This does not itself deliver push notifications; it only manages permission.
class NotificationPermissionService {
  NotificationPermissionService._();

  static const MethodChannel _channel =
      MethodChannel('com.finora.app/notifications');

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isGranted() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!isAndroid) return;
    await _channel.invokeMethod<void>('openSettings');
  }
}
