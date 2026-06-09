import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

void main() => runApp(const FestMapApp());

class FestMapApp extends StatelessWidget {
  const FestMapApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '축제지도',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2563EB), useMaterial3: true),
      home: const MapPage(),
    );
  }
}

// 웹 메르카토르(EPSG:3857)
const double _kR = 6378137.0;
double _mx(double lng) => _kR * lng * math.pi / 180;
double _my(double lat) => _kR * math.log(math.tan(math.pi / 4 + lat * math.pi / 360));

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();

  double _w = 0, _h = 0;        // 약도 픽셀 크기
  List<double>? _hom;           // 메르카토르→픽셀 호모그래피(8)
  double _northAngle = 0;       // 약도상 '북'의 화면각(rad, y-down)
  String _event = '', _imageAsset = '';
  bool _ready = false;

  double? _meLat, _meLng;
  double? _headingDeg;
  String _status = '현재 위치를 약도 위에 표시 중…';

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    _init();
    _listenCompass();
  }

  @override
  void dispose() { _posSub?.cancel(); _compassSub?.cancel(); super.dispose(); }

  Future<void> _init() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/georef.json')) as Map;
    _event = (raw['event'] ?? '행사지도').toString();
    _imageAsset = 'assets/${raw['image']}';
    final c = raw['corners'] as Map;
    double lat(String k) => (c[k]['lat'] as num).toDouble();
    double lng(String k) => (c[k]['lng'] as num).toDouble();

    final bytes = (await rootBundle.load(_imageAsset)).buffer.asUint8List();
    final frame = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
    _w = frame.image.width.toDouble(); _h = frame.image.height.toDouble();

    final src = [
      [_mx(lng('topLeft')), _my(lat('topLeft'))],
      [_mx(lng('topRight')), _my(lat('topRight'))],
      [_mx(lng('bottomLeft')), _my(lat('bottomLeft'))],
      [_mx(lng('bottomRight')), _my(lat('bottomRight'))],
    ];
    final dst = [[0.0, 0.0], [_w, 0.0], [0.0, _h], [_w, _h]];
    _hom = _homography(src, dst);

    final refLat = (lat('topLeft') + lat('bottomRight')) / 2;
    final refLng = (lng('topLeft') + lng('bottomRight')) / 2;
    final p0 = _toPixel(refLat, refLng), p1 = _toPixel(refLat + 0.001, refLng);
    _northAngle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);

    setState(() => _ready = true);
    _locateMe();
  }

  Offset _toPixel(double la, double ln) {
    final h = _hom!, X = _mx(ln), Y = _my(la);
    final w = h[6] * X + h[7] * Y + 1;
    return Offset((h[0] * X + h[1] * Y + h[2]) / w, (h[3] * X + h[4] * Y + h[5]) / w);
  }

  // 픽셀(px,py) → CRS.simple 좌표(LatLng): lat = H-py(위가 북), lng = px
  LatLng _pixelToMap(Offset p) => LatLng(_h - p.dy, p.dx);

  List<double> _homography(List<List<double>> s, List<List<double>> d) {
    final A = <List<double>>[]; final b = <double>[];
    for (var i = 0; i < 4; i++) {
      final X = s[i][0], Y = s[i][1], px = d[i][0], py = d[i][1];
      A.add([X, Y, 1, 0, 0, 0, -px * X, -px * Y]); b.add(px);
      A.add([0, 0, 0, X, Y, 1, -py * X, -py * Y]); b.add(py);
    }
    return _solve(A, b);
  }

  List<double> _solve(List<List<double>> A, List<double> b) {
    final n = b.length;
    final M = [for (var i = 0; i < n; i++) [...A[i], b[i]]];
    for (var col = 0; col < n; col++) {
      var piv = col;
      for (var r = col + 1; r < n; r++) { if (M[r][col].abs() > M[piv][col].abs()) piv = r; }
      final t = M[col]; M[col] = M[piv]; M[piv] = t;
      final dd = M[col][col]; if (dd.abs() < 1e-15) continue;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = M[r][col] / dd;
        for (var cc = col; cc <= n; cc++) { M[r][cc] -= f * M[col][cc]; }
      }
    }
    return [for (var i = 0; i < n; i++) M[i][n] / M[i][i]];
  }

  void _listenCompass() {
    final ev = FlutterCompass.events;
    if (ev == null) return;
    _compassSub = ev.listen((e) { if (e.heading != null) setState(() => _headingDeg = e.heading); });
  }

  Future<void> _locateMe() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _status = '위치 권한이 거부되었습니다.'); return;
      }
      final p = await Geolocator.getCurrentPosition();
      setState(() { _meLat = p.latitude; _meLng = p.longitude; _status = '내 위치 표시 중'; });
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 1),
      ).listen((q) => setState(() { _meLat = q.latitude; _meLng = q.longitude; }));
    } catch (e) {
      setState(() => _status = '위치 오류: $e');
    }
  }

  LatLngBounds get _bounds => LatLngBounds(const LatLng(0, 0), LatLng(_h, _w));
  void _fitAll() => _map.fitCamera(CameraFit.bounds(bounds: _bounds, padding: const EdgeInsets.all(10)));

  void _centerOnMe() {
    if (_meLat == null) { _locateMe(); return; }
    _map.move(_pixelToMap(_toPixel(_meLat!, _meLng!)), math.max(_map.camera.zoom, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    LatLng? mePoint;
    if (_ready && _meLat != null && _meLng != null) mePoint = _pixelToMap(_toPixel(_meLat!, _meLng!));
    final facing = _northAngle + (_headingDeg ?? 0) * math.pi / 180;

    return Scaffold(
      appBar: AppBar(title: Text(_event), actions: [
        IconButton(tooltip: '약도 전체 보기', onPressed: _ready ? _fitAll : null, icon: const Icon(Icons.fit_screen)),
      ]),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  crs: const CrsSimple(),
                  initialCameraFit: CameraFit.bounds(bounds: _bounds, padding: const EdgeInsets.all(10)),
                  minZoom: -6, maxZoom: 4,
                  backgroundColor: const Color(0xFFEFEFEF),
                ),
                children: [
                  OverlayImageLayer(overlayImages: [
                    OverlayImage(bounds: _bounds, imageProvider: AssetImage(_imageAsset)),
                  ]),
                  if (mePoint != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: mePoint,
                        width: 130, height: 130,
                        child: CustomPaint(painter: _MePainter(facing: facing)),
                      ),
                    ]),
                ],
              ),
              Positioned(
                left: 12, right: 12, bottom: 12,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    child: Row(children: [
                      Expanded(child: Text(_status, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                      FilledButton.icon(
                        onPressed: _centerOnMe,
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('내 위치'),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
    );
  }
}

// 현위치 점 + 방향 콘 (크기 고정, 줌과 무관)
class _MePainter extends CustomPainter {
  _MePainter({required this.facing});
  final double facing; // 화면각(rad, y-down)
  static const _blue = Color(0xFF1D4ED8);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const half = 0.5, r = 56.0;
    final ang = facing;
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + r * math.cos(ang - half), c.dy + r * math.sin(ang - half))
      ..arcToPoint(Offset(c.dx + r * math.cos(ang + half), c.dy + r * math.sin(ang + half)),
          radius: const Radius.circular(r))
      ..close();
    canvas.drawPath(path, Paint()
      ..shader = const RadialGradient(colors: [Color(0xE63B82F6), Color(0x143B82F6)])
          .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF1D4ED8));
    canvas.drawCircle(c, 13, Paint()..color = Colors.white);
    canvas.drawCircle(c, 9, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant _MePainter old) => old.facing != facing;
}
