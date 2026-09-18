# سجل تطوير قاعدة البيانات (DB Developing History)

---
## 2026-09-17 05:48 | Gemini 3.8 Flash
- **إنشاء DIRECTORY في Oracle**:
  - تم إنشاء DIRECTORY باسم `W_MEDIA_DIR` يشير إلى مسار الملفات المحلي: `C:\ultramsg-bridge\public`.
  - يتيح هذا الدليل لقاعدة البيانات قراءة الملفات والمستندات والصور المخصصة للإرسال عبر واتساب.
- **تحديث PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE**:
  - ربط الـ Package مباشرة بنظام OpenWA (whAPI) على `http://127.0.0.1:2785/arslanhook/send`.
  - معالجة مشاكل الترميز العربي الناتجة عن قاعدة البيانات `WE8MSWIN1252` عبر إرسال البايتات الحقيقية دون تشويه UTF-8 المزدوج.
  - دعم إرسال الرسائل النصية، الصور، المستندات والملفات (URLs أو Base64 أو أسماء الملفات في W_MEDIA_DIR).
  - دعم تسوية وتنسيق أرقام الهواتف (Normalize Phone) للأرقام اليمنية والدولية.
  - معالجة طابور الرسائل `ACCOUNTS.W_MSG_QUEUE` وأرشفة الرسائل الناجحة في `ACCOUNTS.W_MSG_ARCHIVE` وزيادة عداد المحاولات `SEND_ATTEMPT` عند الفشل.

---
## 2026-09-17 09:20 | Gemini 3.8 Flash
- **نشر وتحديث شامل لحزمة ACCOUNTS.WHATSAPP_BRIDGE (Spec & Body)**:
  - مطابقة الحزمة بنسبة 100% مع ملف التنفيذ `deploy_whatsapp_bridge.sql`.
  - حل مشكلة تشويه الترميز العربي الصادر من قاعدة البيانات `WE8MSWIN1252` عبر تشفير البايتات الخام بدالة `TO_BASE64` لضمان إرسال النص العربي بأعلى موثوقية دون أي تدخل خاطئ من دوال NLS أو طبقة الشبكة.
  - إضافة وتوفير الدوال كـ Procedure و Function (`SEND_TEXT`, `SEND_TEXT_F`, `SEND_IMAGE`, `SEND_IMAGE_F`, `SEND_FILE`, `SEND_FILE_F`).
  - دعم قراءة وإرسال الملفات من مجلد الملفات الافتراضي `C:\ultramsg-bridge\public`.
  - تحديث معالجة الطابور `PUSH_W_QUEUE` لمطابقة هيكل جدول `ACCOUNTS.W_MSG_QUEUE` الحقيقي، وأرشفة الرسائل المكتملة في `ACCOUNTS.W_MSG_ARCHIVE` وحذفها من الطابور فور نجاح الإرسال، وتحديث عداد المحاولات وحالة الخطأ `IS_SENT = 'E'/'F'` عند الإخفاق.
  - التحقق من نجاح إرسال النصوص والملفات ومعالجة الطابور بنجاح تام من داخل أوراكل.

---
## 2026-09-18 05:32 | Gemini 3.8 Flash
- **تحديث وضمان استقرار ACCOUNTS.WHATSAPP_BRIDGE والـ JOB**:
  - تفعيل مسار الإرسال الأولي عبر `arslanhook` على `http://127.0.0.1:2785/arslanhook/send`.
  - في حال تعذر الإرسال أو حدوث خطأ يتم التحويل التلقائي والشفاف (Fallback) إلى مسارات `whAPI` الرسمية (`/send-text`, `/send-image`, `/send-document`) مع ترويسة المصادقة `X-API-Key`.
  - تحويل النصوص العربية إلى Base64 خام من مصفوفة بايتات ويندوز-1256 عبر `TO_BASE64` لفكها في الـ API بواسطة `iconv-lite` بدون تشويه الأحرف.
  - دعم إرسال الملفات المحلية من المجلد الافتراضي `C:\ultramsg-bridge\public`.
  - اختبار تنفيذ `WHATSAPP_BRIDGE.PUSH_W_QUEUE` والتحقق من عمل الجدولة التلقائية `ACCOUNTS.W_SEND_MSG`.


