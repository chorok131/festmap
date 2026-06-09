import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _map = MapController();

  static const LatLng _seoulForest = LatLng(37.5438, 127.0405);

  // 약도 오버레이의 세 모서리 — PC 정렬도구가 내보낸 georef.json에서 로드.
  LatLng? _topLeft, _bottomLeft, _bottomRight;
  double _opacity = 0.65;
  bool _showOverlay = true;

  LatLng? _me;          // 현위치
  double? _headingDeg;  // 바라보는 방향(도, 0=북, 시계방향)
  String _status = '약도(georef.json)를 불러왔습니다. "내 위치"로 현위치를 표시하세요.';

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  void _setStatus(String s) => setState(() => _status = s);

  @override
  void initState() {
    super.initState();
    _loadGeoref();
    _listenCompass();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  // 정렬도구가 만든 georeference 로드 (행사 = 데이터)
  Future<void> _loadGeoref() async {
    try {
      final raw = await rootBundle.loadString('assets/georef.json');
      final c = (jsonDecode(raw) as Map)['corners'] as Map;
      LatLng p(String k) =>
          LatLng((c[k]['lat'] as num).toDouble(), (c[k]['lng'] as num).toDouble());
      setState(() {
        _topLeft = p('topLeft');
        _bottomLeft = p('bottomLeft');
        _bottomRight = p('bottomRight');
      });
    } catch (e) {
      _setStatus('georef.json 로드 실패: $e');
    }
  }

  // 나침반(바라보는 방향) 구독
  void _listenCompass() {
    final ev = FlutterCompass.events;
    if (ev == null) return; // 기기에 자기센서 없음(시뮬레이터 등)
    _compassSub = ev.listen((e) {
      if (e.heading == null) return;
      setState(() => _headingDeg = e.heading);
    });
  }

  Future<void> _locateMe() async {
    _setStatus('내 위치 찾는 중…');
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _setStatus('위치 권한이 거부되었습니다.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
      _map.move(_me!, 17);
      // 이동하며 실시간 추적
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 1),
      ).listen((p) => setState(() => _me = LatLng(p.latitude, p.longitude)));
      _setStatus('내 위치 표시 중 · 방향 ${_headingDeg?.round() ?? '–'}°');
    } catch (e) {
      _setStatus('위치 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGeoref = _topLeft != null && _bottomLeft != null && _bottomRight != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('축제지도 · 서울숲 정원박람회'),
        actions: [
          IconButton(
            tooltip: _showOverlay ? '약도 숨기기' : '약도 보이기',
            icon: Icon(_showOverlay ? Icons.layers : Icons.layers_clear),
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(initialCenter: _seoulForest, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.festmap.app',
                maxZoom: 19,
              ),
              if (_showOverlay && hasGeoref)
                OverlayImageLayer(
                  overlayImages: [
                    RotatedOverlayImage(
                      imageProvider: const AssetImage('assets/seoulforest_map.png'),
                      topLeftCorner: _topLeft!,
                      bottomLeftCorner: _bottomLeft!,
                      bottomRightCorner: _bottomRight!,
                      opacity: _opacity,
                    ),
                  ],
                ),
              if (_me != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _me!,
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      child: _MeMarker(headingDeg: _headingDeg),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap 기여자')],
              ),
            ],
          ),

          Positioned(
            left: 12, right: 12, bottom: 12,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_status, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    Row(
                      children: [
                        const Text('투명도'),
                        Expanded(
                          child: Slider(
                            value: _opacity,
                            onChanged: (v) => setState(() => _opacity = v),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _locateMe,
                          icon: const Icon(Icons.navigation, size: 18),
                          label: const Text('내 위치'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 네이버 지도식 현위치 + 바라보는 방향(부채꼴 콘) 마커
class _MeMarker extends StatelessWidget {
  const _MeMarker({this.headingDeg});
  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    // 지도는 정북 고정 → 콘을 heading(시계방향)만큼 회전
    final angle = (headingDeg ?? 0) * math.pi / 180;
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        size: const Size(96, 96),
        painter: _ConePainter(showCone: true),
      ),
    );
  }
}

class _ConePainter extends CustomPainter {
  _ConePainter({required this.showCone});
  final bool showCone;
  static const _blue = Color(0xFF1D4ED8);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);

    // 방향 부채꼴(위쪽 = heading 방향). 네이버처럼 또렷한 빔.
    if (showCone) {
      const half = 0.46; // 약 ±26°
      const r = 50.0;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.sin(-half), c.dy - r * math.cos(-half))
        ..arcToPoint(
          Offset(c.dx + r * math.sin(half), c.dy - r * math.cos(half)),
          radius: const Radius.circular(r),
        )
        ..close();
      final cone = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xCC2563EB), Color(0x122563EB)],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawPath(path, cone);
    }

    // 현위치 점(흰 테두리 + 파란 점)
    canvas.drawCircle(c, 11, Paint()..color = Colors.white);
    canvas.drawCircle(c, 8, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant _ConePainter old) => old.showCone != showCone;
}
