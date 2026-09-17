import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const HUAWEI_AGC_SDK_DOMAIN: number = 0x0000;
const HUAWEI_AGC_SDK_TAG: string = 'HuaweiAgcSdk';

/**
 * The AGConnect SDK is an Official-only dependency, and it is not guaranteed to be linked into every
 * package. A static `import` of it is resolved when the module record loads, which is before any of
 * our code runs and cannot be caught: a package that ships without the SDK then dies at startup with
 * "cannot find record '&@hw-agconnect/api-ohos/index&1.1.2'", taking the whole browser down for a
 * feature the user may never touch.
 *
 * So the SDK is reached only through this loader's dynamic import. The module record is then resolved
 * on first use, and a missing SDK becomes a rejected promise the Huawei-account features can degrade
 * on instead of a load-time crash. The handles below are structural (no SDK types are imported, not
 * even type-only), so nothing in the startup graph carries a hard reference to the SDK.
 */

/** Raised when the AGConnect SDK is not part of the running package. Callers degrade, never crash. */
export class HuaweiAgcSdkUnavailableError extends Error {
  reason: string;

  constructor(reason: string) {
    super(`华为账号服务组件不可用（${reason}）。`);
    this.reason = reason;
  }
}

export function isHuaweiAgcSdkUnavailableError(error: Error): boolean {
  return error instanceof HuaweiAgcSdkUnavailableError;
}

export interface HuaweiAgcTokenHandle {
  getString(): string;
  getExpirePeriod(): number;
}

export interface HuaweiAgcAuthUserHandle {
  getUid(): string;
  getDisplayName(): string;
  getPhotoUrl(): string;
  getToken(forceRefresh: boolean): Promise<HuaweiAgcTokenHandle>;
}

export interface HuaweiAgcSignInResultHandle {
  getUser(): HuaweiAgcAuthUserHandle;
}

export interface HuaweiAgcCredentialInfo {
  kind: string;
}

export interface HuaweiAgcSignInParam {
  autoCreateUser: boolean;
  credentialInfo: HuaweiAgcCredentialInfo;
}

export interface HuaweiAgcAuthHandle {
  init(applicationContext: common.Context, json: string): void;
  signIn(signInParam: HuaweiAgcSignInParam): Promise<HuaweiAgcSignInResultHandle>;
  signOut(): Promise<void>;
  getCurrentUser(): Promise<HuaweiAgcAuthUserHandle | null>;
}

export interface HuaweiAgcInstanceHandle {
  init(applicationContext: common.Context, config?: Object): void;
}

export interface HuaweiAgcApiHandle {
  instance(): HuaweiAgcInstanceHandle;
}

export interface HuaweiAgcSdkHandle {
  auth: HuaweiAgcAuthHandle;
  agconnect: HuaweiAgcApiHandle;
}

interface HuaweiAgcApiModuleNamespace {
  default: HuaweiAgcApiHandle;
}

interface HuaweiAgcAuthModuleNamespace {
  default: HuaweiAgcAuthHandle;
}

/**
 * Overridable so a test can exercise the degradation path without a package that actually omits the
 * SDK: the default reads the real module registry and can only be validated on a device.
 */
export type HuaweiAgcSdkModuleImport = () => Promise<HuaweiAgcSdkHandle>;

export class HuaweiAgcSdkLoader {
  private importModules: HuaweiAgcSdkModuleImport;
  private loaded?: HuaweiAgcSdkHandle;
  private loadTask?: Promise<HuaweiAgcSdkHandle>;

  constructor(importModules?: HuaweiAgcSdkModuleImport) {
    this.importModules = importModules ?? ((): Promise<HuaweiAgcSdkHandle> => this.loadFromModuleRegistry());
  }

  /**
   * Resolves the SDK on first use. A missing SDK rejects with HuaweiAgcSdkUnavailableError; the
   * failed attempt is not cached, so a later call may still succeed if the module becomes available.
   */
  async load(): Promise<HuaweiAgcSdkHandle> {
    if (this.loaded !== undefined) {
      return this.loaded;
    }
    if (this.loadTask === undefined) {
      this.loadTask = this.importModules()
        .then((handle: HuaweiAgcSdkHandle): HuaweiAgcSdkHandle => {
          this.loaded = handle;
          return handle;
        })
        .catch((error: Error): HuaweiAgcSdkHandle => {
          this.loadTask = undefined;
          if (isHuaweiAgcSdkUnavailableError(error)) {
            throw error;
          }
          hilog.error(
            HUAWEI_AGC_SDK_DOMAIN,
            HUAWEI_AGC_SDK_TAG,
            'agconnect sdk could not be loaded error=%{public}s',
            JSON.stringify(error)
          );
          throw new HuaweiAgcSdkUnavailableError('module_missing');
        });
    }
    return this.loadTask;
  }

  /** Already-resolved handle, for callers that must not trigger a load (diagnostics, sync probes). */
  peek(): HuaweiAgcSdkHandle | undefined {
    return this.loaded;
  }

  private async loadFromModuleRegistry(): Promise<HuaweiAgcSdkHandle> {
    // Each import is read through an Object handle before the cast. Annotating the import expression
    // with our structural interface would make the compiler check it against the SDK's real
    // declarations, and the point of this loader is that no SDK type is referenced from our graph.
    const agconnectModule: Object = await import('@hw-agconnect/api-ohos');
    // core-ohos installs `agconnect.instance()` onto the api-ohos singleton as a load side effect,
    // so it has to be evaluated before any instance() call.
    await import('@hw-agconnect/core-ohos');
    const authModule: Object = await import('@hw-agconnect/auth');
    return {
      auth: (authModule as HuaweiAgcAuthModuleNamespace).default,
      agconnect: (agconnectModule as HuaweiAgcApiModuleNamespace).default
    };
  }
}

export const sharedHuaweiAgcSdkLoader: HuaweiAgcSdkLoader = new HuaweiAgcSdkLoader();
