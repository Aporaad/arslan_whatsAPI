-- ============================================================
-- WHATSAPP_BRIDGE - Oracle Package for WhatsApp Integration
-- Version: 4.0 (Robust Base64 Arabic Encoding & OpenWA Direct)
-- Database Charset: WE8MSWIN1252 (Single-byte Arabic)
-- Solution: Raw byte Base64 encoding for 100% lossless Arabic text
-- ============================================================
/*
-- 1. Create or Replace Package Specification
CREATE OR REPLACE PACKAGE ACCOUNTS.WHATSAPP_BRIDGE AS

    -- Base Endpoints
    C_BASE_URL    CONSTANT VARCHAR2(100) := 'http://127.0.0.1:2785/arslanhook';
    C_SEND_URL    CONSTANT VARCHAR2(100) := 'http://127.0.0.1:2785/arslanhook/send';

    -- Directory name for local media files
    C_MEDIA_DIR   CONSTANT VARCHAR2(30)  := 'W_MEDIA_DIR';

    /**
     * Remove unprintable ASCII control characters
     */
    FUNCTION CLEAN_TEXT(p_text IN VARCHAR2) RETURN VARCHAR2;

    /**
     * Escape special characters for JSON payloads
     */
    FUNCTION JSON_ESCAPE(p_text IN VARCHAR2) RETURN VARCHAR2;

    /**
     * Convert raw database bytes into standard Base64 string
     * Guarantees 100% lossless transfer of Arabic text from WE8MSWIN1252
     */
    FUNCTION TO_BASE64(p_text IN VARCHAR2) RETURN VARCHAR2;

    /**
     * Normalize international/local phone number format
     */
    FUNCTION NORMALIZE_PHONE(p_phone IN VARCHAR2) RETURN VARCHAR2;

    /**
     * Send text message (Procedure)
     */
    PROCEDURE SEND_TEXT(
        p_to   IN VARCHAR2,
        p_text IN VARCHAR2
    );

    /**
     * Send text message (Function returning response)
     */
    FUNCTION SEND_TEXT_F(
        p_to   IN VARCHAR2,
        p_text IN VARCHAR2
    ) RETURN VARCHAR2;

    /**
     * Send image message (Procedure)
     */
    PROCEDURE SEND_IMAGE(
        p_to      IN VARCHAR2,
        p_caption IN VARCHAR2 DEFAULT NULL,
        p_url     IN VARCHAR2 DEFAULT NULL
    );

    /**
     * Send image message (Function returning response)
     */
    FUNCTION SEND_IMAGE_F(
        p_to      IN VARCHAR2,
        p_caption IN VARCHAR2 DEFAULT NULL,
        p_url     IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2;

    /**
     * Send file or document (Procedure)
     */
    PROCEDURE SEND_FILE(
        p_to       IN VARCHAR2,
        p_caption  IN VARCHAR2 DEFAULT NULL,
        p_url      IN VARCHAR2 DEFAULT NULL,
        p_filename IN VARCHAR2 DEFAULT NULL
    );

    /**
     * Send file or document (Function returning response)
     */
    FUNCTION SEND_FILE_F(
        p_to       IN VARCHAR2,
        p_caption  IN VARCHAR2 DEFAULT NULL,
        p_url      IN VARCHAR2 DEFAULT NULL,
        p_filename IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2;

    /**
     * Process pending messages in ACCOUNTS.W_MSG_QUEUE
     * Invoked automatically by the Oracle Scheduler Job ACCOUNTS.W_SEND_MSG
     */
    PROCEDURE PUSH_W_QUEUE;

END WHATSAPP_BRIDGE;
/

-- 2. Create or Replace Package Body
CREATE OR REPLACE PACKAGE BODY ACCOUNTS.WHATSAPP_BRIDGE AS

    -- -------------------------------------------------------
    -- Remove bad control characters
    -- -------------------------------------------------------
    FUNCTION CLEAN_TEXT(p_text IN VARCHAR2) RETURN VARCHAR2 IS
        l_cleaned VARCHAR2(32767);
        i         INTEGER;
        l_char    VARCHAR2(1);
        l_code    NUMBER;
        l_len     INTEGER;
    BEGIN
        IF p_text IS NULL THEN
            RETURN '';
        END IF;

        l_cleaned := '';
        l_len := LENGTH(p_text);

        FOR i IN 1 .. l_len LOOP
            l_char := SUBSTR(p_text, i, 1);
            l_code := ASCII(l_char);

            -- Keep printable ASCII, newlines, tabs, and high-byte characters (Arabic bytes 128-255)
            IF (l_code >= 32 AND l_code <= 126)
               OR l_char = CHR(9)
               OR l_char = CHR(10)
               OR l_char = CHR(13)
               OR l_code > 127
            THEN
                l_cleaned := l_cleaned || l_char;
            END IF;
        END LOOP;

        RETURN l_cleaned;
    END CLEAN_TEXT;

    -- -------------------------------------------------------
    -- Escape JSON characters
    -- -------------------------------------------------------
    FUNCTION JSON_ESCAPE(p_text IN VARCHAR2) RETURN VARCHAR2 IS
        l_result VARCHAR2(32767);
    BEGIN
        IF p_text IS NULL THEN
            RETURN '';
        END IF;

        l_result := CLEAN_TEXT(p_text);
        l_result := REPLACE(l_result, '\', '\\');
        l_result := REPLACE(l_result, '"', '\"');
        l_result := REPLACE(l_result, CHR(13) || CHR(10), '\n');
        l_result := REPLACE(l_result, CHR(13), '\n');
        l_result := REPLACE(l_result, CHR(10), '\n');
        l_result := REPLACE(l_result, CHR(9),  '\t');

        RETURN l_result;
    END JSON_ESCAPE;

    -- -------------------------------------------------------
    -- Convert raw text bytes into standard Base64
    -- Prevents any charset degradation across HTTP/JSON
    -- -------------------------------------------------------
    FUNCTION TO_BASE64(p_text IN VARCHAR2) RETURN VARCHAR2 IS
        l_raw RAW(32767);
        l_b64 VARCHAR2(32767);
    BEGIN
        IF p_text IS NULL THEN
            RETURN '';
        END IF;

        l_raw := UTL_RAW.CAST_TO_RAW(p_text);
        l_b64 := UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(l_raw));
        -- Remove CRLF inserted by base64_encode
        l_b64 := REPLACE(l_b64, CHR(13), '');
        l_b64 := REPLACE(l_b64, CHR(10), '');
        RETURN l_b64;
    END TO_BASE64;

    -- -------------------------------------------------------
    -- Normalize phone numbers
    -- -------------------------------------------------------
    FUNCTION NORMALIZE_PHONE(p_phone IN VARCHAR2) RETURN VARCHAR2 IS
        l_clean VARCHAR2(100);
    BEGIN
        IF p_phone IS NULL THEN
            RETURN '';
        END IF;

        -- Remove spaces, dashes, parentheses and plus
        l_clean := REGEXP_REPLACE(p_phone, '[^0-9]', '');

        -- Remove leading double zeros
        IF SUBSTR(l_clean, 1, 2) = '00' THEN
            l_clean := SUBSTR(l_clean, 3);
        END IF;

        -- Yemen mobile 9-digit starting with 7 (e.g. 776422777 -> 967776422777)
        IF LENGTH(l_clean) = 9 AND SUBSTR(l_clean, 1, 1) = '7' THEN
            l_clean := '967' || l_clean;
        ELSIF LENGTH(l_clean) = 10 AND SUBSTR(l_clean, 1, 2) = '07' THEN
            l_clean := '967' || SUBSTR(l_clean, 2);
        END IF;

        RETURN l_clean;
    END NORMALIZE_PHONE;

    -- -------------------------------------------------------
    -- Execute HTTP POST Request to ArslanHook API
    -- -------------------------------------------------------
    PROCEDURE DO_HTTP_POST(
        p_url  IN VARCHAR2,
        p_json IN VARCHAR2,
        p_resp OUT CLOB
    ) IS
        l_req      UTL_HTTP.REQ;
        l_resp     UTL_HTTP.RESP;
        l_buf      VARCHAR2(32767);
        l_raw_body RAW(32767);
        l_len      NUMBER;
    BEGIN
        UTL_HTTP.SET_TRANSFER_TIMEOUT(30);

        l_raw_body := UTL_RAW.CAST_TO_RAW(p_json);
        l_len      := UTL_RAW.LENGTH(l_raw_body);

        l_req := UTL_HTTP.BEGIN_REQUEST(p_url, 'POST', 'HTTP/1.1');
        UTL_HTTP.SET_HEADER(l_req, 'Content-Type', 'application/json; charset=utf-8');
        UTL_HTTP.SET_HEADER(l_req, 'Accept', 'application/json');
        UTL_HTTP.SET_HEADER(l_req, 'Content-Length', TO_CHAR(l_len));
        UTL_HTTP.SET_HEADER(l_req, 'Connection', 'close');

        UTL_HTTP.WRITE_RAW(l_req, l_raw_body);

        l_resp := UTL_HTTP.GET_RESPONSE(l_req);
        p_resp := '';

        BEGIN
            LOOP
                UTL_HTTP.READ_LINE(l_resp, l_buf, FALSE);
                p_resp := p_resp || l_buf;
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN
                NULL;
        END;

        UTL_HTTP.END_RESPONSE(l_resp);

    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                UTL_HTTP.END_RESPONSE(l_resp);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
            RAISE;
    END DO_HTTP_POST;

    -- -------------------------------------------------------
    -- SEND_TEXT Implementation
    -- -------------------------------------------------------
    FUNCTION SEND_TEXT_F(
        p_to   IN VARCHAR2,
        p_text IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_resp  CLOB;
        l_json  VARCHAR2(32767);
        l_phone VARCHAR2(100);
        l_b64   VARCHAR2(32767);
    BEGIN
        l_phone := NORMALIZE_PHONE(p_to);
        l_b64   := TO_BASE64(p_text);

        l_json := '{"to":"' || l_phone || '",' ||
                  '"base64_text":"' || l_b64 || '"}';

        DO_HTTP_POST(C_SEND_URL, l_json, l_resp);
        RETURN SUBSTR(l_resp, 1, 4000);
    END SEND_TEXT_F;

    PROCEDURE SEND_TEXT(
        p_to   IN VARCHAR2,
        p_text IN VARCHAR2
    ) IS
        l_res VARCHAR2(4000);
    BEGIN
        l_res := SEND_TEXT_F(p_to, p_text);
        DBMS_OUTPUT.PUT_LINE('SEND_TEXT OK: ' || SUBSTR(l_res, 1, 200));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('SEND_TEXT ERROR: ' || SQLERRM);
            RAISE;
    END SEND_TEXT;

    -- -------------------------------------------------------
    -- SEND_IMAGE Implementation
    -- -------------------------------------------------------
    FUNCTION SEND_IMAGE_F(
        p_to      IN VARCHAR2,
        p_caption IN VARCHAR2 DEFAULT NULL,
        p_url     IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 IS
        l_resp    CLOB;
        l_json    VARCHAR2(32767);
        l_phone   VARCHAR2(100);
        l_b64cap  VARCHAR2(32767);
    BEGIN
        l_phone  := NORMALIZE_PHONE(p_to);
        l_b64cap := TO_BASE64(p_caption);

        l_json := '{"to":"' || l_phone || '",' ||
                  '"url":"' || JSON_ESCAPE(NVL(p_url, '')) || '",' ||
                  '"type":"image"';

        IF l_b64cap IS NOT NULL THEN
            l_json := l_json || ',"base64_text":"' || l_b64cap || '"';
        END IF;

        l_json := l_json || '}';

        DO_HTTP_POST(C_SEND_URL, l_json, l_resp);
        RETURN SUBSTR(l_resp, 1, 4000);
    END SEND_IMAGE_F;

    PROCEDURE SEND_IMAGE(
        p_to      IN VARCHAR2,
        p_caption IN VARCHAR2 DEFAULT NULL,
        p_url     IN VARCHAR2 DEFAULT NULL
    ) IS
        l_res VARCHAR2(4000);
    BEGIN
        l_res := SEND_IMAGE_F(p_to, p_caption, p_url);
        DBMS_OUTPUT.PUT_LINE('SEND_IMAGE OK: ' || SUBSTR(l_res, 1, 200));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('SEND_IMAGE ERROR: ' || SQLERRM);
            RAISE;
    END SEND_IMAGE;

    -- -------------------------------------------------------
    -- SEND_FILE Implementation
    -- -------------------------------------------------------
    FUNCTION SEND_FILE_F(
        p_to       IN VARCHAR2,
        p_caption  IN VARCHAR2 DEFAULT NULL,
        p_url      IN VARCHAR2 DEFAULT NULL,
        p_filename IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 IS
        l_resp     CLOB;
        l_json     VARCHAR2(32767);
        l_phone    VARCHAR2(100);
        l_b64cap   VARCHAR2(32767);
        l_file_val VARCHAR2(1000);
    BEGIN
        l_phone    := NORMALIZE_PHONE(p_to);
        l_b64cap   := TO_BASE64(p_caption);
        l_file_val := NVL(p_url, p_filename);

        l_json := '{"to":"' || l_phone || '",' ||
                  '"url":"' || JSON_ESCAPE(l_file_val) || '",' ||
                  '"type":"file"';

        IF p_filename IS NOT NULL THEN
            l_json := l_json || ',"filename":"' || JSON_ESCAPE(p_filename) || '"';
        END IF;

        IF l_b64cap IS NOT NULL THEN
            l_json := l_json || ',"base64_text":"' || l_b64cap || '"';
        END IF;

        l_json := l_json || '}';

        DO_HTTP_POST(C_SEND_URL, l_json, l_resp);
        RETURN SUBSTR(l_resp, 1, 4000);
    END SEND_FILE_F;

    PROCEDURE SEND_FILE(
        p_to       IN VARCHAR2,
        p_caption  IN VARCHAR2 DEFAULT NULL,
        p_url      IN VARCHAR2 DEFAULT NULL,
        p_filename IN VARCHAR2 DEFAULT NULL
    ) IS
        l_res VARCHAR2(4000);
    BEGIN
        l_res := SEND_FILE_F(p_to, p_caption, p_url, p_filename);
        DBMS_OUTPUT.PUT_LINE('SEND_FILE OK: ' || SUBSTR(l_res, 1, 200));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('SEND_FILE ERROR: ' || SQLERRM);
            RAISE;
    END SEND_FILE;

    -- -------------------------------------------------------
    -- PUSH_W_QUEUE Implementation
    -- Reads pending messages from ACCOUNTS.W_MSG_QUEUE, sends them,
    -- and archives them in ACCOUNTS.W_MSG_ARCHIVE.
    -- -------------------------------------------------------
    PROCEDURE PUSH_W_QUEUE IS
        CURSOR c_pending IS
            SELECT q.ROWID AS ROW_ID,
                   q.ID,
                   TO_CHAR(q.MOBILE_NO) AS MOBILE_NO,
                   q.MSG_TEXT,
                   q.FILE_PATH,
                   q.FILE_NAME,
                   q.FILE_TYPE,
                   q.CAPTION,
                   NVL(q.SEND_ATTEMPT, 0) AS SEND_ATTEMPT,
                   q.CREATED_AT,
                   q.CREATED_BY,
                   q.SERVICE_ID,
                   q.PROVIDER_ID,
                   q.CUSTOMER_NAME
            FROM   ACCOUNTS.W_MSG_QUEUE q
            WHERE  q.IS_SENT = 'N'
            ORDER  BY q.ID ASC
            FOR UPDATE SKIP LOCKED;

        l_row   c_pending%ROWTYPE;
        l_resp  VARCHAR2(4000);
        l_error VARCHAR2(4000);
        l_type  VARCHAR2(50);
        l_file  VARCHAR2(1000);
        l_text  VARCHAR2(4000);
    BEGIN
        OPEN c_pending;
        FETCH c_pending INTO l_row;

        IF c_pending%NOTFOUND THEN
            CLOSE c_pending;
            RETURN;
        END IF;

        CLOSE c_pending;

        -- Update attempt count immediately
        UPDATE ACCOUNTS.W_MSG_QUEUE
        SET    SEND_ATTEMPT = NVL(SEND_ATTEMPT, 0) + 1,
               UPDATED_AT   = SYSDATE
        WHERE  ID = l_row.ID;
        COMMIT;

        BEGIN
            l_type := UPPER(NVL(l_row.FILE_TYPE, 'TEXT'));
            l_file := NVL(l_row.FILE_PATH, l_row.FILE_NAME);
            l_text := NVL(l_row.MSG_TEXT, l_row.CAPTION);

            -- Determine send action based on file presence
            IF l_file IS NOT NULL AND l_file != 'not file' AND LENGTH(TRIM(l_file)) > 0 THEN
                IF l_type IN ('IMAGE', 'JPG', 'JPEG', 'PNG', 'WEBP', 'GIF') THEN
                    SEND_IMAGE(
                        p_to      => l_row.MOBILE_NO,
                        p_caption => l_text,
                        p_url     => l_file
                    );
                ELSE
                    SEND_FILE(
                        p_to       => l_row.MOBILE_NO,
                        p_caption  => l_text,
                        p_url      => l_file,
                        p_filename => NVL(l_row.FILE_NAME, l_file)
                    );
                END IF;
            ELSE
                -- Plain text message
                SEND_TEXT(
                    p_to   => l_row.MOBILE_NO,
                    p_text => l_text
                );
            END IF;

            -- Successful: Archive and remove from queue
            BEGIN
                INSERT INTO ACCOUNTS.W_MSG_ARCHIVE (
                    ID, MSG_TEXT, MOBILE_NO, IS_SENT,
                    CREATED_AT, CREATED_BY, UPDATED_AT, UPDATED_BY,
                    SERVICE_ID, PROVIDER_ID, CUSTOMER_NAME,
                    SEND_ATTEMPT, FILE_PATH, FILE_NAME, FILE_TYPE, CAPTION
                ) VALUES (
                    l_row.ID, l_row.MSG_TEXT, TO_NUMBER(l_row.MOBILE_NO), 'Y',
                    l_row.CREATED_AT, l_row.CREATED_BY, SYSDATE, 'WHATSAPP_BRIDGE',
                    l_row.SERVICE_ID, l_row.PROVIDER_ID, l_row.CUSTOMER_NAME,
                    l_row.SEND_ATTEMPT, l_row.FILE_PATH, l_row.FILE_NAME, l_row.FILE_TYPE, l_row.CAPTION
                );

                DELETE FROM ACCOUNTS.W_MSG_QUEUE WHERE ID = l_row.ID;
            EXCEPTION
                WHEN OTHERS THEN
                    -- In case archive already has this ID or error, mark queue as sent
                    UPDATE ACCOUNTS.W_MSG_QUEUE
                    SET    IS_SENT    = 'Y',
                           UPDATED_AT = SYSDATE,
                           UPDATED_BY = 'WHATSAPP_BRIDGE'
                    WHERE  ID = l_row.ID;
            END;

            COMMIT;
            DBMS_OUTPUT.PUT_LINE('PUSH_W_QUEUE Success: Message ID ' || l_row.ID || ' processed and archived.');

        EXCEPTION
            WHEN OTHERS THEN
                l_error := SUBSTR(SQLERRM, 1, 3900);
                UPDATE ACCOUNTS.W_MSG_QUEUE
                SET    IS_SENT    = CASE WHEN NVL(SEND_ATTEMPT, 0) >= 5 THEN 'F' ELSE 'E' END,
                       UPDATED_AT = SYSDATE,
                       UPDATED_BY = SUBSTR('ERROR: ' || l_error, 1, 80)
                WHERE  ID = l_row.ID;
                COMMIT;
                DBMS_OUTPUT.PUT_LINE('PUSH_W_QUEUE Failed: Message ID ' || l_row.ID || ': ' || l_error);
        END;

    END PUSH_W_QUEUE;

END WHATSAPP_BRIDGE;
/
*/

-- ============================================================
-- WHATSAPP_BRIDGE - Oracle Package for WhatsApp Integration
-- Version: 3.0 
-- ============================================================
/*
CREATE OR REPLACE PACKAGE          WHATSAPP_BRIDGE IS

  -- ============================================================
  -- WHATSAPP_BRIDGE Package
  -- OpenWA (whAPI) Direct Integration - No Bridge Needed
  -- Target: http://127.0.0.1:2785
  -- Session: arslan-session
  -- Arabic Fix: UTL_I18N.STRING_TO_RAW for proper UTF-8 encoding
  -- ============================================================

  PROCEDURE INS_W_MSG_QUEUE
    (
     P_ID            IN W_MSG_QUEUE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_QUEUE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_QUEUE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_QUEUE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_QUEUE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_QUEUE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_QUEUE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_QUEUE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_QUEUE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_QUEUE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE
    ,P_FILE_PATH     IN W_MSG_QUEUE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_QUEUE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_QUEUE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_QUEUE.CAPTION%TYPE
    );

  PROCEDURE MERGE_W_MSG_QUEUE
    (
     P_ID            IN W_MSG_QUEUE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_QUEUE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_QUEUE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_QUEUE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_QUEUE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_QUEUE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_QUEUE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_QUEUE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_QUEUE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_QUEUE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE
    ,P_FILE_PATH     IN W_MSG_QUEUE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_QUEUE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_QUEUE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_QUEUE.CAPTION%TYPE
    );

  PROCEDURE UPD_W_MSG_QUEUE
    (
     P_ID            IN W_MSG_QUEUE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_QUEUE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_QUEUE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_QUEUE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_QUEUE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_QUEUE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_QUEUE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_QUEUE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_QUEUE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_QUEUE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE
    ,P_FILE_PATH     IN W_MSG_QUEUE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_QUEUE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_QUEUE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_QUEUE.CAPTION%TYPE
    );

  PROCEDURE DEL_W_MSG_QUEUE
    (
     P_ID IN W_MSG_QUEUE.ID%TYPE
    );

  PROCEDURE SET_W_MSG_SENT
    (
     P_ID         IN W_MSG_QUEUE.ID%TYPE
    ,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE
    ,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE
    );

  PROCEDURE SET_W_SEND_ATTEMPT(P_ID NUMBER);

  PROCEDURE INS_W_MSG_ARCHIVE
    (
     P_ID            IN W_MSG_ARCHIVE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_ARCHIVE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_ARCHIVE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_ARCHIVE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_ARCHIVE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_ARCHIVE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_ARCHIVE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_ARCHIVE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_ARCHIVE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE
    ,P_SEND_ATTEMPT  IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE
    ,P_FILE_PATH     IN W_MSG_ARCHIVE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_ARCHIVE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_ARCHIVE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_ARCHIVE.CAPTION%TYPE
    );

  PROCEDURE MERGE_W_MSG_ARCHIVE
    (
     P_ID            IN W_MSG_ARCHIVE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_ARCHIVE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_ARCHIVE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_ARCHIVE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_ARCHIVE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_ARCHIVE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_ARCHIVE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_ARCHIVE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_ARCHIVE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE
    ,P_SEND_ATTEMPT  IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE
    ,P_FILE_PATH     IN W_MSG_ARCHIVE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_ARCHIVE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_ARCHIVE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_ARCHIVE.CAPTION%TYPE
    );

  PROCEDURE UPD_W_MSG_ARCHIVE
    (
     P_ID            IN W_MSG_ARCHIVE.ID%TYPE
    ,P_MSG_TEXT      IN W_MSG_ARCHIVE.MSG_TEXT%TYPE
    ,P_MOBILE_NO     IN W_MSG_ARCHIVE.MOBILE_NO%TYPE
    ,P_IS_SENT       IN W_MSG_ARCHIVE.IS_SENT%TYPE
    ,P_CREATED_AT    IN W_MSG_ARCHIVE.CREATED_AT%TYPE
    ,P_CREATED_BY    IN W_MSG_ARCHIVE.CREATED_BY%TYPE
    ,P_UPDATED_AT    IN W_MSG_ARCHIVE.UPDATED_AT%TYPE
    ,P_UPDATED_BY    IN W_MSG_ARCHIVE.UPDATED_BY%TYPE
    ,P_SERVICE_ID    IN W_MSG_ARCHIVE.SERVICE_ID%TYPE
    ,P_PROVIDER_ID   IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE
    ,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE
    ,P_SEND_ATTEMPT  IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE
    ,P_FILE_PATH     IN W_MSG_ARCHIVE.FILE_PATH%TYPE
    ,P_FILE_NAME     IN W_MSG_ARCHIVE.FILE_NAME%TYPE
    ,P_FILE_TYPE     IN W_MSG_ARCHIVE.FILE_TYPE%TYPE
    ,P_CAPTION       IN W_MSG_ARCHIVE.CAPTION%TYPE
    );

  PROCEDURE DEL_W_MSG_ARCHIVE
    (
     P_ID IN W_MSG_ARCHIVE.ID%TYPE
    );

  PROCEDURE ARCHIVE_W_MSG
    (
     P_ID         IN W_MSG_QUEUE.ID%TYPE
    ,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE
    ,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE
    );

  PROCEDURE PUSH_W_QUEUE;

  FUNCTION CLEAN_CONTROL_CHARS(P_TEXT VARCHAR2) RETURN VARCHAR2;
  FUNCTION ESCAPE_JSON(P_TEXT VARCHAR2) RETURN VARCHAR2;
  FUNCTION TEXT_TO_UTF8_RAW(P_TEXT VARCHAR2) RETURN RAW;
  FUNCTION CALL_OPENWA_POST(P_PATH VARCHAR2, P_JSON_BODY VARCHAR2, P_API_KEY VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;
  FUNCTION SEND_TEXT(P_PHONE VARCHAR2, P_MSG VARCHAR2) RETURN VARCHAR2;
  FUNCTION SEND_IMAGE(P_PHONE VARCHAR2, P_IMAGE_URL VARCHAR2, P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;
  FUNCTION SEND_IMAGE_B64(P_PHONE VARCHAR2, P_BASE64_IMAGE VARCHAR2, P_MIMETYPE VARCHAR2 DEFAULT 'image/jpeg', P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;
  FUNCTION SEND_FILE(P_PHONE VARCHAR2, P_FILE_URL VARCHAR2, P_FILENAME VARCHAR2 DEFAULT NULL, P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;
  FUNCTION SEND_FILE_B64(P_PHONE VARCHAR2, P_BASE64_FILE VARCHAR2, P_FILENAME VARCHAR2, P_MIMETYPE VARCHAR2 DEFAULT 'application/octet-stream', P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

END WHATSAPP_BRIDGE;
/



CREATE OR REPLACE PACKAGE BODY          WHATSAPP_BRIDGE IS
  C_API_BASE   CONSTANT VARCHAR2(100) := 'http://127.0.0.1:2785';
  C_API_KEY    CONSTANT VARCHAR2(100) := 'owa_k1_f90d9452652653e945d87c0b272a059547d28866b7e73c14f3cf71358dc4788e';
  C_SESSION_ID CONSTANT VARCHAR2(100) := '4bbbed0b-1a14-4092-bff2-9c9c565cf941';

  FUNCTION CLEAN_CONTROL_CHARS(P_TEXT VARCHAR2) RETURN VARCHAR2 IS
    L_TEXT VARCHAR2(32767);
  BEGIN
    L_TEXT := P_TEXT;
    L_TEXT := REPLACE(L_TEXT, CHR(0),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(1),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(2),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(3),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(4),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(5),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(6),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(7),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(8),  '');
    L_TEXT := REPLACE(L_TEXT, CHR(11), '');
    L_TEXT := REPLACE(L_TEXT, CHR(12), '');
    L_TEXT := REPLACE(L_TEXT, CHR(14), '');
    L_TEXT := REPLACE(L_TEXT, CHR(15), '');
    L_TEXT := REPLACE(L_TEXT, CHR(16), '');
    L_TEXT := REPLACE(L_TEXT, CHR(17), '');
    L_TEXT := REPLACE(L_TEXT, CHR(18), '');
    L_TEXT := REPLACE(L_TEXT, CHR(19), '');
    L_TEXT := REPLACE(L_TEXT, CHR(20), '');
    L_TEXT := REPLACE(L_TEXT, CHR(21), '');
    L_TEXT := REPLACE(L_TEXT, CHR(22), '');
    L_TEXT := REPLACE(L_TEXT, CHR(23), '');
    L_TEXT := REPLACE(L_TEXT, CHR(24), '');
    L_TEXT := REPLACE(L_TEXT, CHR(25), '');
    L_TEXT := REPLACE(L_TEXT, CHR(26), '');
    L_TEXT := REPLACE(L_TEXT, CHR(27), '');
    L_TEXT := REPLACE(L_TEXT, CHR(28), '');
    L_TEXT := REPLACE(L_TEXT, CHR(29), '');
    L_TEXT := REPLACE(L_TEXT, CHR(30), '');
    L_TEXT := REPLACE(L_TEXT, CHR(31), '');
    RETURN L_TEXT;
  END CLEAN_CONTROL_CHARS;

  FUNCTION ESCAPE_JSON(P_TEXT VARCHAR2) RETURN VARCHAR2 IS
    L_TEXT VARCHAR2(32767);
  BEGIN
    L_TEXT := P_TEXT;
    L_TEXT := REPLACE(L_TEXT, CHR(92), CHR(92)||CHR(92));
    L_TEXT := REPLACE(L_TEXT, CHR(34), CHR(92)||CHR(34));
    L_TEXT := REPLACE(L_TEXT, CHR(13)||CHR(10), CHR(92)||'n');
    L_TEXT := REPLACE(L_TEXT, CHR(10), CHR(92)||'n');
    L_TEXT := REPLACE(L_TEXT, CHR(13), CHR(92)||'n');
    L_TEXT := REPLACE(L_TEXT, CHR(9),  CHR(92)||'t');
    RETURN CLEAN_CONTROL_CHARS(L_TEXT);
  END ESCAPE_JSON;

  FUNCTION TEXT_TO_UTF8_RAW(P_TEXT VARCHAR2) RETURN RAW IS
  BEGIN
    RETURN UTL_I18N.STRING_TO_RAW(P_TEXT, 'AL32UTF8');
  EXCEPTION
    WHEN OTHERS THEN
      RETURN UTL_RAW.CAST_TO_RAW(P_TEXT);
  END TEXT_TO_UTF8_RAW;

  FUNCTION CALL_OPENWA_POST(P_PATH VARCHAR2, P_JSON_BODY VARCHAR2, P_API_KEY VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    L_URL       VARCHAR2(500);
    L_HTTP_REQ  UTL_HTTP.REQ;
    L_HTTP_RESP UTL_HTTP.RESP;
    L_RAW_BODY  RAW(32767);
    L_RESP_TEXT VARCHAR2(32767) := '';
    L_BUFFER    VARCHAR2(32767);
  BEGIN
    L_URL      := C_API_BASE || P_PATH;
    L_RAW_BODY := TEXT_TO_UTF8_RAW(P_JSON_BODY);
    UTL_HTTP.SET_TRANSFER_TIMEOUT(60);
    L_HTTP_REQ := UTL_HTTP.BEGIN_REQUEST(url => L_URL, method => 'POST', http_version => 'HTTP/1.1');
    UTL_HTTP.SET_HEADER(L_HTTP_REQ, 'Content-Type',   'application/json; charset=utf-8');
    UTL_HTTP.SET_HEADER(L_HTTP_REQ, 'Accept',         'application/json');
    UTL_HTTP.SET_HEADER(L_HTTP_REQ, 'Content-Length', TO_CHAR(UTL_RAW.LENGTH(L_RAW_BODY)));
    UTL_HTTP.SET_HEADER(L_HTTP_REQ, 'User-Agent',     'Oracle-OpenWA/4.0');
    IF P_API_KEY IS NOT NULL THEN
      UTL_HTTP.SET_HEADER(L_HTTP_REQ, 'x-api-key', P_API_KEY);
    END IF;
    UTL_HTTP.WRITE_RAW(L_HTTP_REQ, L_RAW_BODY);
    L_HTTP_RESP := UTL_HTTP.GET_RESPONSE(L_HTTP_REQ);
    BEGIN
      LOOP
        UTL_HTTP.READ_TEXT(L_HTTP_RESP, L_BUFFER, 4096);
        L_RESP_TEXT := L_RESP_TEXT || L_BUFFER;
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.END_OF_BODY THEN NULL;
    END;
    UTL_HTTP.END_RESPONSE(L_HTTP_RESP);
    RETURN L_RESP_TEXT;
  EXCEPTION
    WHEN OTHERS THEN
      BEGIN UTL_HTTP.END_RESPONSE(L_HTTP_RESP); EXCEPTION WHEN OTHERS THEN NULL; END;
      RETURN '{"status":"error","message":"' || ESCAPE_JSON(SQLERRM) || '"}';
  END CALL_OPENWA_POST;

  FUNCTION SEND_TEXT(P_PHONE VARCHAR2, P_MSG VARCHAR2) RETURN VARCHAR2 IS
    L_PHONE VARCHAR2(20);
  BEGIN
    L_PHONE := REGEXP_REPLACE(P_PHONE, '[^0-9]', '');
    IF SUBSTR(L_PHONE, 1, 1) = '0' THEN
      L_PHONE := '967' || SUBSTR(L_PHONE, 2);
    END IF;
    RETURN CALL_OPENWA_POST('/arslanhook/send',
      '{"to":"' || L_PHONE || '","text":"' || ESCAPE_JSON(P_MSG) || '"}', NULL);
  END SEND_TEXT;

  FUNCTION SEND_IMAGE(P_PHONE VARCHAR2, P_IMAGE_URL VARCHAR2, P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    L_PHONE VARCHAR2(20);
    L_PATH  VARCHAR2(200);
    L_JSON  VARCHAR2(32767);
  BEGIN
    L_PHONE := REGEXP_REPLACE(P_PHONE, '[^0-9]', '');
    IF SUBSTR(L_PHONE, 1, 1) = '0' THEN L_PHONE := '967' || SUBSTR(L_PHONE, 2); END IF;
    L_PATH := '/api/sessions/' || C_SESSION_ID || '/messages/send-image';
    L_JSON := '{"chatId":"' || L_PHONE || '@c.us","image":{"url":"' || ESCAPE_JSON(P_IMAGE_URL) || '"}' ||
              CASE WHEN P_CAPTION IS NOT NULL THEN ',"caption":"' || ESCAPE_JSON(P_CAPTION) || '"' ELSE '' END || '}';
    RETURN CALL_OPENWA_POST(L_PATH, L_JSON, C_API_KEY);
  END SEND_IMAGE;

  FUNCTION SEND_IMAGE_B64(P_PHONE VARCHAR2, P_BASE64_IMAGE VARCHAR2, P_MIMETYPE VARCHAR2 DEFAULT 'image/jpeg', P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    L_PHONE VARCHAR2(20);
    L_PATH  VARCHAR2(200);
    L_JSON  VARCHAR2(32767);
  BEGIN
    L_PHONE := REGEXP_REPLACE(P_PHONE, '[^0-9]', '');
    IF SUBSTR(L_PHONE, 1, 1) = '0' THEN L_PHONE := '967' || SUBSTR(L_PHONE, 2); END IF;
    L_PATH := '/api/sessions/' || C_SESSION_ID || '/messages/send-image';
    L_JSON := '{"chatId":"' || L_PHONE || '@c.us","image":{"data":"data:' || P_MIMETYPE || ';base64,' || P_BASE64_IMAGE || '"}' ||
              CASE WHEN P_CAPTION IS NOT NULL THEN ',"caption":"' || ESCAPE_JSON(P_CAPTION) || '"' ELSE '' END || '}';
    RETURN CALL_OPENWA_POST(L_PATH, L_JSON, C_API_KEY);
  END SEND_IMAGE_B64;

  FUNCTION SEND_FILE(P_PHONE VARCHAR2, P_FILE_URL VARCHAR2, P_FILENAME VARCHAR2 DEFAULT NULL, P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    L_PHONE VARCHAR2(20);
    L_PATH  VARCHAR2(200);
    L_JSON  VARCHAR2(32767);
  BEGIN
    L_PHONE := REGEXP_REPLACE(P_PHONE, '[^0-9]', '');
    IF SUBSTR(L_PHONE, 1, 1) = '0' THEN L_PHONE := '967' || SUBSTR(L_PHONE, 2); END IF;
    L_PATH := '/api/sessions/' || C_SESSION_ID || '/messages/send-document';
    L_JSON := '{"chatId":"' || L_PHONE || '@c.us","document":{"url":"' || ESCAPE_JSON(P_FILE_URL) || '"}' ||
              CASE WHEN P_FILENAME IS NOT NULL THEN ',"filename":"' || ESCAPE_JSON(P_FILENAME) || '"' ELSE '' END ||
              CASE WHEN P_CAPTION IS NOT NULL THEN ',"caption":"' || ESCAPE_JSON(P_CAPTION) || '"' ELSE '' END || '}';
    RETURN CALL_OPENWA_POST(L_PATH, L_JSON, C_API_KEY);
  END SEND_FILE;

  FUNCTION SEND_FILE_B64(P_PHONE VARCHAR2, P_BASE64_FILE VARCHAR2, P_FILENAME VARCHAR2, P_MIMETYPE VARCHAR2 DEFAULT 'application/octet-stream', P_CAPTION VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    L_PHONE VARCHAR2(20);
    L_PATH  VARCHAR2(200);
    L_JSON  VARCHAR2(32767);
  BEGIN
    L_PHONE := REGEXP_REPLACE(P_PHONE, '[^0-9]', '');
    IF SUBSTR(L_PHONE, 1, 1) = '0' THEN L_PHONE := '967' || SUBSTR(L_PHONE, 2); END IF;
    L_PATH := '/api/sessions/' || C_SESSION_ID || '/messages/send-document';
    L_JSON := '{"chatId":"' || L_PHONE || '@c.us","document":{"data":"data:' || P_MIMETYPE || ';base64,' || P_BASE64_FILE || '"},"filename":"' || ESCAPE_JSON(P_FILENAME) || '"' ||
              CASE WHEN P_CAPTION IS NOT NULL THEN ',"caption":"' || ESCAPE_JSON(P_CAPTION) || '"' ELSE '' END || '}';
    RETURN CALL_OPENWA_POST(L_PATH, L_JSON, C_API_KEY);
  END SEND_FILE_B64;

  PROCEDURE SET_W_SEND_ATTEMPT(P_ID NUMBER) IS
  BEGIN
    UPDATE ACCOUNTS.W_MSG_QUEUE
       SET SEND_ATTEMPT = NVL(SEND_ATTEMPT, 0) + 1,
           UPDATED_AT   = SYSDATE,
           UPDATED_BY   = 'SCHEDULER'
     WHERE ID = P_ID;
  END SET_W_SEND_ATTEMPT;

  PROCEDURE ARCHIVE_W_MSG(P_ID IN W_MSG_QUEUE.ID%TYPE, P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE, P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE) IS
    L_REC W_MSG_QUEUE%ROWTYPE;
  BEGIN
    SELECT * INTO L_REC FROM ACCOUNTS.W_MSG_QUEUE WHERE ID = P_ID;
    MERGE_W_MSG_ARCHIVE(
      P_ID => L_REC.ID, P_MSG_TEXT => L_REC.MSG_TEXT, P_MOBILE_NO => L_REC.MOBILE_NO,
      P_IS_SENT => 'Y', P_CREATED_AT => L_REC.CREATED_AT, P_CREATED_BY => L_REC.CREATED_BY,
      P_UPDATED_AT => P_UPDATED_AT, P_UPDATED_BY => P_UPDATED_BY,
      P_SERVICE_ID => L_REC.SERVICE_ID, P_PROVIDER_ID => L_REC.PROVIDER_ID,
      P_CUSTOMER_NAME => L_REC.CUSTOMER_NAME,
      P_SEND_ATTEMPT => NVL(L_REC.SEND_ATTEMPT, 0) + 1,
      P_FILE_PATH => L_REC.FILE_PATH, P_FILE_NAME => L_REC.FILE_NAME,
      P_FILE_TYPE => L_REC.FILE_TYPE, P_CAPTION => L_REC.CAPTION);
    DEL_W_MSG_QUEUE(P_ID => P_ID);
  END ARCHIVE_W_MSG;

  PROCEDURE PUSH_W_QUEUE IS
    CURSOR C_MSGS IS
      SELECT ID, MSG_TEXT, MOBILE_NO, FILE_PATH, FILE_NAME, FILE_TYPE, CAPTION
        FROM ACCOUNTS.W_MSG_QUEUE
       WHERE IS_SENT = 'N' AND (SEND_ATTEMPT IS NULL OR SEND_ATTEMPT < 3)
       ORDER BY CREATED_AT
      FOR UPDATE SKIP LOCKED;
    L_RESP       VARCHAR2(32767);
    L_IS_SUCCESS BOOLEAN;
    L_NOW        DATE := SYSDATE;
  BEGIN
    FOR R IN C_MSGS LOOP
      BEGIN
        L_RESP := NULL;
        IF R.FILE_PATH IS NOT NULL AND LOWER(NVL(R.FILE_TYPE,'')) IN ('jpg','jpeg','png','gif','webp','image') THEN
          L_RESP := SEND_IMAGE(R.MOBILE_NO, R.FILE_PATH, R.CAPTION);
        ELSIF R.FILE_NAME IS NOT NULL AND R.FILE_PATH IS NOT NULL THEN
          L_RESP := SEND_FILE(R.MOBILE_NO, R.FILE_PATH, R.FILE_NAME, R.CAPTION);
        ELSE
          L_RESP := SEND_TEXT(R.MOBILE_NO, NVL(R.MSG_TEXT, R.CAPTION));
        END IF;
        L_IS_SUCCESS :=
          (INSTR(NVL(L_RESP,''), '"status":"success"') > 0) OR
          (INSTR(NVL(L_RESP,''), '"messageId"') > 0) OR
          (INSTR(NVL(L_RESP,''), '"id"') > 0 AND INSTR(NVL(L_RESP,''), '"error"') = 0);
        IF L_IS_SUCCESS THEN
          ARCHIVE_W_MSG(P_ID => R.ID, P_UPDATED_AT => L_NOW, P_UPDATED_BY => 'SCHEDULER');
        ELSE
          SET_W_SEND_ATTEMPT(R.ID);
        END IF;
        COMMIT;
      EXCEPTION
        WHEN OTHERS THEN
          ROLLBACK;
          BEGIN SET_W_SEND_ATTEMPT(R.ID); COMMIT; EXCEPTION WHEN OTHERS THEN ROLLBACK; END;
      END;
    END LOOP;
  END PUSH_W_QUEUE;

  PROCEDURE INS_W_MSG_QUEUE(P_ID IN W_MSG_QUEUE.ID%TYPE,P_MSG_TEXT IN W_MSG_QUEUE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_QUEUE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_QUEUE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_QUEUE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_QUEUE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_QUEUE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_QUEUE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE,P_FILE_PATH IN W_MSG_QUEUE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_QUEUE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_QUEUE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_QUEUE.CAPTION%TYPE) IS
  BEGIN
    INSERT INTO ACCOUNTS.W_MSG_QUEUE(ID,MSG_TEXT,MOBILE_NO,IS_SENT,CREATED_AT,CREATED_BY,UPDATED_AT,UPDATED_BY,SERVICE_ID,PROVIDER_ID,CUSTOMER_NAME,FILE_PATH,FILE_NAME,FILE_TYPE,CAPTION)
    VALUES(P_ID,P_MSG_TEXT,P_MOBILE_NO,P_IS_SENT,P_CREATED_AT,P_CREATED_BY,P_UPDATED_AT,P_UPDATED_BY,P_SERVICE_ID,P_PROVIDER_ID,P_CUSTOMER_NAME,P_FILE_PATH,P_FILE_NAME,P_FILE_TYPE,P_CAPTION);
  END INS_W_MSG_QUEUE;

  PROCEDURE MERGE_W_MSG_QUEUE(P_ID IN W_MSG_QUEUE.ID%TYPE,P_MSG_TEXT IN W_MSG_QUEUE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_QUEUE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_QUEUE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_QUEUE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_QUEUE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_QUEUE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_QUEUE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE,P_FILE_PATH IN W_MSG_QUEUE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_QUEUE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_QUEUE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_QUEUE.CAPTION%TYPE) IS
  BEGIN
    MERGE INTO ACCOUNTS.W_MSG_QUEUE T USING (SELECT P_ID AS ID FROM DUAL) S ON (T.ID=S.ID)
    WHEN MATCHED THEN UPDATE SET MSG_TEXT=P_MSG_TEXT,MOBILE_NO=P_MOBILE_NO,IS_SENT=P_IS_SENT,UPDATED_AT=P_UPDATED_AT,UPDATED_BY=P_UPDATED_BY,SERVICE_ID=P_SERVICE_ID,PROVIDER_ID=P_PROVIDER_ID,CUSTOMER_NAME=P_CUSTOMER_NAME,FILE_PATH=P_FILE_PATH,FILE_NAME=P_FILE_NAME,FILE_TYPE=P_FILE_TYPE,CAPTION=P_CAPTION
    WHEN NOT MATCHED THEN INSERT(ID,MSG_TEXT,MOBILE_NO,IS_SENT,CREATED_AT,CREATED_BY,UPDATED_AT,UPDATED_BY,SERVICE_ID,PROVIDER_ID,CUSTOMER_NAME,FILE_PATH,FILE_NAME,FILE_TYPE,CAPTION) VALUES(P_ID,P_MSG_TEXT,P_MOBILE_NO,P_IS_SENT,P_CREATED_AT,P_CREATED_BY,P_UPDATED_AT,P_UPDATED_BY,P_SERVICE_ID,P_PROVIDER_ID,P_CUSTOMER_NAME,P_FILE_PATH,P_FILE_NAME,P_FILE_TYPE,P_CAPTION);
  END MERGE_W_MSG_QUEUE;

  PROCEDURE UPD_W_MSG_QUEUE(P_ID IN W_MSG_QUEUE.ID%TYPE,P_MSG_TEXT IN W_MSG_QUEUE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_QUEUE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_QUEUE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_QUEUE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_QUEUE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_QUEUE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_QUEUE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_QUEUE.CUSTOMER_NAME%TYPE,P_FILE_PATH IN W_MSG_QUEUE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_QUEUE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_QUEUE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_QUEUE.CAPTION%TYPE) IS
  BEGIN
    UPDATE ACCOUNTS.W_MSG_QUEUE SET MSG_TEXT=P_MSG_TEXT,MOBILE_NO=P_MOBILE_NO,IS_SENT=P_IS_SENT,CREATED_AT=P_CREATED_AT,CREATED_BY=P_CREATED_BY,UPDATED_AT=P_UPDATED_AT,UPDATED_BY=P_UPDATED_BY,SERVICE_ID=P_SERVICE_ID,PROVIDER_ID=P_PROVIDER_ID,CUSTOMER_NAME=P_CUSTOMER_NAME,FILE_PATH=P_FILE_PATH,FILE_NAME=P_FILE_NAME,FILE_TYPE=P_FILE_TYPE,CAPTION=P_CAPTION WHERE ID=P_ID;
  END UPD_W_MSG_QUEUE;

  PROCEDURE DEL_W_MSG_QUEUE(P_ID IN W_MSG_QUEUE.ID%TYPE) IS
  BEGIN DELETE FROM ACCOUNTS.W_MSG_QUEUE WHERE ID=P_ID; END DEL_W_MSG_QUEUE;

  PROCEDURE SET_W_MSG_SENT(P_ID IN W_MSG_QUEUE.ID%TYPE,P_UPDATED_AT IN W_MSG_QUEUE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_QUEUE.UPDATED_BY%TYPE) IS
  BEGIN
    UPDATE ACCOUNTS.W_MSG_QUEUE SET IS_SENT='Y',UPDATED_AT=P_UPDATED_AT,UPDATED_BY=P_UPDATED_BY WHERE ID=P_ID;
  END SET_W_MSG_SENT;

  PROCEDURE INS_W_MSG_ARCHIVE(P_ID IN W_MSG_ARCHIVE.ID%TYPE,P_MSG_TEXT IN W_MSG_ARCHIVE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_ARCHIVE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_ARCHIVE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_ARCHIVE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_ARCHIVE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_ARCHIVE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_ARCHIVE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_ARCHIVE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE,P_SEND_ATTEMPT IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE,P_FILE_PATH IN W_MSG_ARCHIVE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_ARCHIVE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_ARCHIVE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_ARCHIVE.CAPTION%TYPE) IS
  BEGIN
    INSERT INTO ACCOUNTS.W_MSG_ARCHIVE(ID,MSG_TEXT,MOBILE_NO,IS_SENT,CREATED_AT,CREATED_BY,UPDATED_AT,UPDATED_BY,SERVICE_ID,PROVIDER_ID,CUSTOMER_NAME,SEND_ATTEMPT,FILE_PATH,FILE_NAME,FILE_TYPE,CAPTION)
    VALUES(P_ID,P_MSG_TEXT,P_MOBILE_NO,P_IS_SENT,P_CREATED_AT,P_CREATED_BY,P_UPDATED_AT,P_UPDATED_BY,P_SERVICE_ID,P_PROVIDER_ID,P_CUSTOMER_NAME,P_SEND_ATTEMPT,P_FILE_PATH,P_FILE_NAME,P_FILE_TYPE,P_CAPTION);
  END INS_W_MSG_ARCHIVE;

  PROCEDURE MERGE_W_MSG_ARCHIVE(P_ID IN W_MSG_ARCHIVE.ID%TYPE,P_MSG_TEXT IN W_MSG_ARCHIVE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_ARCHIVE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_ARCHIVE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_ARCHIVE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_ARCHIVE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_ARCHIVE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_ARCHIVE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_ARCHIVE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE,P_SEND_ATTEMPT IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE,P_FILE_PATH IN W_MSG_ARCHIVE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_ARCHIVE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_ARCHIVE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_ARCHIVE.CAPTION%TYPE) IS
  BEGIN
    MERGE INTO ACCOUNTS.W_MSG_ARCHIVE T USING (SELECT P_ID AS ID FROM DUAL) S ON (T.ID=S.ID)
    WHEN MATCHED THEN UPDATE SET MSG_TEXT=P_MSG_TEXT,MOBILE_NO=P_MOBILE_NO,IS_SENT=P_IS_SENT,UPDATED_AT=P_UPDATED_AT,UPDATED_BY=P_UPDATED_BY,SERVICE_ID=P_SERVICE_ID,PROVIDER_ID=P_PROVIDER_ID,CUSTOMER_NAME=P_CUSTOMER_NAME,SEND_ATTEMPT=P_SEND_ATTEMPT,FILE_PATH=P_FILE_PATH,FILE_NAME=P_FILE_NAME,FILE_TYPE=P_FILE_TYPE,CAPTION=P_CAPTION
    WHEN NOT MATCHED THEN INSERT(ID,MSG_TEXT,MOBILE_NO,IS_SENT,CREATED_AT,CREATED_BY,UPDATED_AT,UPDATED_BY,SERVICE_ID,PROVIDER_ID,CUSTOMER_NAME,SEND_ATTEMPT,FILE_PATH,FILE_NAME,FILE_TYPE,CAPTION) VALUES(P_ID,P_MSG_TEXT,P_MOBILE_NO,P_IS_SENT,P_CREATED_AT,P_CREATED_BY,P_UPDATED_AT,P_UPDATED_BY,P_SERVICE_ID,P_PROVIDER_ID,P_CUSTOMER_NAME,P_SEND_ATTEMPT,P_FILE_PATH,P_FILE_NAME,P_FILE_TYPE,P_CAPTION);
  END MERGE_W_MSG_ARCHIVE;

  PROCEDURE UPD_W_MSG_ARCHIVE(P_ID IN W_MSG_ARCHIVE.ID%TYPE,P_MSG_TEXT IN W_MSG_ARCHIVE.MSG_TEXT%TYPE,P_MOBILE_NO IN W_MSG_ARCHIVE.MOBILE_NO%TYPE,P_IS_SENT IN W_MSG_ARCHIVE.IS_SENT%TYPE,P_CREATED_AT IN W_MSG_ARCHIVE.CREATED_AT%TYPE,P_CREATED_BY IN W_MSG_ARCHIVE.CREATED_BY%TYPE,P_UPDATED_AT IN W_MSG_ARCHIVE.UPDATED_AT%TYPE,P_UPDATED_BY IN W_MSG_ARCHIVE.UPDATED_BY%TYPE,P_SERVICE_ID IN W_MSG_ARCHIVE.SERVICE_ID%TYPE,P_PROVIDER_ID IN W_MSG_ARCHIVE.PROVIDER_ID%TYPE,P_CUSTOMER_NAME IN W_MSG_ARCHIVE.CUSTOMER_NAME%TYPE,P_SEND_ATTEMPT IN W_MSG_ARCHIVE.SEND_ATTEMPT%TYPE,P_FILE_PATH IN W_MSG_ARCHIVE.FILE_PATH%TYPE,P_FILE_NAME IN W_MSG_ARCHIVE.FILE_NAME%TYPE,P_FILE_TYPE IN W_MSG_ARCHIVE.FILE_TYPE%TYPE,P_CAPTION IN W_MSG_ARCHIVE.CAPTION%TYPE) IS
  BEGIN
    UPDATE ACCOUNTS.W_MSG_ARCHIVE SET MSG_TEXT=P_MSG_TEXT,MOBILE_NO=P_MOBILE_NO,IS_SENT=P_IS_SENT,CREATED_AT=P_CREATED_AT,CREATED_BY=P_CREATED_BY,UPDATED_AT=P_UPDATED_AT,UPDATED_BY=P_UPDATED_BY,SERVICE_ID=P_SERVICE_ID,PROVIDER_ID=P_PROVIDER_ID,CUSTOMER_NAME=P_CUSTOMER_NAME,SEND_ATTEMPT=P_SEND_ATTEMPT,FILE_PATH=P_FILE_PATH,FILE_NAME=P_FILE_NAME,FILE_TYPE=P_FILE_TYPE,CAPTION=P_CAPTION WHERE ID=P_ID;
  END UPD_W_MSG_ARCHIVE;

  PROCEDURE DEL_W_MSG_ARCHIVE(P_ID IN W_MSG_ARCHIVE.ID%TYPE) IS
  BEGIN DELETE FROM ACCOUNTS.W_MSG_ARCHIVE WHERE ID=P_ID; END DEL_W_MSG_ARCHIVE;

END WHATSAPP_BRIDGE;
/
*/