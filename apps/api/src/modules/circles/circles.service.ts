import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateCircleDto,
  JoinCircleDto,
  CircleCheckInDto,
  CircleResponseDto,
  CircleListItemDto,
  CircleDetailDto,
  CirclePostDto,
  JoinCircleResponseDto,
} from './dto/circles.dto';
import { randomBytes } from 'crypto';

@Injectable()
export class CirclesService {
  constructor(private readonly prisma: PrismaService) {}

  private generateInviteCode(): string {
    // Generate 12-character base32 uppercase invite code
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const bytes = randomBytes(12);
    let code = '';
    for (let i = 0; i < 12; i++) {
      code += chars[bytes[i] % chars.length];
    }
    return code;
  }

  async createCircle(
    userId: string,
    dto: CreateCircleDto,
  ): Promise<CircleResponseDto> {
    // Generate unique invite code
    let inviteCode: string;
    let isUnique = false;
    while (!isUnique) {
      inviteCode = this.generateInviteCode();
      const existing = await this.prisma.circle.findUnique({
        where: { inviteCode },
      });
      if (!existing) isUnique = true;
    }

    const circle = await this.prisma.circle.create({
      data: {
        ownerUserId: userId,
        name: dto.name,
        description: dto.description || null,
        maxMembers: dto.maxMembers || 8,
        inviteCode: inviteCode!,
        isPrivate: true,
        members: {
          create: {
            userId,
            role: 'owner',
            status: 'active',
          },
        },
      },
      include: {
        _count: {
          select: { members: true },
        },
      },
    });

    // Check for circle_creator badge
    await this.checkCircleCreatorBadge(userId);

    return {
      id: circle.id,
      name: circle.name,
      description: circle.description,
      isPrivate: circle.isPrivate,
      inviteCode: circle.inviteCode,
      maxMembers: circle.maxMembers,
      memberCount: circle._count.members,
      role: 'owner',
      createdAt: circle.createdAt,
    };
  }

  async joinCircle(
    userId: string,
    dto: JoinCircleDto,
  ): Promise<JoinCircleResponseDto> {
    const circle = await this.prisma.circle.findUnique({
      where: { inviteCode: dto.inviteCode },
      include: {
        _count: {
          select: { members: true },
        },
        members: {
          where: { userId },
        },
      },
    });

    if (!circle) {
      throw new NotFoundException({
        code: 'INVITE_CODE_INVALID',
        message: 'Invalid invite code',
      });
    }

    // Check if already a member
    if (circle.members.length > 0) {
      throw new ConflictException({
        code: 'ALREADY_MEMBER',
        message: 'You are already a member of this circle',
      });
    }

    // Check if circle is full
    if (circle._count.members >= circle.maxMembers) {
      throw new ConflictException({
        code: 'CIRCLE_FULL',
        message: 'This circle has reached its maximum member limit',
      });
    }

    // Add member
    await this.prisma.circleMember.create({
      data: {
        circleId: circle.id,
        userId,
        role: 'member',
        status: 'active',
      },
    });

    return {
      circleId: circle.id,
      role: 'member',
    };
  }

  async getCircles(userId: string): Promise<CircleListItemDto[]> {
    const memberships = await this.prisma.circleMember.findMany({
      where: { userId, status: 'active' },
      include: {
        circle: {
          include: {
            _count: {
              select: { members: true },
            },
          },
        },
      },
      orderBy: {
        joinedAt: 'desc',
      },
    });

    return memberships.map((m) => ({
      id: m.circle.id,
      name: m.circle.name,
      memberCount: m.circle._count.members,
      role: m.role,
    }));
  }

