import { Injectable, Logger, BadRequestException, NotFoundException, Optional, forwardRef, Inject } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import * as iconv from 'iconv-lite';
import { SessionService } from '../session/session.service';
import { MessageService } from '../message/message.service';
import { WebhookService } from '../webhook/webhook.service';
import { SessionStatus } from '../session/entities/session.entity';

export interface ReceivedWebhookEvent {
  id: string;
  timestamp: string;
  event?: string;
  sessionId?: string;
  data: any;
}

export interface SendMessageOptions {
  to: string;
  text?: string;
  caption?: string;
  base64_text?: string;
  base64_caption?: string;
  url?: string;
  base64?: string;
  mimetype?: string;
  filename?: string;
  type?: string;
  sessionId?: string;
}

/**
 * Decode Base64 encoded Windows-1256 string from Oracle using iconv
 */
export function decodeBase64Message(base64Str: string): string {
  try {
    const buffer = Buffer.from(base64Str, 'base64');
    return iconv.decode(buffer, 'windows-1256');
  } catch (e) {
    console.error('Base64 decode error:', e);
    return base64Str;
  }
}

@Injectable()
export class ArslanHookService {
  private readonly logger = new Logger('ArslanHook');
  private linkedSessionId: string | null = null;
  private readonly receivedEvents: ReceivedWebhookEvent[] = [];
  private readonly MAX_EVENTS = 100;

  constructor(
    @Inject(forwardRef(() => SessionService))
    private readonly sessionService: SessionService,
    @Inject(forwardRef(() => MessageService))
    private readonly messageService: MessageService,
    @Inject(forwardRef(() => WebhookService))
    private readonly webhookService: WebhookService,
  ) {}

  /**
   * Decode Win-1256 hex string sent by Oracle
   * Format: HEX1256:CAE320C7E4... -> Arabic Unicode text
   * Oracle WE8MSWIN1252 DB stores Arabic as AR8MSWIN1256 bytes.
   * Since Oracle can't convert them (charset mismatch), it sends the raw bytes
  /**
   * Official Unicode Consortium Windows-1256 (CP1256) mapping table
   */
  private static readonly CP1256_MAP: Record<number, number> = {
    0x80: 0x20AC, 0x81: 0x067E, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
    0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030,
    0x8A: 0x0679, 0x8B: 0x2039, 0x8C: 0x0152, 0x8D: 0x0686, 0x8E: 0x0698,
    0x8F: 0x06AF, 0x90: 0x0670, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
    0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x06A9,
    0x99: 0x2122, 0x9A: 0x0691, 0x9B: 0x203A, 0x9C: 0x0153, 0x9D: 0x200C,
    0x9E: 0x200D, 0x9F: 0x06BA, 0xA0: 0x00A0, 0xA1: 0x060C, 0xA2: 0x00A2,
    0xA3: 0x00A3, 0xA4: 0x00A4, 0xA5: 0x00A5, 0xA6: 0x00A6, 0xA7: 0x00A7,
    0xA8: 0x00A8, 0xA9: 0x00A9, 0xAA: 0x06BE, 0xAB: 0x00AB, 0xAC: 0x00AC,
    0xAD: 0x00AD, 0xAE: 0x00AE, 0xAF: 0x00AF, 0xB0: 0x00B0, 0xB1: 0x00B1,
    0xB2: 0x00B2, 0xB3: 0x00B3, 0xB4: 0x00B4, 0xB5: 0x00B5, 0xB6: 0x00B6,
    0xB7: 0x00B7, 0xB8: 0x00B8, 0xB9: 0x00B9, 0xBA: 0x061B, 0xBB: 0x00BB,
    0xBC: 0x00BC, 0xBD: 0x00BD, 0xBE: 0x00BE, 0xBF: 0x061F, 0xC0: 0x06C1,
    0xC1: 0x0621, 0xC2: 0x0622, 0xC3: 0x0623, 0xC4: 0x0624, 0xC5: 0x0625,
    0xC6: 0x0626, 0xC7: 0x0627, 0xC8: 0x0628, 0xC9: 0x0629, 0xCA: 0x062A,
    0xCB: 0x062B, 0xCC: 0x062C, 0xCD: 0x062D, 0xCE: 0x062E, 0xCF: 0x062F,
    0xD0: 0x0630, 0xD1: 0x0631, 0xD2: 0x0632, 0xD3: 0x0633, 0xD4: 0x0634,
    0xD5: 0x0635, 0xD6: 0x0636, 0xD7: 0x00D7, 0xD8: 0x0637, 0xD9: 0x0638,
    0xDA: 0x0639, 0xDB: 0x063A, 0xDC: 0x0640, 0xDD: 0x0641, 0xDE: 0x0642,
    0xDF: 0x0643, 0xE0: 0x00E0, 0xE1: 0x0644, 0xE2: 0x00E2, 0xE3: 0x0645,
    0xE4: 0x0646, 0xE5: 0x0647, 0xE6: 0x0648, 0xE7: 0x00E7, 0xE8: 0x00E8,
    0xE9: 0x00E9, 0xEA: 0x00EA, 0xEB: 0x00EB, 0xEC: 0x0649, 0xED: 0x064A,
    0xEE: 0x064B, 0xEF: 0x064C, 0xF0: 0x064D, 0xF1: 0x064E, 0xF2: 0x064F,
    0xF3: 0x0650, 0xF4: 0x0651, 0xF5: 0x0652, 0xF6: 0x200E, 0xF7: 0x200F,
    0xF8: 0x0640, 0xF9: 0x067E, 0xFA: 0x0670, 0xFB: 0x06D5, 0xFC: 0x06CC,
    0xFD: 0x06C6, 0xFE: 0x06D2, 0xFF: 0x0640,
  };

