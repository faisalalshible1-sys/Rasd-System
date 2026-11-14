# فيديو المنظومة — خطة الإكمال (للجلسة التالية)

## الحالة
- الصوت: ElevenLabs، flow `3SLfRtdz9IE7VTuE7BYI` (مساحة العمل f45f2fd3…)، الصوت `6cFz1T5FQxQS8Xk88qQi` (Ahmed – Deep Arabic Documentary)، النموذج `eleven_v4`.
- المقاطع الجاهزة (المعتمدة أولاً):
  - s01 `KXB0iTI6kqsnCxxqu5U8` (17.006s)
  - s02 `XcxeQ6yGklXMsbQK1P8U` (14.838s)
  - s03 `Nsi5T49J3DPTH9Ltcl2D` (17.476s)
  - s04 `KQLio6U3FIvbr0DreFrC` (12.356s)
  - s06 `iOGWkfoAavpt98eHAsOG` (13.087s)
  - s08 `pGQNQBEfBJbOJN10y3gn` (14.916s)
  - s10 `CrPl5Qeqiha5j1TSt80F` (18.756s)
- الباقية: s05 s07 s09 s11 s12 s13 (نصوصها في TEXT داخل build.py). توقفت لأن ElevenLabs عطّلت الخطة المجانية («Unusual activity»). تحتاج اشتراكاً مدفوعاً من المستخدم.

## خطوات الإكمال
1. ولّد المقاطع الستة (creative_generate_speech، flow أعلاه، الصوت والنموذج أعلاه).
2. قِس مدتها في صندوق ElevenLabs (ffprobe) وضعها في durs.json (احذف "est").
3. `python3 build.py` ثم صيّر على عمليتين: `node render.js 0 N1 a.mp4` و`node render.js N1 N b.mp4` (N = TOTAL×30)، ثم ffmpeg concat (-c copy).
4. `python3 music.py TOTAL 11.6 <start s13+0.2> music.wav` ثم flac.
5. الجسر: ادفع video.mp4 وmusic.flac إلى فرع `video-assets-tmp` في dc-app (رسالة الإيداع فيها [skip ci])، واطلب download_url من contents API (صالح 5 دقائق)، ثم creative_attach_reference_file إلى الـflow.
6. اخلط في الصندوق: الصوت بـadelay عند start[k] من timeline.json، والموسيقى مخفّضة تحت الصوت (sidechaincompress)، وإخراج AAC 192k مع نسخ الفيديو.
7. افحص: المدة ≤ 4:00، الجهارة ≈ -16 LUFS، إطارات عيّنة، ونسخ الصوت.
8. سلّم بـcreative_show_flow_results، واحذف فرع video-assets-tmp.

## المصادر
- اللقطات: فرع `visual-shots` في dc-app. الشعار والشريط: assets/brand في main.
