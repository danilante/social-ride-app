import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';

/// Cache key for a rider's marker icon: changes when the rider's state
/// (in group / dropped off) changes, so a new icon color is generated.
String markerIconKey(RiderDoc rider) => '${rider.userId}_${rider.state}';

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
          ))
      .toSet();
}

/// Renders a circular marker icon with the rider's initial letter, so the
/// map shows who each dot is instead of an unlabeled colored pointer.
Future<BitmapDescriptor> createInitialMarkerIcon(
  String displayName,
  Color color, {
  double size = 96,
}) async {
  final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final circlePaint = Paint()..color = color;
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

  final borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.06;
  canvas.drawCircle(
    Offset(size / 2, size / 2),
    size / 2 - borderPaint.strokeWidth / 2,
    borderPaint,
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: initial,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.5,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}