  async getCircleDetail(
    userId: string,
    circleId: string,
  ): Promise<CircleDetailDto> {
    // Check membership
    const membership = await this.prisma.circleMember.findUnique({
      where: {
        circleId_userId: { circleId, userId },
      },
    });

    if (!membership || membership.status !== 'active') {
      throw new ForbiddenException({
        code: 'NOT_A_MEMBER',
        message: 'You are not a member of this circle',
      });
    }

    const circle = await this.prisma.circle.findUnique({
      where: { id: circleId },
      include: {
        members: {
          where: { status: 'active' },
          include: {
            user: {
              select: {
                id: true,
                handle: true,
                displayName: true,
              },
            },
          },
          orderBy: {
            joinedAt: 'asc',
          },
        },
      },
    });

    if (!circle) {
      throw new NotFoundException('Circle not found');
    }

    return {
      id: circle.id,
      name: circle.name,
      description: circle.description,
      isPrivate: circle.isPrivate,
      inviteCode: circle.inviteCode,
      maxMembers: circle.maxMembers,
      members: circle.members.map((m) => ({
        userId: m.user.id,
        handle: m.user.handle,
        displayName: m.user.displayName,
        role: m.role,
        joinedAt: m.joinedAt,
      })),
      createdAt: circle.createdAt,
    };
  }

  async getCircleFeed(
    userId: string,
    circleId: string,
    from?: string,
    to?: string,
  ): Promise<CirclePostDto[]> {
    // Check membership
    const membership = await this.prisma.circleMember.findUnique({
      where: {
        circleId_userId: { circleId, userId },
      },
    });

    if (!membership || membership.status !== 'active') {
      throw new ForbiddenException({
        code: 'NOT_A_MEMBER',
        message: 'You are not a member of this circle',
      });
    }

    // Build date filter
    const dateFilter: any = {};
    if (from) dateFilter.gte = from;
    if (to) dateFilter.lte = to;

    const posts = await this.prisma.circlePost.findMany({
      where: {
        circleId,
        ...(Object.keys(dateFilter).length > 0
          ? { localDate: dateFilter }
          : {}),
      },
      include: {
        user: {
          select: {
            handle: true,
            displayName: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 50,
    });

    return posts.map((p) => ({
      id: p.id,
      kind: p.kind,
      user: {
        handle: p.user.handle,
        displayName: p.user.displayName,
      },
      moodEmoji: p.moodEmoji,
      bodyText: p.bodyText,
      localDate: p.localDate,
      createdAt: p.createdAt,
    }));
  }

  async postCheckIn(
    userId: string,
    circleId: string,
    dto: CircleCheckInDto,
  ): Promise<CirclePostDto> {
    // Check membership
    const membership = await this.prisma.circleMember.findUnique({
      where: {
        circleId_userId: { circleId, userId },
      },
    });

    if (!membership || membership.status !== 'active') {
      throw new ForbiddenException({
        code: 'NOT_A_MEMBER',
        message: 'You are not a member of this circle',
      });
    }

    // Upsert check-in (one per user per circle per day)
    const post = await this.prisma.circlePost.upsert({
      where: {
        circleId_userId_localDate_kind: {
          circleId,
          userId,
          localDate: dto.localDate,
          kind: 'checkin',
        },
      },
      create: {
        circleId,
        userId,
        kind: 'checkin',
        moodEmoji: dto.moodEmoji || null,
        bodyText: dto.bodyText || null,
        localDate: dto.localDate,
      },
      update: {
        moodEmoji: dto.moodEmoji || null,
        bodyText: dto.bodyText || null,
      },
      include: {
        user: {
          select: {
            handle: true,
            displayName: true,
          },
        },
      },
    });

    return {
      id: post.id,
      kind: post.kind,
      user: {
        handle: post.user.handle,
        displayName: post.user.displayName,
      },
      moodEmoji: post.moodEmoji,
      bodyText: post.bodyText,
      localDate: post.localDate,
      createdAt: post.createdAt,
    };
  }

  private async checkCircleCreatorBadge(userId: string): Promise<void> {
    const circleCount = await this.prisma.circle.count({
      where: { ownerUserId: userId },
    });

    if (circleCount === 1) {
      const badge = await this.prisma.badge.findUnique({
        where: { code: 'circle_creator' },
      });

      if (badge) {
        await this.prisma.userBadge
          .create({
            data: { userId, badgeId: badge.id },
          })
          .catch(() => {
            // Badge already exists, ignore
          });
      }
    }
  }
}