  /**
   * Decode Windows-1256 raw bytes to Unicode string
   */
  decodeWindows1256Buffer(buf: Buffer): string {
    let result = '';
    for (let i = 0; i < buf.length; i++) {
      const byte = buf[i];
      if (byte < 0x80) {
        result += String.fromCharCode(byte);
      } else {
        const uCode = ArslanHookService.CP1256_MAP[byte] ?? byte;
        result += String.fromCharCode(uCode);
      }
    }
    return result;
  }

  /**
   * Decode Win-1256 hex string sent by Oracle
   */
  private decodeHex1256(hex: string): string {
    const cleanHex = hex.replace(/[^0-9A-Fa-f]/g, '');
    const buf = Buffer.from(cleanHex, 'hex');
    return this.decodeWindows1256Buffer(buf);
  }

  /**
   * Smart Arabic encoding decoder
   * Handles:
   * 1. BASE64 / BASE64: prefix (Cleanest ASCII transmission from Oracle via decodeBase64Message)
   * 2. Pure Base64 strings from Oracle (without prefix)
   * 3. HEX1256: prefix
   * 4. Plain valid Arabic Unicode (preserves untouched)
   * 5. Windows-1256 single-byte characters misread as Latin-1 (decoded via iconv)
   * 6. UTF-8 Mojibake (double-encoding)
   */
  fixArabicEncoding(input?: string): string {
    if (!input || typeof input !== 'string') return input || '';

    // 0. Base64 encoded Windows-1256 with BASE64: prefix
    if (input.startsWith('BASE64:')) {
      const b64 = input.slice(7).trim();
      const decoded = decodeBase64Message(b64);
      this.logger.debug(`[Encoding] BASE64 decoded via iconv: "${decoded.substring(0, 40)}"`);
      return decoded;
    }

    // 1. HEX1256: prefix from Oracle
    if (input.startsWith('HEX1256:')) {
      const hexPart = input.slice(8);
      const decoded = this.decodeHex1256(hexPart);
      this.logger.debug(`[Encoding] HEX1256 decoded: "${decoded.substring(0, 40)}"`);
      return decoded;
    }

    // 2. If string already contains standard Arabic Unicode characters - return untouched
    if (/[\u0600-\u06FF]/.test(input)) {
      return input;
    }

    // 3. Raw Base64 string check (e.g. from Oracle without prefix)
    const trimmed = input.trim();
    if (trimmed.length >= 4 && trimmed.length % 4 === 0 && /^[A-Za-z0-9+/=]+$/.test(trimmed)) {
      try {
        const decoded = decodeBase64Message(trimmed);
        if (/[\u0600-\u06FF]/.test(decoded)) {
          this.logger.debug(`[Encoding] Raw Base64 decoded via iconv: "${decoded.substring(0, 40)}"`);
          return decoded;
        }
      } catch {
        // ignore
      }
    }

    // 4. UTF-8 Mojibake check (two-byte sequence in C0-DF followed by 80-BF)
    if (/[\u00C0-\u00DF][\u0080-\u00BF]/.test(input)) {
      try {
        const bytes = Buffer.from(input, 'latin1');
        const decoded = bytes.toString('utf8');
        if (/[\u0600-\u06FF]/.test(decoded)) {
          this.logger.debug(`[Encoding] Fixed UTF-8 mojibake: "${decoded.substring(0, 40)}"`);
          return decoded;
        }
      } catch {
        // ignore
      }
    }

    // 5. Windows-1256 single-byte characters stored as Latin-1 code points (0x80 - 0xFF)
    if (/[\u0080-\u00FF]/.test(input)) {
      try {
        const rawBuf = Buffer.from(input, 'latin1');
        const decoded = iconv.decode(rawBuf, 'windows-1256');
        if (/[\u0600-\u06FF]/.test(decoded)) {
          this.logger.debug(`[Encoding] Fixed CP1256 Latin-1 via iconv: "${decoded.substring(0, 40)}"`);
          return decoded;
        }
      } catch {
        const decoded = this.decodeWindows1256Buffer(Buffer.from(input, 'latin1'));
        if (/[\u0600-\u06FF]/.test(decoded)) {
          return decoded;
        }
      }
    }

    return input;
  }

