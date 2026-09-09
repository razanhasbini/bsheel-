import 'dart:math' as math;
import 'dart:ui';

/// TopoJSON delta decoding. Rings retain their holes and island polygons.
class CountryGeometry {
  CountryGeometry(this.id, this.name, this.rings);
  final String id, name;
  final List<List<Offset>> rings;

  static List<CountryGeometry> decode(Map<String, dynamic> topology) {
    final transform = topology['transform'] as Map;
    final scale = (transform['scale'] as List).cast<num>();
    final translate = (transform['translate'] as List).cast<num>();
    final arcs = (topology['arcs'] as List).map((raw) {
      num x = 0, y = 0;
      return (raw as List).map((point) {
        x += (point as List)[0] as num;
        y += point[1] as num;
        return Offset((x * scale[0] + translate[0]).toDouble(),
            (y * scale[1] + translate[1]).toDouble());
      }).toList();
    }).toList();
    List<Offset> ring(List indices) {
      final points = <Offset>[];
      for (final index in indices.cast<int>()) {
        final segment =
            index < 0 ? arcs[~index].reversed.toList() : arcs[index];
        points.addAll(points.isEmpty ? segment : segment.skip(1));
      }
      return points;
    }

    final geometries = ((topology['objects'] as Map)['countries']
        as Map)['geometries'] as List;
    return geometries.map((raw) {
      final item = raw as Map;
      final polygons =
          item['type'] == 'Polygon' ? [item['arcs']] : item['arcs'] as List;
      return CountryGeometry(item['id'].toString().padLeft(3, '0'),
          (item['properties'] as Map)['name'] as String, [
        for (final polygon in polygons)
          for (final boundary in polygon as List) ring(boundary as List)
      ]);
    }).toList();
  }
}

/// One projection shared by coastline, discovery overlays and pin positions.
class MapProjection {
  MapProjection(Iterable<CountryGeometry> shapes, this.size) {
    final points =
        shapes.expand((s) => s.rings).expand((r) => r).map(mercator).toList();
    if (points.isEmpty) {
      bounds = const Rect.fromLTRB(-math.pi, -math.pi, math.pi, math.pi);
    } else {
      bounds = Rect.fromLTRB(
          points.map((p) => p.dx).reduce(math.min),
          points.map((p) => p.dy).reduce(math.min),
          points.map((p) => p.dx).reduce(math.max),
          points.map((p) => p.dy).reduce(math.max));
    }
    scale = math.min((size.width - 32) / math.max(bounds.width, 0.001),
        (size.height - 32) / math.max(bounds.height, 0.001));
  }
  final Size size;
  late final Rect bounds;
  late final double scale;
  static Offset mercator(Offset lonLat) {
    final lat = lonLat.dy.clamp(-85.0, 85.0) * math.pi / 180;
    return Offset(
        lonLat.dx * math.pi / 180, -math.log(math.tan(math.pi / 4 + lat / 2)));
  }

  Offset project(Offset lonLat) =>
      (mercator(lonLat) - bounds.center) * scale +
      Offset(size.width / 2, size.height / 2);
  Path path(CountryGeometry geometry) {
    final result = Path()..fillType = PathFillType.evenOdd;
    for (final ring in geometry.rings) {
      if (ring.isEmpty) continue;
      final points = ring.map(project).toList();
      result.moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        result.lineTo(p.dx, p.dy);
      }
      result.close();
    }
    return result;
  }
}
