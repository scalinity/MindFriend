"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var ChatService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const openai_1 = __importDefault(require("openai"));
const prisma_service_1 = require("../prisma/prisma.service");
const CRISIS_KEYWORDS = [
    'kill myself',
    'want to die',
    'end my life',
    'suicide',
    'self-harm',
    'hurt myself',
    'cutting myself',
    'overdose',
    'jump off',
    'hang myself',
];
const CRISIS_RESPONSE = `I'm really sorry you're feeling this way. I can't help with anything that could harm you, but you deserve support right now. If you're in immediate danger, please call your local emergency number.

You can also access Crisis Resources in the app (tap the heart icon) for local helplines. You matter, and help is available.`;
const SYSTEM_PROMPT_BASE = `You are MindFriend, a warm and supportive AI wellness companion. Your role is to:
- Provide emotional support and encouragement
- Help users reflect on their feelings and experiences
- Suggest healthy coping strategies and mindfulness techniques
- Celebrate their progress and small wins
- Be empathetic, non-judgmental, and positive

Important guidelines:
- Never provide medical, legal, or financial advice
- If someone expresses thoughts of self-harm or suicide, always encourage them to seek professional help and mention the Crisis Resources feature
- Keep responses concise (2-4 sentences typically)
- Use a conversational, friendly tone
- Ask thoughtful follow-up questions to encourage reflection`;
const TONE_MODIFIERS = {
    friendly: 'Be warm, casual, and use occasional light humor when appropriate.',
    professional: 'Be supportive but maintain a calm, measured professional tone.',
    motivational: 'Be enthusiastic, encouraging, and use empowering language.',
    gentle: 'Be extra soft, patient, and nurturing in your responses.',
};
let ChatService = ChatService_1 = class ChatService {
    prisma;
    configService;
    logger = new common_1.Logger(ChatService_1.name);
    openai;
    model;
    maxTokens;
    dailyFreeQuota;
    premiumQuota;
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.openai = new openai_1.default({
            apiKey: this.configService.get('OPENAI_API_KEY'),
        });
        this.model = this.configService.get('OPENAI_MODEL', 'gpt-4o-mini');
        this.maxTokens = parseInt(this.configService.get('OPENAI_MAX_TOKENS', '500'), 10);
        this.dailyFreeQuota = parseInt(this.configService.get('AI_DAILY_FREE_QUOTA', '20'), 10);
        this.premiumQuota = 9999;
    }
    async createConversation(userId, dto) {
        const conversation = await this.prisma.conversation.create({
            data: {
                userId,
                title: dto?.title || null,
            },
        });
        await this.checkFirstChatBadge(userId);
        return {
            id: conversation.id,
            title: conversation.title,
            status: conversation.status,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
        };
    }
    async getConversations(userId) {
        const conversations = await this.prisma.conversation.findMany({
            where: { userId },
            orderBy: { updatedAt: 'desc' },
            include: {
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                },
            },
        });
        return conversations.map((c) => ({
            id: c.id,
            title: c.title,
            status: c.status,
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
            lastMessage: c.messages[0]
                ? {
                    role: c.messages[0].role,
                    content: c.messages[0].content.substring(0, 100),
                    createdAt: c.messages[0].createdAt,
                }
                : undefined,
        }));
    }
    async getMessages(userId, conversationId, limit = 50) {
        const conversation = await this.prisma.conversation.findFirst({
            where: { id: conversationId, userId },
        });
        if (!conversation) {
            throw new common_1.NotFoundException('Conversation not found');
        }
        const messages = await this.prisma.message.findMany({
            where: { conversationId },
            orderBy: { createdAt: 'asc' },
            take: limit,
        });
        return messages.map((m) => ({
            id: m.id,
            role: m.role,
            content: m.content,
            createdAt: m.createdAt,
            blocked: m.blocked,
        }));
    }
    async sendMessage(userId, conversationId, dto) {
        const conversation = await this.prisma.conversation.findFirst({
            where: { id: conversationId, userId },
        });
        if (!conversation) {
            throw new common_1.NotFoundException('Conversation not found');
        }
        const quotaCheck = await this.checkAndIncrementQuota(userId);
        if (!quotaCheck.allowed) {
            throw new common_1.ForbiddenException({
                message: 'Daily AI quota exceeded',
                code: 'AI_QUOTA_EXCEEDED',
                upgradeUrl: 'app://paywall',
            });
        }
        const inputModeration = this.moderateInput(dto.content);
        const userMessage = await this.prisma.message.create({
            data: {
                conversationId,
                userId,
                role: 'user',
                content: dto.content,
                moderationLabel: inputModeration.label,
                blocked: false,
            },
        });
        if (inputModeration.isCrisis) {
            await this.prisma.crisisEvent.create({
                data: {
                    userId,
                    severity: 'high',
                    source: 'ai_input',
                    messageId: userMessage.id,
                    actionTaken: 'show_resources',
                },
            });
            const crisisMessage = await this.prisma.message.create({
                data: {
                    conversationId,
                    userId,
                    role: 'assistant',
                    content: CRISIS_RESPONSE,
                    moderationLabel: 'ok',
                    blocked: false,
                },
            });
            return {
                userMessage: this.formatMessage(userMessage),
                assistantMessage: this.formatMessage(crisisMessage),
                quotaRemaining: quotaCheck.remaining,
                crisisDetected: true,
            };
        }
        const userSettings = await this.prisma.userSettings.findUnique({
            where: { userId },
        });
        const aiTone = userSettings?.aiTone || 'friendly';
        const history = await this.prisma.message.findMany({
            where: { conversationId },
            orderBy: { createdAt: 'asc' },
            take: 10,
        });
        const aiResponse = await this.generateAIResponse(dto.content, history, aiTone);
        const assistantMessage = await this.prisma.message.create({
            data: {
                conversationId,
                userId,
                role: 'assistant',
                content: aiResponse.content,
                tokenIn: aiResponse.tokensIn,
                tokenOut: aiResponse.tokensOut,
                moderationLabel: 'ok',
                blocked: false,
            },
        });
        await this.prisma.conversation.update({
            where: { id: conversationId },
            data: { updatedAt: new Date() },
        });
        return {
            userMessage: this.formatMessage(userMessage),
            assistantMessage: this.formatMessage(assistantMessage),
            quotaRemaining: quotaCheck.remaining,
        };
    }
    async generateAIResponse(userMessage, history, aiTone) {
        const systemPrompt = `${SYSTEM_PROMPT_BASE}\n\n${TONE_MODIFIERS[aiTone] || TONE_MODIFIERS.friendly}`;
        const messages = [
            { role: 'system', content: systemPrompt },
            ...history.slice(-8).map((m) => ({
                role: m.role,
                content: m.content,
            })),
            { role: 'user', content: userMessage },
        ];
        try {
            const completion = await this.openai.chat.completions.create({
                model: this.model,
                messages,
                max_tokens: this.maxTokens,
                temperature: 0.7,
            });
            return {
                content: completion.choices[0]?.message?.content ||
                    "I'm here for you. How can I support you today?",
                tokensIn: completion.usage?.prompt_tokens || 0,
                tokensOut: completion.usage?.completion_tokens || 0,
            };
        }
        catch (error) {
            this.logger.error('OpenAI API error', error);
            return {
                content: "I'm having a moment. Could you try again? I'm here to listen.",
                tokensIn: 0,
                tokensOut: 0,
            };
        }
    }
    moderateInput(content) {
        const lowerContent = content.toLowerCase();
        for (const keyword of CRISIS_KEYWORDS) {
            if (lowerContent.includes(keyword)) {
                return { isCrisis: true, label: 'self_harm' };
            }
        }
        return { isCrisis: false, label: 'ok' };
    }
    async checkAndIncrementQuota(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: {
                subscriptions: {
                    where: { status: { in: ['active', 'grace'] } },
                    take: 1,
                },
            },
        });
        const isPremium = user?.subscriptions && user.subscriptions.length > 0;
        const dailyQuota = isPremium ? this.premiumQuota : this.dailyFreeQuota;
        const timezone = user?.timezone || 'UTC';
        const localDate = this.getLocalDate(timezone);
        const usage = await this.prisma.dailyAiUsage.upsert({
            where: {
                userId_localDate: { userId, localDate },
            },
            create: {
                userId,
                localDate,
                messageCount: 1,
            },
            update: {
                messageCount: { increment: 1 },
            },
        });
        if (usage.messageCount > dailyQuota) {
            await this.prisma.dailyAiUsage.update({
                where: { id: usage.id },
                data: { messageCount: { decrement: 1 } },
            });
            return { allowed: false, remaining: 0 };
        }
        return { allowed: true, remaining: dailyQuota - usage.messageCount };
    }
    async checkFirstChatBadge(userId) {
        const conversationCount = await this.prisma.conversation.count({
            where: { userId },
        });
        if (conversationCount === 1) {
            const badge = await this.prisma.badge.findUnique({
                where: { code: 'first_chat' },
            });
            if (badge) {
                await this.prisma.userBadge
                    .create({
                    data: { userId, badgeId: badge.id },
                })
                    .catch(() => {
                });
            }
        }
    }
    formatMessage(message) {
        return {
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            blocked: message.blocked,
        };
    }
    getLocalDate(timezone) {
        const now = new Date();
        const formatter = new Intl.DateTimeFormat('en-CA', {
            timeZone: timezone,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        });
        return formatter.format(now);
    }
};
exports.ChatService = ChatService;
exports.ChatService = ChatService = ChatService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], ChatService);
//# sourceMappingURL=chat.service.js.map