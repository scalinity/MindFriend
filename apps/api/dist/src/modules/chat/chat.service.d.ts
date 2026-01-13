import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { CreateConversationDto, SendMessageDto, ConversationResponseDto, MessageResponseDto, SendMessageResponseDto } from './dto/chat.dto';
export declare class ChatService {
    private readonly prisma;
    private readonly configService;
    private readonly logger;
    private readonly openai;
    private readonly model;
    private readonly maxTokens;
    private readonly dailyFreeQuota;
    private readonly premiumQuota;
    constructor(prisma: PrismaService, configService: ConfigService);
    createConversation(userId: string, dto?: CreateConversationDto): Promise<ConversationResponseDto>;
    getConversations(userId: string): Promise<ConversationResponseDto[]>;
    getMessages(userId: string, conversationId: string, limit?: number): Promise<MessageResponseDto[]>;
    sendMessage(userId: string, conversationId: string, dto: SendMessageDto): Promise<SendMessageResponseDto>;
    private generateAIResponse;
    private moderateInput;
    private checkAndIncrementQuota;
    private checkFirstChatBadge;
    private formatMessage;
    private getLocalDate;
}
