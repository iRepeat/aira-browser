import { webview } from '@kit.ArkWeb';
import {
  SecureDnsSelectionId,
  SecureDnsSettings,
  SecureDnsSettingsModel
} from '../../core/settings/SecureDnsSettingsModel';
import {
  SecureDnsDoHProbeCandidate,
  SecureDnsDoHProbeService
} from './SecureDnsDoHProbeService';

export interface SecureDnsOption {
  id: SecureDnsSelectionId;
  endpoint: string;
}

export interface SecureDnsApplyResult {
  applied: boolean;
  selectionId: SecureDnsSelectionId;
  activeSelectionId: SecureDnsSelectionId;
  endpoint: string;
  probeElapsedMs: number;
  strictMode: boolean;
  message: string;
}

export interface SecureDnsStartupResolution {
  configuredSelectionId: SecureDnsSelectionId;
  activeSettings: SecureDnsSettings;
  probeElapsedMs: number;
}

const SECURE_DNS_OPTIONS: SecureDnsOption[] = [
  { id: 'system', endpoint: '' },
  { id: 'auto', endpoint: '' },
  { id: 'alidns', endpoint: 'https://dns.alidns.com/dns-query' },
  { id: 'dnspod', endpoint: 'https://doh.pub/dns-query' },
  { id: 'cloudflare', endpoint: 'https://cloudflare-dns.com/dns-query' },
  { id: 'google', endpoint: 'https://dns.google/dns-query' }
];

export class SecureDnsService {
  private settingsModel: SecureDnsSettingsModel;
  private probeService: SecureDnsDoHProbeService;

  constructor(
    settingsModel: SecureDnsSettingsModel = new SecureDnsSettingsModel(),
    probeService: SecureDnsDoHProbeService = new SecureDnsDoHProbeService()
  ) {
    this.settingsModel = settingsModel;
    this.probeService = probeService;
  }

  getOptions(): SecureDnsOption[] {
    return SECURE_DNS_OPTIONS.map((option: SecureDnsOption): SecureDnsOption => {
      return {
        id: option.id,
        endpoint: option.endpoint
      };
    });
  }

  resolveEndpoint(settings: SecureDnsSettings): string {
    const normalized = this.settingsModel.normalize(settings);
    if (normalized.selectionId === 'system') {
      return '';
    }
    if (normalized.selectionId === 'custom') {
      return this.settingsModel.findProfile(
        normalized,
        normalized.activeCustomProfileId
      )?.endpoint ?? '';
    }
    const option = SECURE_DNS_OPTIONS.find((candidate: SecureDnsOption): boolean => {
      return candidate.id === normalized.selectionId;
    });
    return option?.endpoint ?? '';
  }

  async resolveStartupSettings(settings: SecureDnsSettings): Promise<SecureDnsStartupResolution> {
    const normalized = this.settingsModel.normalize(settings);
    if (normalized.selectionId !== 'auto') {
      return {
        configuredSelectionId: normalized.selectionId,
        activeSettings: normalized,
        probeElapsedMs: 0
      };
    }
    const probeResult = await this.probeService.selectFirstReachable(this.buildAutomaticProbeCandidates());
    if (probeResult === undefined) {
      // Strict mode promises "no system-DNS fallback", so a failed startup probe must not quietly
      // resolve in plaintext for the rest of the session. Keep the highest-priority candidate and
      // let SECURE_ONLY surface the failure instead; DoH recovers on its own once the network is back.
      const strictCandidate = normalized.strictMode === true ? this.buildAutomaticProbeCandidates()[0] : undefined;
      if (strictCandidate !== undefined) {
        return {
          configuredSelectionId: normalized.selectionId,
          activeSettings: {
            selectionId: this.normalizeSelectionId(strictCandidate.id),
            activeCustomProfileId: normalized.activeCustomProfileId,
            customProfiles: normalized.customProfiles,
            strictMode: true
          },
          probeElapsedMs: 0
        };
      }
      return {
        configuredSelectionId: normalized.selectionId,
        activeSettings: {
          selectionId: 'system',
          activeCustomProfileId: normalized.activeCustomProfileId,
          customProfiles: normalized.customProfiles,
          strictMode: normalized.strictMode
        },
        probeElapsedMs: 0
      };
    }
    return {
      configuredSelectionId: normalized.selectionId,
      activeSettings: {
        selectionId: this.normalizeSelectionId(probeResult.candidate.id),
        activeCustomProfileId: normalized.activeCustomProfileId,
        customProfiles: normalized.customProfiles,
        strictMode: normalized.strictMode
      },
      probeElapsedMs: probeResult.elapsedMs
    };
  }

  applyToArkWeb(
    settings: SecureDnsSettings,
    configuredSelectionId: SecureDnsSelectionId = settings.selectionId,
    probeElapsedMs: number = 0
  ): SecureDnsApplyResult {
    const normalized = this.settingsModel.normalize(settings);
    const endpoint = this.resolveEndpoint(normalized);
    try {
      if (normalized.selectionId === 'system' || endpoint.length === 0) {
        webview.WebviewController.setHttpDns(webview.SecureDnsMode.OFF, '');
        return {
          applied: true,
          selectionId: configuredSelectionId,
          activeSelectionId: 'system',
          endpoint: '',
          probeElapsedMs: probeElapsedMs,
          strictMode: false,
          message: configuredSelectionId === 'auto' ?
            'No reachable automatic Secure DNS candidate; using system DNS.' :
            'ArkWeb Secure DNS disabled; using system DNS.'
        };
      }
      // Strict mode skips the system-DNS fallback so a failing DoH server surfaces as a page load
      // failure instead of silently resolving in plaintext. ArkWeb keeps this global, so the
      // preference only takes effect through the existing restart path.
      const strictMode = normalized.strictMode === true;
      webview.WebviewController.setHttpDns(
        strictMode ? webview.SecureDnsMode.SECURE_ONLY : webview.SecureDnsMode.AUTO,
        endpoint
      );
      return {
        applied: true,
        selectionId: configuredSelectionId,
        activeSelectionId: normalized.selectionId,
        endpoint: endpoint,
        probeElapsedMs: probeElapsedMs,
        strictMode: strictMode,
        message: strictMode ?
          'ArkWeb Secure DNS applied without system-DNS fallback.' :
          (configuredSelectionId === 'auto' ?
            'Automatic Secure DNS candidate applied with system-DNS fallback.' :
            'ArkWeb Secure DNS applied with automatic system-DNS fallback.')
      };
    } catch (_error) {
      return {
        applied: false,
        selectionId: configuredSelectionId,
        activeSelectionId: normalized.selectionId,
        endpoint: endpoint,
        probeElapsedMs: probeElapsedMs,
        strictMode: normalized.strictMode === true,
        message: 'ArkWeb Secure DNS configuration failed.'
      };
    }
  }

  private normalizeSelectionId(value: string): SecureDnsSelectionId {
    if (value === 'auto' || value === 'alidns' || value === 'dnspod' || value === 'cloudflare' ||
      value === 'google' || value === 'custom') {
      return value;
    }
    return 'system';
  }

  private buildAutomaticProbeCandidates(): SecureDnsDoHProbeCandidate[] {
    const candidates: SecureDnsDoHProbeCandidate[] = [];
    for (let index = 0; index < SECURE_DNS_OPTIONS.length; index += 1) {
      const option = SECURE_DNS_OPTIONS[index];
      if (option.endpoint.length > 0) {
        candidates.push({
          id: option.id,
          endpoint: option.endpoint
        });
      }
    }
    return candidates;
  }
}
