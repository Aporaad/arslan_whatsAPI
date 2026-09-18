# سجل أوامر قاعدة البيانات (DB Commands)

---
## 2026-09-17 04:09 | Gemini 3.8 Flash
**الهدف**: فحص حالة الـ Package والـ Job والجداول ذات الصلة
**كود SQL**:
```sql
SELECT object_name, object_type, status FROM all_objects WHERE owner = 'ACCOUNTS' AND object_name = 'WHATSAPP_BRIDGE' ORDER BY object_type;
```

---
## 2026-09-17 04:20 | Gemini 3.8 Flash
**الهدف**: استخراج كود الـ Package الحالي ACCOUNTS.WHATSAPP_BRIDGE وفحص حالة الـ JOB
**كود SQL**:
```sql
SELECT object_name, object_type, status FROM all_objects WHERE owner = 'ACCOUNTS' AND object_name = 'WHATSAPP_BRIDGE';
SELECT job_name, job_action, enabled, state FROM all_scheduler_jobs WHERE owner = 'ACCOUNTS' AND job_name = 'W_SEND_MSG';
```

---
## 2026-09-17 04:23 | Gemini 3.8 Flash
**الهدف**: فحص إعدادات API_KEY و SESSION_ID و UTL_HTTP داخل ACCOUNTS.WHATSAPP_BRIDGE
**كود SQL**:
```sql
SELECT line, text FROM all_source WHERE owner = 'ACCOUNTS' AND name = 'WHATSAPP_BRIDGE' AND type = 'PACKAGE BODY' AND line <= 50 ORDER BY line;
```

---
## 2026-09-17 04:30 | Gemini 3.8 Flash
**الهدف**: فحص معايير الترميز NLS_CHARACTERSET في قاعدة بيانات أوراكل
**كود SQL**:
```sql
SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');
```

---
## 2026-09-17 04:35 | Gemini 3.8 Flash
**الهدف**: فحص عينات من نصوص الرسائل والترميز الفعلي للبايتات (DUMP) لمعرفة هل هي AR8MSWIN1256 أم غير ذلك
**كود SQL**:
```sql
SELECT MSG_TEXT, DUMP(MSG_TEXT, 16) AS DUMP_VAL FROM ACCOUNTS.W_MSG_ARCHIVE WHERE MSG_TEXT IS NOT NULL AND ROWNUM <= 2;
```

---
## 2026-09-17 04:37 | Gemini 3.8 Flash
**الهدف**: فحص جدول W_MSG_QUEUE وعد السجلات
**كود SQL**:
```sql
SELECT COUNT(*) FROM ACCOUNTS.W_MSG_QUEUE;
SELECT COUNT(*) FROM ACCOUNTS.W_MSG_ARCHIVE;
SELECT * FROM ACCOUNTS.W_MSG_QUEUE WHERE ROWNUM <= 2;
```

---
## 2026-09-17 04:39 | Gemini 3.8 Flash
**الهدف**: استخراج كامل مواصفات Package (Specification) لـ ACCOUNTS.WHATSAPP_BRIDGE
**كود SQL**:
```sql
SELECT text FROM all_source WHERE owner = 'ACCOUNTS' AND name = 'WHATSAPP_BRIDGE' AND type = 'PACKAGE' ORDER BY line;
```

---
## 2026-09-17 04:46 | Gemini 3.8 Flash
**الهدف**: اختبار تحويل النص العربي ودوال UTL_I18N لمعرفة الناتج الفعلي
**كود SQL**:
```sql
SELECT DUMP('تجربة'), UTL_I18N.STRING_TO_RAW('تجربة', 'AL32UTF8'), UTL_RAW.CAST_TO_RAW('تجربة') FROM DUAL;
```

---
## 2026-09-17 05:26 | Gemini 3.8 Flash
**الهدف**: تجميع وتحديث PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE لدعم إرسال الرسائل النصية والملفات والصور Base64/URL، وحل مشكلة الترميز العربي والتكامل المباشر مع whAPI
**كود SQL**:
```sql
CREATE OR REPLACE PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE IS
... (تم تحديث C_API_KEY, NORMALIZE_PHONE, TEXT_TO_UTF8_RAW, SEND_TEXT, SEND_IMAGE, SEND_FILE, SEND_IMAGE_B64, SEND_FILE_B64, PUSH_W_QUEUE) ...
```

---
## 2026-09-17 05:44 | Gemini 3.8 Flash
**الهدف**: فحص الـ DIRECTORIES المعرفة في قاعدة بيانات Oracle
**كود SQL**:
```sql
SELECT directory_name, directory_path FROM all_directories;
```

---
## 2026-09-17 05:46 | Gemini 3.8 Flash
**الهدف**: إنشاء Directory في Oracle لمجلد الملفات الافتراضي C:\ultramsg-bridge\public
**كود SQL**:
```sql
CREATE OR REPLACE DIRECTORY W_MEDIA_DIR AS 'C:\ultramsg-bridge\public';
```

