import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  Res,
  NotFoundException,
  UsePipes,
  ValidationPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Response } from 'express';
import * as fs from 'fs';
import * as path from 'path';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { Public } from '../auth/decorators/auth.decorators';
import { ArslanHookService } from './arslanhook.service';

@ApiTags('arslanhook')
@Public()
@Controller(['arslanhook', 'api/arslanhook'])
@UsePipes(new ValidationPipe({ whitelist: false, forbidNonWhitelisted: false }))
export class ArslanHookController {
  constructor(private readonly arslanHookService: ArslanHookService) {}

  @Get()
  @ApiOperation({ summary: 'Get ArslanHook webhook status and instructions' })
  async getStatus() {
    return this.arslanHookService.getStatus();
  }

  @Get('status')
  @ApiOperation({ summary: 'Get ArslanHook webhook status' })
  async getStatusAlias() {
    return this.arslanHookService.getStatus();
  }

  @Get('public/:fileName')
  @ApiOperation({ summary: 'Serve public media file from C:\\ultramsg-bridge\\public' })
  async getPublicFile(@Param('fileName') fileName: string, @Res() res: Response) {
    const filePath = path.join('C:\\ultramsg-bridge\\public', fileName);
    if (!fs.existsSync(filePath)) {
      throw new NotFoundException(`File ${fileName} not found in public folder`);
    }
    return res.sendFile(filePath);
  }

  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Dual-purpose webhook endpoint: receives incoming webhook events OR sends outgoing WhatsApp messages',
  })
  async handleWebhookOrSend(@Body() body: any, @Query('sessionId') querySessionId?: string) {
    const targetRecipient = body?.to || body?.phone || body?.number || body?.recipient || body?.chatId;
    const b64Text = body?.base64_text || body?.base64_message;
    const b64Cap = body?.base64_caption || b64Text;
    const rawText = b64Text ? `BASE64:${b64Text}` : (body?.text || body?.message || body?.body || body?.content);
    const rawCaption = b64Cap ? `BASE64:${b64Cap}` : (body?.caption || rawText);
    const targetText = rawText ? this.arslanHookService.fixArabicEncoding(String(rawText)) : undefined;
    const targetCaption = rawCaption ? this.arslanHookService.fixArabicEncoding(String(rawCaption)) : targetText;
    const url = body?.url || body?.filePath || body?.fileUrl || body?.imageUrl || body?.file_path;
    const base64 = body?.base64 || body?.data || body?.file_data;
    const sessionId = body?.sessionId || querySessionId;

    if ((targetRecipient && (targetText || targetCaption || url || base64)) && !body?.event && !body?.events) {
      return this.arslanHookService.sendMessage({
        to: String(targetRecipient),
        text: targetText,
        caption: targetCaption,
        base64_text: b64Text ? String(b64Text) : undefined,
        base64_caption: b64Cap ? String(b64Cap) : undefined,
        url: url ? String(url) : undefined,
        base64: base64 ? String(base64) : undefined,
        mimetype: body?.mimetype || body?.mimeType || body?.fileType || body?.file_type,
        filename: body?.filename || body?.fileName || body?.file_name,
        type: body?.type,
        sessionId,
      });
    }

    // Otherwise, treat as inbound webhook event
    const recorded = this.arslanHookService.recordEvent(body);
    return {
      status: 'success',
      action: 'event_received',
      eventId: recorded.id,
      timestamp: recorded.timestamp,
      message: 'Webhook event processed by ArslanHook successfully',
    };
  }

  @Post('send')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Send a WhatsApp message or media via ArslanHook' })
  async sendMessage(@Body() body: any, @Query('sessionId') querySessionId?: string) {
    const to = body?.to || body?.phone || body?.number || body?.recipient || body?.chatId;
    const b64Text = body?.base64_text || body?.base64_message;
    const b64Cap = body?.base64_caption || b64Text;
    const rawText = b64Text ? `BASE64:${b64Text}` : (body?.text || body?.message || body?.body || body?.content);
    const rawCaption = b64Cap ? `BASE64:${b64Cap}` : (body?.caption || rawText);
    const text = rawText ? this.arslanHookService.fixArabicEncoding(String(rawText)) : undefined;
    const caption = rawCaption ? this.arslanHookService.fixArabicEncoding(String(rawCaption)) : text;
    const url = body?.url || body?.filePath || body?.fileUrl || body?.imageUrl || body?.file_path;
    const base64 = body?.base64 || body?.data || body?.file_data;
    const sessionId = body?.sessionId || querySessionId;

    return this.arslanHookService.sendMessage({
      to: String(to),
      text,
      caption,
      base64_text: b64Text ? String(b64Text) : undefined,
      base64_caption: b64Cap ? String(b64Cap) : undefined,
      url: url ? String(url) : undefined,
      base64: base64 ? String(base64) : undefined,
      mimetype: body?.mimetype || body?.mimeType || body?.fileType || body?.file_type,
      filename: body?.filename || body?.fileName || body?.file_name,
      type: body?.type,
      sessionId,
    });
  }

  @Post('link')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Link a WhatsApp session to ArslanHook' })
  async linkSessionBody(@Body() body: { sessionId?: string }, @Query('sessionId') querySessionId?: string) {
    const sessionId = body?.sessionId || querySessionId;
    return this.arslanHookService.linkSession(String(sessionId));
  }

  @Post('link/:sessionId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Link a WhatsApp session to ArslanHook by path param' })
  async linkSessionParam(@Param('sessionId') sessionId: string) {
    return this.arslanHookService.linkSession(sessionId);
  }

  @Get('events')
  @ApiOperation({ summary: 'Get recently received webhook events' })
  async getEvents(@Query('limit') limit?: string) {
    const parsedLimit = limit ? parseInt(limit, 10) : 50;
    return {
      total: this.arslanHookService.getEvents().length,
      events: this.arslanHookService.getEvents(parsedLimit),
    };
  }

  @Delete('events')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Clear received webhook events log' })
  async clearEvents() {
    this.arslanHookService.clearEvents();
    return { status: 'success', message: 'Events log cleared' };
  }
}
