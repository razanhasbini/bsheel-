import { Module } from '@nestjs/common';
import { SearchService } from './application/search.service.js';
import { SearchRepository } from './infrastructure/search.repository.js';
import { SearchController } from './presentation/search.controller.js';

@Module({ controllers: [SearchController], providers: [SearchService, SearchRepository] })
export class SearchModule {}
