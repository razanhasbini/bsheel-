import { Module } from '@nestjs/common';
import { NETWORK_EVIDENCE_PROVIDER } from '../../modules/agent/domain/agent.tokens.js';
import { CamaraAuthService } from './camara-auth.service.js';
import { CamaraClientFactory } from './camara-client.factory.js';
import { CamaraEvidenceAdapter } from './camara-evidence.adapter.js';
import { CamaraGeofencingAdapter } from './camara-geofencing.adapter.js';
import { CamaraOAuthMetadataService } from './camara-oauth-metadata.service.js';
import { CamaraNumberVerificationAdapter } from './number-verification.adapter.js';

@Module({
  providers: [
    CamaraAuthService,
    CamaraClientFactory,
    CamaraEvidenceAdapter,
    CamaraGeofencingAdapter,
    CamaraOAuthMetadataService,
    CamaraNumberVerificationAdapter,
    { provide: NETWORK_EVIDENCE_PROVIDER, useExisting: CamaraEvidenceAdapter },
  ],
  exports: [
    NETWORK_EVIDENCE_PROVIDER,
    CamaraClientFactory,
    CamaraEvidenceAdapter,
    CamaraGeofencingAdapter,
    CamaraOAuthMetadataService,
    CamaraNumberVerificationAdapter,
  ],
})
export class CamaraModule {}
