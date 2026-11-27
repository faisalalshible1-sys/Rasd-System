// مواقع المشاريع وبلاغات الصيانة على الخريطة (الإصدار 1.13.0، الترحيل 44).

/// وسط بنغازي: مركز الخريطة الافتراضي حين لا نقاط مسجَّلة.
const double geoDefaultLat = 32.1167;
const double geoDefaultLng = 20.0667;

/// نقطة موقع لمشروع أو لبلاغ صيانة (واحدة لكل منهما).
class GeoPoint {
  const GeoPoint({required this.id, this.projectId, this.requestId, required this.lat, required this.lng, this.note = ''});

  final String id;
  final String? projectId;
  final String? requestId;
  final double lat;
  final double lng;
  final String note;

  bool get isProject => projectId != null;

  factory GeoPoint.fromMap(Map<String, dynamic> m) => GeoPoint(
        id: '${m['id'] ?? ''}',
        projectId: m['project_id'] as String?,
        requestId: m['request_id'] as String?,
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        note: '${m['note'] ?? ''}',
      );
}

bool geoValid(double lat, double lng) => lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

/// يقرأ إحداثيات من نص: «32.1167, 20.0667» أو «32.1167 20.0667» أو رابط خرائط (…@32.1167,20.0667… أو ?q=32.1167,20.0667).
/// الأعداد العربية الهندية والفاصلة العربية «،» مقبولة. يعيد null إن لم يجد زوجاً صالحاً.
({double lat, double lng})? parseCoordinates(String input) {
  var t = input.trim();
  if (t.isEmpty) return null;
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < arabic.length; i++) {
    t = t.replaceAll(arabic[i], '$i');
  }
  t = t.replaceAll('٫', '.').replaceAll('،', ',');
  final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(t);
  final m = at ?? RegExp(r'(-?\d+(?:\.\d+)?)\s*[,\s;]\s*(-?\d+(?:\.\d+)?)').firstMatch(t);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null || !geoValid(lat, lng)) return null;
  return (lat: lat, lng: lng);
}

String geoText(double lat, double lng) => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

/// رابط OpenStreetMap لموقع (للفتح في المتصفح).
String geoOsmUrl(double lat, double lng) => 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';
