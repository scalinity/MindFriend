import { ChatService } from './chat.service';
import { CreateConversationDto, SendMessageDto, ConversationResponseDto, MessageResponseDto, SendMessageResponseDto } from './dto/chat.dto';
export declare class ChatController {
    private readonly chatService;
    constructor(chatService: ChatService);
    createConversation(userId: string, dto?: CreateConversationDto): Promise<ConversationResponseDto>;
    getConversations(userId: string): Promise<ConversationResponseDto[]>;
    getMessages(userId: string, conversationId: string, limit: number): Promise<MessageResponseDto[]>;
    sendMessage(userId: string, conversationId: string, dto: SendMessageDto): Promise<SendMessageResponseDto>;
}
