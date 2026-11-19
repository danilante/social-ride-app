import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';

Set<Marker> buildMarkers(List<RiderDoc> riders) {
  return riders
      .where((r) => r.lat != null && r.lng != null)
      .map((r) => Marker(
            markerId: MarkerId(r.userId),
            position: LatLng(r.lat!, r.lng!),
            infoWindow: InfoWindow(
              title: r.displayName,
              snippet: r.state == RiderState.droppedOff
                  ? 'Staccato${r.distanceFromGroupMeters != null ? " ~${r.distanceFromGroupMeters!.round()}m" : ""}'
                  : null,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              r.state == RiderState.droppedOff
                  ? BitmapDescriptor.hueRed
                  : BitmapDescriptor.hueGreen,
            ),
          ))
      .toSet();
}
