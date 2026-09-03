import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 即時 Google 地圖，鏡頭置中於裝置目前位置，並用地圖原生的
/// 「顯示目前位置」藍點（myLocationEnabled）標示自身位置。右下角有一個
/// 「回到目前位置」按鈕，可在拖曳地圖後重新置中。
/// Android 金鑰見 android/local.properties，iOS 金鑰見
/// ios/Flutter/ApiKeys.xcconfig。
class LiveGoogleMap extends StatefulWidget {
  const LiveGoogleMap({super.key});

  @override
  State<LiveGoogleMap> createState() => _LiveGoogleMapState();
}

class _LiveGoogleMapState extends State<LiveGoogleMap> {
  static const _fallbackPosition = LatLng(23.0468, 120.2500); // 南台科技大學一帶（定位失敗時的備援）
  static const _zoom = 17.0;
  static const _locationTimeout = Duration(seconds: 8); // 避免收不到定位訊號時無限期卡住

  GoogleMapController? _controller;
  LatLng? _initialPosition;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _resolveCurrentPosition();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<LatLng?> _requestCurrentPosition() async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final current = await Geolocator.getCurrentPosition().timeout(_locationTimeout);
          return LatLng(current.latitude, current.longitude);
        }
      }
    } catch (_) {
      // 定位失敗（權限被拒、服務關閉、逾時等）時交由呼叫端處理備援，
      // 避免（尤其 iOS）在收不到定位訊號時無限期卡在轉圈圈。
    }
    return null;
  }

  Future<void> _resolveCurrentPosition() async {
    final position = await _requestCurrentPosition();
    if (mounted) {
      setState(() {
        _initialPosition = position ?? _fallbackPosition;
        _locationGranted = position != null;
      });
    }
  }

  Future<void> _recenter() async {
    final position = await _requestCurrentPosition();
    if (position == null || !mounted) return;
    setState(() => _locationGranted = true);
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(position, _zoom));
  }

  @override
  Widget build(BuildContext context) {
    final initialPosition = _initialPosition;
    if (initialPosition == null) {
      return const ColoredBox(color: Colors.white, child: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initialPosition, zoom: _zoom),
          onMapCreated: (controller) => _controller = controller,
          myLocationEnabled: _locationGranted,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: '回到目前位置',
            onPressed: _recenter,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
