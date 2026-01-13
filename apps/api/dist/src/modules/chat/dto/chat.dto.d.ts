export declare class CreateConversationDto {
    title?: string;
}
export declare class SendMessageDto {
    content: string;
}
export declare class ConversationResponseDto {
    id: string;
    title: string | null;
    status: string;
    createdAt: Date;
    updatedAt: Date;
    lastMessage?: {
        role: string;
        content: string;
        createdAt: Date;
    };
}
export declare class MessageResponseDto {
    id: string;
    role: string;
    content: string;
    createdAt: Date;
    blocked: boolean;
}
export declare class SendMessageResponseDto {
    userMessage: MessageResponseDto;
    assistantMessage: MessageResponseDto;
    quotaRemaining: number;
    crisisDetected?: boolean;
}