  /**
   * Normalize phone number to full international WhatsApp format (e.g. 967776422777@c.us)
   */
  normalizeChatId(to: string): string {
    if (to.includes('@')) return to;
    let clean = to.replace(/[^0-9]/g, '');
    if (clean.startsWith('00')) clean = clean.slice(2);
    else if (clean.startsWith('07')) clean = '967' + clean.slice(1);
    else if (clean.startsWith('05')) clean = '966' + clean.slice(1);
    else if (clean.startsWith('0')) clean = '967' + clean.slice(1);
    else if (clean.length === 9 && clean.startsWith('7')) clean = '967' + clean;
    return `${clean}@c.us`;
  }

  /**
   * Set the default linked session ID for arslanhook
   */
  async linkSession(sessionId: string, autoRegisterWebhook = true): Promise<{ sessionId: string; webhookRegistered: boolean }> {
    const session = await this.sessionService.findOne(sessionId);
    if (!session) {
      throw new NotFoundException(`Session with id '${sessionId}' not found`);
    }

    this.linkedSessionId = sessionId;
    this.logger.log(`Session '${sessionId}' linked to ArslanHook`);

    let webhookRegistered = false;
    if (autoRegisterWebhook) {
      const webhookUrl = 'http://127.0.0.1:2785/arslanhook';
      try {
        const existing = await this.webhookService.findBySession(sessionId);
        const match = existing.find(w => w.url === webhookUrl);
        if (!match) {
          await this.webhookService.create(sessionId, {
            url: webhookUrl,
            events: ['*'],
          });
          webhookRegistered = true;
          this.logger.log(`Registered webhook ${webhookUrl} for session '${sessionId}'`);
        } else {
          webhookRegistered = true;
        }
      } catch (err) {
        this.logger.warn(`Could not auto-register webhook: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    return { sessionId, webhookRegistered };
  }

  getLinkedSessionId(): string | null {
    return this.linkedSessionId;
  }

  /**
   * Resolve an active session: explicitly linked, or provided, or first authenticated session
   */
  async resolveSessionId(preferredSessionId?: string): Promise<string> {
    if (preferredSessionId) {
      const session = await this.sessionService.findOne(preferredSessionId);
      if (session) return session.id;
    }

    if (this.linkedSessionId) {
      const session = await this.sessionService.findOne(this.linkedSessionId);
      if (session) return session.id;
    }

    const allSessions = await this.sessionService.findAll();
    if (allSessions.length === 0) {
      throw new BadRequestException('No WhatsApp session exists. Please create a session first via Dashboard or POST /api/sessions');
    }

    // Try finding working/ready session
    const ready = allSessions.find(s => s.status === SessionStatus.READY || s.status === SessionStatus.QR_READY);
    if (ready) return ready.id;

    return allSessions[0].id;
  }

  /**
   * Send WhatsApp message (text, image, or document) via arslanhook
   */
  async sendMessage(options: SendMessageOptions): Promise<any> {
    const { to, text, caption, url, base64, mimetype, filename, type, sessionId: explicitSessionId, base64_text, base64_caption } = options;
    if (!to) {
      throw new BadRequestException("Parameter 'to' is required to send a message.");
    }

    // Apply Arabic encoding fix via decodeBase64Message and fixArabicEncoding
    let rawText = text;
    if (base64_text) {
      rawText = decodeBase64Message(base64_text);
    }
    let rawCaption = caption;
    if (base64_caption) {
      rawCaption = decodeBase64Message(base64_caption);
    } else if (!rawCaption && base64_text) {
      rawCaption = decodeBase64Message(base64_text);
    }

    const fixedText = rawText ? this.fixArabicEncoding(rawText) : undefined;
    const fixedCaption = rawCaption ? this.fixArabicEncoding(rawCaption) : fixedText;
    const targetSessionId = await this.resolveSessionId(explicitSessionId);
    const chatId = this.normalizeChatId(to);

    this.logger.log(`[ArslanHook] sendMessage to=${chatId} type=${type || 'auto'} hasText=${!!fixedText} hasUrl=${!!url} hasBase64=${!!base64}`);
    if (fixedText) {
      this.logger.debug(`[ArslanHook] Message text (first 80 chars): ${fixedText.substring(0, 80)}`);
    }

    let effectiveUrl = url;
    let effectiveBase64 = base64;
    let effectiveMime = mimetype;
    let effectiveFilename = filename;

    // Check if url, filePath, or filename points to a local file in C:\ultramsg-bridge\public
    const publicFolder = 'C:\\ultramsg-bridge\\public';
    let localFilePath: string | null = null;

    if (url && (fs.existsSync(url) || !/^https?:\/\//i.test(url))) {
      if (fs.existsSync(url)) {
        localFilePath = url;
      } else if (fs.existsSync(path.join(publicFolder, url))) {
        localFilePath = path.join(publicFolder, url);
      }
    }
    if (!localFilePath && filename && fs.existsSync(path.join(publicFolder, filename))) {
      localFilePath = path.join(publicFolder, filename);
    }

    if (localFilePath) {
      try {
        const fileBuf = fs.readFileSync(localFilePath);
        effectiveBase64 = fileBuf.toString('base64');
        effectiveUrl = undefined;
        if (!effectiveFilename) {
          effectiveFilename = path.basename(localFilePath);
        }
        if (!effectiveMime) {
          const ext = path.extname(localFilePath).toLowerCase();
          const mimeMap: Record<string, string> = {
            '.pdf': 'application/pdf',
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.png': 'image/png',
            '.gif': 'image/gif',
            '.webp': 'image/webp',
            '.txt': 'text/plain',
            '.doc': 'application/msword',
            '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            '.xls': 'application/vnd.ms-excel',
            '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          };
          effectiveMime = mimeMap[ext] || 'application/octet-stream';
        }
        this.logger.log(`Resolved local file from public dir: ${localFilePath} (${fileBuf.length} bytes, mime: ${effectiveMime})`);
      } catch (err) {
        this.logger.warn(`Could not read local file ${localFilePath}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // If media is provided (URL or Base64)
    if (effectiveUrl || effectiveBase64) {
      const isImage = type === 'image' ||
        (effectiveMime && effectiveMime.startsWith('image/')) ||
        (effectiveUrl && /\.(jpg|jpeg|png|webp|gif)$/i.test(effectiveUrl)) ||
        (effectiveFilename && /\.(jpg|jpeg|png|webp|gif)$/i.test(effectiveFilename));

      if (isImage) {
        this.logger.log(`Sending image to ${chatId} via session ${targetSessionId}`);
        try {
          const result = await this.messageService.sendImage(targetSessionId, {
            chatId,
            url: effectiveUrl,
            base64: effectiveBase64,
            mimetype: effectiveMime || 'image/jpeg',
            caption: fixedCaption || undefined,
          });
          return {
            status: 'success',
            message: 'Image sent successfully via ArslanHook',
            sessionId: targetSessionId,
            to,
            chatId,
            result,
          };
        } catch (err: any) {
          this.logger.error(`sendImage error: ${err?.message || err}`, err?.stack);
          throw new BadRequestException(`Failed to send image: ${err?.message || err}`);
        }
      }

      // Document / file send
      this.logger.log(`Sending document to ${chatId} via session ${targetSessionId}`);
      try {
        const result = await this.messageService.sendDocument(targetSessionId, {
          chatId,
          url: effectiveUrl,
          base64: effectiveBase64,
          mimetype: effectiveMime || 'application/octet-stream',
          filename: effectiveFilename || (effectiveUrl ? effectiveUrl.split('/').pop()?.split('?')[0] : 'file'),
          caption: fixedCaption || undefined,
        });
        return {
          status: 'success',
          message: 'Document sent successfully via ArslanHook',
          sessionId: targetSessionId,
          to,
          chatId,
          result,
        };
      } catch (err: any) {
        this.logger.error(`sendDocument error: ${err?.message || err}`, err?.stack);
        throw new BadRequestException(`Failed to send document: ${err?.message || err}`);
      }
    }

    // Pure text send
    if (!fixedText) {
      throw new BadRequestException("Parameters 'text', 'url', or 'base64' are required to send a message.");
    }

    this.logger.log(`Sending text message to ${chatId} via session ${targetSessionId}`);
    const result = await this.messageService.sendText(targetSessionId, {
      chatId,
      text: fixedText,
    });

    return {
      status: 'success',
      message: 'Message sent successfully via ArslanHook',
      sessionId: targetSessionId,
      to,
      chatId,
      text: fixedText,
      result,
    };
  }

  /**
   * Record received inbound webhook event
   */
  recordEvent(payload: any): ReceivedWebhookEvent {
    const eventRecord: ReceivedWebhookEvent = {
      id: `evt_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
      timestamp: new Date().toISOString(),
      event: payload?.event || payload?.type || 'unknown',
      sessionId: payload?.sessionId || payload?.session || this.linkedSessionId || undefined,
      data: payload,
    };

    this.receivedEvents.unshift(eventRecord);
    if (this.receivedEvents.length > this.MAX_EVENTS) {
      this.receivedEvents.pop();
    }

    this.logger.log(`[ArslanHook] Received webhook event: ${eventRecord.event} (Session: ${eventRecord.sessionId ?? 'N/A'})`);
    return eventRecord;
  }

  getEvents(limit = 50): ReceivedWebhookEvent[] {
    return this.receivedEvents.slice(0, limit);
  }

  clearEvents(): void {
    this.receivedEvents.length = 0;
  }

  async getStatus(): Promise<any> {
    const sessions = await this.sessionService.findAll().catch(() => []);
    return {
      status: 'active',
      name: 'ArslanHook Internal Webhook',
      endpoint: 'http://127.0.0.1:2785/arslanhook',
      linkedSessionId: this.linkedSessionId,
      availableSessions: sessions.map(s => ({ id: s.id, name: s.name, status: s.status })),
      receivedEventsCount: this.receivedEvents.length,
      usage: {
        send_message_post: 'POST http://127.0.0.1:2785/arslanhook with JSON: { "to": "9677xxxxxxxx", "text": "Hello" }',
        send_message_explicit: 'POST http://127.0.0.1:2785/arslanhook/send with JSON: { "to": "9677xxxxxxxx", "text": "Hello" }',
        link_session: 'POST http://127.0.0.1:2785/arslanhook/link with JSON: { "sessionId": "your-session-id" }',
        view_events: 'GET http://127.0.0.1:2785/arslanhook/events',
      },
    };
  }
}
