import { describe, expect, it } from '@ohos/hypium';
import { InstalledUserScriptState } from '../main/ets/features/userscripts/UserScriptMetadataModels';
import {
  UserScriptInjectionRequest,
  UserScriptInjectionService
} from '../main/ets/services/userscripts/UserScriptInjectionService';

const HEAD_COMPAT_MARKER: string = 'airaInstallDocumentHeadCompat';
const USER_SOURCE_MARKER: string = 'aira-head-compat-probe';

function buildProbe(runAt: 'document-start' | 'document-end'): InstalledUserScriptState {
  return {
    id: 'userscript-aira-head-compat-probe',
    name: 'Aira Head Compat Probe',
    namespace: 'aira.head-compat.test',
    version: '1.0.0',
    description: '',
    iconUrl: '',
    source: `document.head.appendChild(document.createElement('style')); // ${USER_SOURCE_MARKER}`,
    sourceUrl: '',
    updateUrl: '',
    downloadUrl: '',
    enabled: true,
    matches: ['https://example.invalid/*'],
    includes: [],
    excludeMatches: [],
    excludes: [],
    grants: ['none'],
    requireUrls: [],
    requireSources: [],
    resources: [],
    connectRules: [],
    noframes: false,
    runAt: runAt,
    installSource: 'paste',
    createdAt: 1,
    updatedAt: 1,
    lastCheckedAt: 0
  };
}

function buildRequest(runAt: 'document-start' | 'document-end'): UserScriptInjectionRequest {
  return {
    script: buildProbe(runAt),
    valueSnapshotLiteral: '{}',
    valueRevision: 0,
    bridgeToken: 'head-compat-token'
  };
}

export default function userScriptDocumentStartHeadCompatTest(): void {
  describe('UserScript document-start head compat', () => {
    it('installs a detached head shim only before document-start user scripts', 0, () => {
      const service = new UserScriptInjectionService();
      const request = buildRequest('document-start');
      const documentStart = service.buildDocumentStartScript([request], ['blocked.invalid']);
      const compatAt = documentStart.indexOf(HEAD_COMPAT_MARKER);
      const userAt = documentStart.indexOf(USER_SOURCE_MARKER);
      const guardAt = documentStart.indexOf('__airaDocumentStartDisabledHosts');

      expect(compatAt).assertLarger(guardAt);
      expect(userAt).assertLarger(compatAt);
      expect(documentStart.includes('__airaDocumentHeadCompatV1')).assertTrue();
      expect(documentStart.includes('insertBefore')).assertFalse();
      expect(documentStart.includes("createElement('head')")).assertTrue();
      expect(service.buildDocumentStartScript([], ['blocked.invalid']).includes(HEAD_COMPAT_MARKER)).assertFalse();
      expect(service.buildDocumentStartApiScript([request], []).includes(HEAD_COMPAT_MARKER)).assertFalse();
      expect(service.buildDocumentEndScript([buildRequest('document-end')]).includes(HEAD_COMPAT_MARKER)).assertFalse();
      expect(service.buildRuntimeFactoryInstallScript().includes(HEAD_COMPAT_MARKER)).assertFalse();
    });
  });
}
