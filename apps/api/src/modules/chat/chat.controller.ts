import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  ParseIntPipe,
  DefaultValuePipe,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ChatService } from './chat.service';
import {
  CreateConversationDto,
  SendMessageDto,
  ConversationResponseDto,
  MessageResponseDto,
  SendMessageResponseDto,
} from './dto/chat.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/chat')
@Throttle({ default: { limit: 60, ttl: 60000 } }) // 60 requests per minute for chat
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Post('conversations')
  async createConversation(
    @CurrentUser('sub') userId: string,
    @Body() dto?: CreateConversationDto,
  ): Promise<ConversationResponseDto> {
    return this.chatService.createConversation(userId, dto);
  }

  @Get('conversations')
  async getConversations(
    @CurrentUser('sub') userId: string,
  ): Promise<ConversationResponseDto[]> {
    return this.chatService.getConversations(userId);
  }

  @Get('conversations/:id/messages')
  async getMessages(
    @CurrentUser('sub') userId: string,
    @Param('id') conversationId: string,
    @Query('limit', new DefaultValuePipe(50), ParseIntPipe) limit: number,
  ): Promise<MessageResponseDto[]> {
    return this.chatService.getMessages(userId, conversationId, limit);
  }

  @Post('conversations/:id/messages')
  async sendMessage(
    @CurrentUser('sub') userId: string,
    @Param('id') conversationId: string,
    @Body() dto: SendMessageDto,
  ): Promise<SendMessageResponseDto> {
    return this.chatService.sendMessage(userId, conversationId, dto);
  }
}
