import { Injectable, NotFoundException } from '@nestjs/common';
import type { MapPlaceDto, MapQueryDto, MapQuestLinkDto } from '../presentation/map.dto.js';
import { MapRepository } from '../infrastructure/map.repository.js';

@Injectable()
export class MapService {
  constructor(private readonly repository:MapRepository) {}
  countries(userId:string){return this.repository.countries(userId);}
  async profileCountries(viewerId:string,userId:string){
    if(!await this.repository.canViewProfile(viewerId,userId))throw new NotFoundException('Profile not found');
    const rows=await this.repository.countries(userId);
    return rows.map(row=>({...row,saved:viewerId===userId?row.saved:0}));
  }
  places(userId:string,query:MapQueryDto){return this.repository.places(userId,query);}
  detail(userId:string,id:string){return this.repository.detail(userId,id);}
  save(userId:string,id:string,value:boolean){return this.repository.save(userId,id,value);}
  adminPlaces(){return this.repository.adminPlaces();}
  create(actorId:string,input:MapPlaceDto){return this.repository.create(actorId,input);}
  link(actorId:string,id:string,input:MapQuestLinkDto){return this.repository.link(actorId,id,input);}
}
