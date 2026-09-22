import { http } from '@kit.NetworkKit';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';
import { AiraMembershipGrantResponseRecord } from './AiraMembershipStateFunctionService';

const AIRA_COMPLIMENTARY_CLAIM_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/membership/complimentary-claim';
const AIRA_COMPLIMENTARY_CLAIM_TIMEOUT_MS: number = 30000;
// Resolve the API hostname through a fixed-IP DoH endpoint so a device-side
// DNS hijack cannot send the request to an unrelated HTTPS host.
const AIRA_COMPLIMENTARY_CLAIM_DOH_ENDPOINT: string = 'https://223.5.5.5/dns-query';

export interface AiraComplimentaryClaimRequestBody {
  uid: string;
  source: string;
  authToken?: string;
}

export interface AiraComplimentaryClaimResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  uidSuffix?: string;
  membershipGrant?: AiraMembershipGrantResponseRecord | null;
  entitlementProof?: string | null;
}

export interface AiraComplimentaryClaimHttpAdapter {
  post(url: string, body: AiraComplimentaryClaimRequestBody, timeoutMs: number):
    Promise<Object | string | null | undefined>;
}

class NetworkAiraComplimentaryClaimHttpAdapter implements AiraComplimentaryClaimHttpAdapter {
  async post(
    url: string,
    body: AiraComplimentaryClaimRequestBody,
    timeoutMs: number
  ): Promise<Object | string | null | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        dnsOverHttps: AIRA_COMPLIMENTARY_CLAIM_DOH_ENDPOINT,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const errorResponse: AiraComplimentaryClaimResponseBody = {
          ok: false,
          code: 'http_error',
          message: `Aira 会员领取服务请求失败（${response.responseCode}）。`
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraComplimentaryClaimFunctionService {
  private adapter: AiraComplimentaryClaimHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: AiraComplimentaryClaimHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkAiraComplimentaryClaimHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  /**
   * Asks the hosted service to grant 15 days of Pro. The service decides
   * whether this account may claim; the client only sends the signed-in
   * identity and applies the grant that comes back.
   */
  async claim(uid: string): Promise<AiraComplimentaryClaimResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return {
        ok: false,
        code: 'distribution_unavailable',
        message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      };
    }
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: '请先使用华为账号登录。'
      };
    }
    const body: AiraComplimentaryClaimRequestBody = {
      uid: normalizedUid,
      source: 'app'
    };
    try {
      const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, false);
      if (token.length > 0) {
        body.authToken = token;
      }
    } catch (_error) {
      body.authToken = undefined;
    }
    const value = await this.adapter.post(
      AIRA_COMPLIMENTARY_CLAIM_ENDPOINT,
      body,
      AIRA_COMPLIMENTARY_CLAIM_TIMEOUT_MS
    );
    return this.parseFunctionValue(value);
  }

  private parseFunctionValue(value: Object | string | null | undefined): AiraComplimentaryClaimResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira 会员领取服务没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira 会员领取服务返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseFunctionObject(value);
  }

  private parseFunctionObject(value: Object): AiraComplimentaryClaimResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | Object[] | undefined | null>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraComplimentaryClaimResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: 'Aira 会员领取服务返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraComplimentaryClaimResponseBody;
    }
    return raw as AiraComplimentaryClaimResponseBody;
  }
}
