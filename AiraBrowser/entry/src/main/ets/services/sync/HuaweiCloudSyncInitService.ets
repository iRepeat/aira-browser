import { common } from '@kit.AbilityKit';
import buffer from '@ohos.buffer';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  HuaweiAgcSdkHandle,
  sharedHuaweiAgcSdkLoader
} from '../../platform/huawei/HuaweiAgcSdkLoader';

export interface HuaweiCloudSyncInitAdapter {
  initializeAuth(context: common.Context): Promise<void>;
}

class AgcHuaweiCloudSyncInitAdapter implements HuaweiCloudSyncInitAdapter {
  async initializeAuth(context: common.Context): Promise<void> {
    // Resolved lazily so a package without the Official SDK fails this call, not module load.
    const sdk: HuaweiAgcSdkHandle = await sharedHuaweiAgcSdkLoader.load();
    const rawFile = context.resourceManager.getRawFileContentSync('agconnect-services.json');
    const json = buffer.from(rawFile.buffer).toString('utf8');
    const config: Object = JSON.parse(json);
    sdk.auth.init(context, json);
    sdk.agconnect.instance().init(context, config);
  }
}

export class HuaweiCloudSyncInitService {
  private adapter: HuaweiCloudSyncInitAdapter;
  private authInitialized: boolean = false;
  private authInitializationTask?: Promise<void>;

  constructor(adapter?: HuaweiCloudSyncInitAdapter) {
    this.adapter = adapter ?? new AgcHuaweiCloudSyncInitAdapter();
  }

  async initializeAuth(context: common.Context): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    if (this.authInitialized) {
      return;
    }
    if (this.authInitializationTask === undefined) {
      this.authInitializationTask = this.adapter.initializeAuth(context)
        .then((): void => {
          this.authInitialized = true;
        })
        .catch((error: Error): Promise<void> => {
          this.authInitializationTask = undefined;
          return Promise.reject(error);
        });
    }
    await this.authInitializationTask;
  }
}
