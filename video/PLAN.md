# فيديو المنظومة — خطة الإكمال (للجلسة التالية)

## الحالة
- **تحديث 22:10:** طلب المستخدم صوتاً من فئة الاستوديو؛ اعتُمد Tariq (18HMWpalD7cscJTD8lEY). حالة المقاطع في voices.json (المصدر الأحدث، ويغلب ما تحته).
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
3. `python3 build.py` ثم `./render_all.sh final_video.mp4` (Bash بخيار run_in_background؛ نحو 8 دقائق).
4. `python3 music.py TOTAL 11.6 <start s13+0.2> music.wav` ثم flac.
5. الجسر: ادفع video.mp4 وmusic.flac إلى فرع `video-assets-tmp` في dc-app (رسالة الإيداع فيها [skip ci])، واطلب download_url من contents API (صالح 5 دقائق)، ثم creative_attach_reference_file إلى الـflow.
6. `python3 mixcmd.py` يطبع أمر الصندوق كاملاً (يكتب الناتج في $OUT). مدخلات الصندوق: video.mp4 وmusic.flac (عقد المرفقات) وsNN.mp3 (generation_id لكل مقطع). جُرّب على نسخة اختبار: الصوت ≈ -16 LUFS والموسيقى ≈ -26 في الفواصل.
7. افحص: المدة ≤ 4:00، الجهارة ≈ -16 LUFS، إطارات عيّنة، ونسخ الصوت.
8. سلّم بـcreative_show_flow_results، واحذف فرع video-assets-tmp.

## المصادر
- اللقطات: فرع `visual-shots` في dc-app. الشعار والشريط: assets/brand في main.

## نسخة «رصد» (2026-11-15)
- الاسم في الفيديو «منظومة رَصْد»، أمثلة تطبيقية بعد الأقسام (e03…e12)، المدة ≤ 6:30، شاشات أكبر.
- التقدم في voices2.json، والنصوص الجديدة في new_texts.json، والمدد في durs2.json (المقاطع غير المذكورة في new_texts تبقى من نسخة طارق السابقة: voices2.keep).
- البناء: `python3 build2.py` (يستخدم examples.py وstyle_ex.css)، ثم `./render_all.sh rasd_video.mp4`.
- الخلط: مثل mixcmd.py لكن بترتيب ORDER في build2 وtimeline2.json؛ الكسب لكل مقطع = -16.5 - lufs.
- التسليم: مخرج الصندوق → asset → preview_url (mono 128k) يُنزَّل عبر المتصفح المدمج إلى التنزيلات (وافق المستخدم مسبقاً) → stage → دمج مع الفيديو المحلي (+3.4dB) → SendUserFile + device_commit_files.
