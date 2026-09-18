import { Module, forwardRef } from '@nestjs/common';
import { ArslanHookController } from './arslanhook.controller';
import { ArslanHookService } from './arslanhook.service';
import { SessionModule } from '../session/session.module';
import { MessageModule } from '../message/message.module';
import { WebhookModule } from '../webhook/webhook.module';

@Module({
  imports: [
    forwardRef(() => SessionModule),
    forwardRef(() => MessageModule),
    forwardRef(() => WebhookModule),
  ],
  controllers: [ArslanHookController],
  providers: [ArslanHookService],
  exports: [ArslanHookService],
})
export class ArslanHookModule {}
