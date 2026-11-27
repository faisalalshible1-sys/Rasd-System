import 'package:dc_app/geo.dart';
import 'package:dc_app/screens/home_shell.dart' show Tabs;
import 'package:dc_app/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// مواقع الخريطة (الترحيل 44): قراءة الإحداثيات من النص والروابط، والتحقق من النطاق.
void main() {
  test('قراءة «العرض, الطول» بصيغ مختلفة', () {
    expect(parseCoordinates('32.1167, 20.0667'), (lat: 32.1167, lng: 20.0667));
    expect(parseCoordinates('32.1167 20.0667'), (lat: 32.1167, lng: 20.0667));
    expect(parseCoordinates('  -33.5;151.2  '), (lat: -33.5, lng: 151.2));
    expect(parseCoordinates('٣٢٫١١٦٧، ٢٠٫٠٦٦٧'), (lat: 32.1167, lng: 20.0667), reason: 'أرقام وفاصلة عربية');
  });

  test('قراءة الإحداثيات من رابط خرائط', () {
    expect(parseCoordinates('https://www.google.com/maps/place/x/@32.1167,20.0667,17z'), (lat: 32.1167, lng: 20.0667));
    expect(parseCoordinates('https://maps.example.com/?q=32.1,20.2'), (lat: 32.1, lng: 20.2));
  });

  test('المرفوض: فارغ ونص بلا أرقام وخارج النطاق', () {
    expect(parseCoordinates(''), isNull);
    expect(parseCoordinates('بنغازي'), isNull);
    expect(parseCoordinates('91, 20'), isNull, reason: 'العرض أكبر من 90');
    expect(parseCoordinates('32, 181'), isNull, reason: 'الطول أكبر من 180');
    expect(geoValid(90, 180), isTrue);
    expect(geoValid(-90.1, 0), isFalse);
  });

  test('نقطة الموقع من صف الجدول', () {
    final p = GeoPoint.fromMap({'id': 'g', 'project_id': 'p1', 'request_id': null, 'lat': 32, 'lng': 20.5, 'note': 'البوابة'});
    expect(p.isProject, isTrue);
    expect(p.lng, 20.5);
    expect(GeoPoint.fromMap({'id': 'g2', 'request_id': 'r1', 'lat': 1.5, 'lng': 2}).isProject, isFalse);
    expect(geoText(32.116712, 20.066698), '32.11671, 20.06670');
  });

  test('صفحة الخريطة ثابتة الرقم وفي قسم المخاطر', () {
    expect(Tabs.siteMap, 23);
    expect(AppState.sectionOf(Tabs.siteMap), 'risks');
  });
}