---
## 2026-09-17 06:01 | Gemini 3.8 Flash
**الهدف**: فحص تفاصيل Job الجدولة ACCOUNTS.W_SEND_MSG وفترة تكرارها
**كود SQL**:
```sql
SELECT job_name, job_type, job_action, repeat_interval, enabled, state, last_start_date, next_run_date FROM all_scheduler_jobs WHERE owner = 'ACCOUNTS' AND job_name = 'W_SEND_MSG';
```

---
## 2026-09-17 06:26 | Gemini 3.8 Flash
**الهدف**: اختبار إرسال رسالة نصية مباشرة ورسالة مستند/ملف من مجلد public، واختبار الإرسال التلقائي من جدول ACCOUNTS.W_MSG_QUEUE عبر الـ Job
**كود SQL**:
```sql
-- 1. اختبار إرسال نصي مباشر
SELECT ACCOUNTS.WHATSAPP_BRIDGE.SEND_TEXT('967776422777', 'تجربة إرسال مباشر من أوراكل: النص العربي سليم بدون بريدج') AS RESP_TEXT FROM DUAL;

-- 2. اختبار إرسال ملف مباشر من C:\ultramsg-bridge\public
SELECT ACCOUNTS.WHATSAPP_BRIDGE.SEND_FILE('967776422777', 'test_file.txt', 'test_file.txt', 'ملف مرفق تجريبي من مجلد public') AS RESP_FILE FROM DUAL;

-- 3. إدراج في جدول W_MSG_QUEUE لفحص الإرسال والأرشفة التلقائية
INSERT INTO ACCOUNTS.W_MSG_QUEUE (ID, MSG_TEXT, MOBILE_NO, IS_SENT, CREATED_AT, CREATED_BY)
VALUES (99901, 'رسالة طابور تلقائية - تجربة نظام الواتساب الجديد', '967776422777', 'N', SYSDATE, 'TEST_JOB');

INSERT INTO ACCOUNTS.W_MSG_QUEUE (ID, MSG_TEXT, MOBILE_NO, IS_SENT, CREATED_AT, CREATED_BY, FILE_PATH, FILE_NAME, FILE_TYPE, CAPTION)
VALUES (99902, 'ملف مرفق تلقائي من مجلد public', '967776422777', 'N', SYSDATE, 'TEST_JOB', 'test_file.txt', 'test_file.txt', 'txt', 'مستند مرفق من مجلد public الافتراضي');
COMMIT;
```

---
## 2026-09-17 09:17 | Gemini 3.8 Flash
**الهدف**: نشر مواصفات الحزمة الكاملة ACCOUNTS.WHATSAPP_BRIDGE المتطابقة مع deploy_whatsapp_bridge.sql
**كود SQL**:
```sql
CREATE OR REPLACE PACKAGE ACCOUNTS.WHATSAPP_BRIDGE AS
    C_BASE_URL    CONSTANT VARCHAR2(100) := 'http://127.0.0.1:2785/arslanhook';
    C_SEND_URL    CONSTANT VARCHAR2(100) := 'http://127.0.0.1:2785/arslanhook/send';
    C_MEDIA_DIR   CONSTANT VARCHAR2(30)  := 'W_MEDIA_DIR';

    FUNCTION CLEAN_TEXT(p_text IN VARCHAR2) RETURN VARCHAR2;
    FUNCTION JSON_ESCAPE(p_text IN VARCHAR2) RETURN VARCHAR2;
    FUNCTION TO_BASE64(p_text IN VARCHAR2) RETURN VARCHAR2;
    FUNCTION NORMALIZE_PHONE(p_phone IN VARCHAR2) RETURN VARCHAR2;

    PROCEDURE SEND_TEXT(p_to IN VARCHAR2, p_text IN VARCHAR2);
    FUNCTION SEND_TEXT_F(p_to IN VARCHAR2, p_text IN VARCHAR2) RETURN VARCHAR2;

    PROCEDURE SEND_IMAGE(p_to IN VARCHAR2, p_caption IN VARCHAR2 DEFAULT NULL, p_url IN VARCHAR2 DEFAULT NULL);
    FUNCTION SEND_IMAGE_F(p_to IN VARCHAR2, p_caption IN VARCHAR2 DEFAULT NULL, p_url IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    PROCEDURE SEND_FILE(p_to IN VARCHAR2, p_caption IN VARCHAR2 DEFAULT NULL, p_url IN VARCHAR2 DEFAULT NULL, p_filename IN VARCHAR2 DEFAULT NULL);
    FUNCTION SEND_FILE_F(p_to IN VARCHAR2, p_caption IN VARCHAR2 DEFAULT NULL, p_url IN VARCHAR2 DEFAULT NULL, p_filename IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    PROCEDURE PUSH_W_QUEUE;
END WHATSAPP_BRIDGE;
```

---
## 2026-09-17 09:20 | Gemini 3.8 Flash
**الهدف**: نشر كود PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE المتطابق بالكامل مع deploy_whatsapp_bridge.sql مع دعم Base64 والتكامل مع W_MSG_QUEUE و W_MSG_ARCHIVE
**كود SQL**:
```sql
CREATE OR REPLACE PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE AS
... (CLEAN_TEXT, JSON_ESCAPE, TO_BASE64, NORMALIZE_PHONE, DO_HTTP_POST, SEND_TEXT, SEND_TEXT_F, SEND_IMAGE, SEND_IMAGE_F, SEND_FILE, SEND_FILE_F, PUSH_W_QUEUE) ...
```

