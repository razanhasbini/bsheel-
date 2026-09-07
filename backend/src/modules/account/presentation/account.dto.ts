import { Equals } from 'class-validator';

export class RequestDeletionDto {
  @Equals('DELETE') confirmation!: 'DELETE';
}
