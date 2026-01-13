import { Module } from '@nestjs/common';
import { MoodsService } from './moods.service';
import { MoodsController } from './moods.controller';

@Module({
  controllers: [MoodsController],
  providers: [MoodsService],
  exports: [MoodsService],
})
export class MoodsModule {}