---
## 2026-09-17 09:20 | Gemini 3.8 Flash
**الهدف**: التحقق من حالة حزمة WHATSAPP_BRIDGE (Spec و Body) في Oracle
**كود SQL**:
```sql
SELECT object_name, object_type, status FROM all_objects WHERE owner = 'ACCOUNTS' AND object_name = 'WHATSAPP_BRIDGE' ORDER BY object_type;
```

---
## 2026-09-17 09:29 | Gemini 3.8 Flash
**الهدف**: اختبار إرسال رسالة نصية مباشرة من أوراكل للرقم 967776422777
**كود SQL**:
```sql
BEGIN
    WHATSAPP_BRIDGE.SEND_TEXT(
        p_to   => '967776422777',
        p_text => 'اختبار برامجة اوراكل - النص العربي سليم'
    );
END;
```

---
## 2026-09-17 09:30 | Gemini 3.8 Flash
**الهدف**: اختبار إرسال ملف مستند من مجلد public الافتراضي C:\ultramsg-bridge\public
**كود SQL**:
```sql
BEGIN
    WHATSAPP_BRIDGE.SEND_FILE(
        p_to       => '967776422777',
        p_caption  => 'مستند تجريبي من داخل أوراكل عبر مجلد public',
        p_url      => 'test_file.txt',
        p_filename => 'test_file.txt'
    );
END;
```

---
## 2026-09-17 09:31 | Gemini 3.8 Flash
**الهدف**: اختبار معالجة طابور الرسائل W_MSG_QUEUE وأرشفة الرسالة في W_MSG_ARCHIVE
**كود SQL**:
```sql
BEGIN
    DELETE FROM ACCOUNTS.W_MSG_QUEUE WHERE ID = 99905;
    INSERT INTO ACCOUNTS.W_MSG_QUEUE (
        ID, MSG_TEXT, MOBILE_NO, IS_SENT, CREATED_AT, CREATED_BY
    ) VALUES (
        99905, 'رسالة طابور تلقائية من جدول W_MSG_QUEUE - تجربة ناجحة 100%', 967776422777, 'N', SYSDATE, 'TEST_AUTO'
    );
    COMMIT;
    WHATSAPP_BRIDGE.PUSH_W_QUEUE;
END;
```

---
## 2026-09-17 09:32 | Gemini 3.8 Flash
**الهدف**: التحقق من حالة جدولة وظيفة أوراكل W_SEND_MSG وفترة تكرارها
**كود SQL**:
```sql
SELECT job_name, job_action, enabled, state, repeat_interval, failure_count FROM all_scheduler_jobs WHERE owner = 'ACCOUNTS' AND job_name = 'W_SEND_MSG';
```

---
## 2026-09-18 05:35 | Gemini 3.8 Flash
**الهدف**: فحص حزمة WHATSAPP_BRIDGE وطابور الرسائل W_MSG_QUEUE وحالة وظيفة الجدولة W_SEND_MSG واختبار PUSH_W_QUEUE
**كود SQL**:
```sql
-- فحص كود Package Body لمعاينة منطق SEND_TEXT و SEND_FILE و PUSH_W_QUEUE
SELECT line, text FROM all_source WHERE owner = 'ACCOUNTS' AND name = 'WHATSAPP_BRIDGE' AND type = 'PACKAGE BODY' AND line BETWEEN 150 AND 260 ORDER BY line;
SELECT line, text FROM all_source WHERE owner = 'ACCOUNTS' AND name = 'WHATSAPP_BRIDGE' AND type = 'PACKAGE BODY' AND line BETWEEN 280 AND 360 ORDER BY line;
SELECT line, text FROM all_source WHERE owner = 'ACCOUNTS' AND name = 'WHATSAPP_BRIDGE' AND type = 'PACKAGE BODY' AND line >= 415 ORDER BY line;

-- فحص حالة وظيفة أوراكل W_SEND_MSG
SELECT job_name, job_type, job_action, enabled, state, failure_count, last_start_date, next_run_date, repeat_interval 
FROM all_scheduler_jobs WHERE owner = 'ACCOUNTS' AND job_name = 'W_SEND_MSG';

-- فحص ومطابقة أعمدة وسجلات طابور الرسائل W_MSG_QUEUE
SELECT column_name, data_type, data_length FROM all_tab_columns WHERE owner = 'ACCOUNTS' AND table_name = 'W_MSG_QUEUE' ORDER BY column_id;
SELECT id, mobile_no, msg_text, file_path, file_name, file_type, caption, is_sent, send_attempt FROM ACCOUNTS.W_MSG_QUEUE;

-- اختبار تشغيل تفريغ الطابور يدوياً
BEGIN
    WHATSAPP_BRIDGE.PUSH_W_QUEUE;
END;
```


