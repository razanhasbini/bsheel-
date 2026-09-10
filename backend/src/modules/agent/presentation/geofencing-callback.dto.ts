import { IsUUID } from 'class-validator';

export class GeofencingCallbackParams {
  @IsUUID() subscriptionId!: string;
}
