import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/models/track_point.dart';

/// Cache key for a rider's marker icon: changes when the rider's state
/// (in group / dropped off) or displayName changes, so a new icon is
/// generated instead of showing a stale color or initial letter.
String markerIconKey(RiderDoc rider) =>
    '${rider.userId}_${rider.state}_${rider.displayName}';

Set<Marker> buildMarkers(
  List<RiderDoc> riders, {
  Map<String, BitmapDescriptor> icons = const {},
}) {
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
            icon: icons[markerIconKey(r)] ??
                BitmapDescriptor.defaultMarkerWithHue(
                  r.state == RiderState.droppedOff
                      ? BitmapDescriptor.hueRed
                      : BitmapDescriptor.hueOrange,
                ),
            anchor: const Offset(0.5, 0.5),
          ))
      .toSet();
}

/// Builds the red trail showing the route the ride's creator has traveled,
/// so a rider who gets separated from the group can see which road was
/// taken.
Set<Polyline> buildTrackPolyline(List<TrackPoint> points) {
  if (points.length < 2) return {};
  return {
    Polyline(
      polylineId: const PolylineId('creatorTrack'),
      points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
      color: Colors.redAccent,
      width: 4,
    ),
  };
}

/// Renders a circular marker icon with the rider's initial letter, so the
/// map shows who each dot is instead of an unlabeled colored pointer.
///
/// [renderSize] is the canvas resolution (kept high for a crisp image);
/// [displaySize] is the logical on-map size in points, passed to
/// [BitmapDescriptor.bytes] so the icon doesn't appear oversized regardless
/// of how finely it was rendered.
Future<BitmapDescriptor> createInitialMarkerIcon(
  String displayName,
  Color color, {
  double renderSize = 128,
  double displaySize = 34,
}) async {
  final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final circlePaint = Paint()..color = color;
  canvas.drawCircle(
      Offset(renderSize / 2, renderSize / 2), renderSize / 2, circlePaint);

  final borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = renderSize * 0.06;
  canvas.drawCircle(
    Offset(renderSize / 2, renderSize / 2),
    renderSize / 2 - borderPaint.strokeWidth / 2,
    borderPaint,
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: initial,
      style: TextStyle(
        color: Colors.white,
        fontSize: renderSize * 0.5,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(
    canvas,
    Offset((renderSize - textPainter.width) / 2,
        (renderSize - textPainter.height) / 2),
  );

  final picture = recorder.endRecording();
  final image =
      await picture.toImage(renderSize.toInt(), renderSize.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: displaySize,
    height: displaySize,
  );
}
