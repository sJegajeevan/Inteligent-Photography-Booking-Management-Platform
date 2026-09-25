import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class CustomerLocation {
  const CustomerLocation(this.latitude, this.longitude);
  final double latitude, longitude;
}

/// One foreground fix, requested only by an explicit customer action.
/// Coordinates are never persisted or logged by this service.
class LocationService {
  Future<CustomerLocation> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFailure(
          'Location services are off. Enable them in device settings and try Near Me again.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(
          'Location permission is blocked. Allow location for SnapSync in app or browser settings to use Near Me.',
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure(
          'Location permission was not granted. You can still browse all studios.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        throw const LocationFailure(
          'Your device returned an invalid location. Please try again.',
        );
      }
      return CustomerLocation(position.latitude, position.longitude);
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(
        'Finding your location timed out. Try Near Me again with a better GPS signal.',
      );
    } on LocationServiceDisabledException {
      throw const LocationFailure(
        'Location services are off. Enable them in device settings to use Near Me.',
      );
    } catch (_) {
      throw const LocationFailure(
        'Unable to get your location. Check location permissions and try again. You can still browse all studios.',
      );
    }
  }
}
