import { ArgumentsHost, type ExceptionFilter } from '@nestjs/common';
export declare class ApiExceptionFilter implements ExceptionFilter {
    private readonly logger;
    catch(exception: unknown, host: ArgumentsHost): void;
    private resolveMessage;
    private resolveCode;
}
