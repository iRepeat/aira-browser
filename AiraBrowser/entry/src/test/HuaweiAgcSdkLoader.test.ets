import { describe, expect, it } from '@ohos/hypium';
import {
  HuaweiAgcSdkHandle,
  HuaweiAgcSdkLoader,
  HuaweiAgcSdkUnavailableError,
  isHuaweiAgcSdkUnavailableError
} from '../main/ets/platform/huawei/HuaweiAgcSdkLoader';

// A package that ships without the Official AGConnect SDK cannot resolve the module record. That used
// to be a static import, so it killed the app during module load with an uncatchable
// "cannot find record '&@hw-agconnect/api-ohos/index&1.1.2'". These tests pin the replacement
// behaviour: the failure is a catchable rejection raised on first use, never at load.
export default function huaweiAgcSdkLoaderTest(): void {
  describe('HuaweiAgcSdkLoader degradation', () => {
    it('rejects with an unavailable error when the SDK module is missing', 0, async () => {
      const loader = new HuaweiAgcSdkLoader((): Promise<HuaweiAgcSdkHandle> => {
        return Promise.reject(new Error("cannot find record '&@hw-agconnect/api-ohos/index&1.1.2'"));
      });
      let caught: Error | undefined;
      try {
        await loader.load();
      } catch (error) {
        caught = error as Error;
      }
      expect(caught !== undefined).assertTrue();
      expect(isHuaweiAgcSdkUnavailableError(caught as Error)).assertTrue();
      expect((caught as HuaweiAgcSdkUnavailableError).reason).assertEqual('module_missing');
    });

    it('maps a non-Error rejection to the same unavailable error', 0, async () => {
      const loader = new HuaweiAgcSdkLoader((): Promise<HuaweiAgcSdkHandle> => {
        return Promise.reject('boom');
      });
      let caught: Error | undefined;
      try {
        await loader.load();
      } catch (error) {
        caught = error as Error;
      }
      expect(isHuaweiAgcSdkUnavailableError(caught as Error)).assertTrue();
    });

    it('resolves the handle once and reuses it on later calls', 0, async () => {
      let importCount = 0;
      const handle: HuaweiAgcSdkHandle = {
        auth: {
          init(): void {
          },
          signIn(): Promise<never> {
            return Promise.reject(new Error('unused'));
          },
          signOut(): Promise<void> {
            return Promise.resolve();
          },
          getCurrentUser(): Promise<never> {
            return Promise.reject(new Error('unused'));
          }
        },
        agconnect: {
          instance(): never {
            throw new Error('unused');
          }
        }
      };
      const loader = new HuaweiAgcSdkLoader((): Promise<HuaweiAgcSdkHandle> => {
        importCount += 1;
        return Promise.resolve(handle);
      });
      expect(loader.peek() === undefined).assertTrue();
      const first = await loader.load();
      const second = await loader.load();
      expect(importCount).assertEqual(1);
      expect(first === handle).assertTrue();
      expect(second === handle).assertTrue();
      expect(loader.peek() === handle).assertTrue();
    });

    it('does not cache a failed attempt, so a later call can recover', 0, async () => {
      let importCount = 0;
      const handle: HuaweiAgcSdkHandle = {
        auth: {
          init(): void {
          },
          signIn(): Promise<never> {
            return Promise.reject(new Error('unused'));
          },
          signOut(): Promise<void> {
            return Promise.resolve();
          },
          getCurrentUser(): Promise<never> {
            return Promise.reject(new Error('unused'));
          }
        },
        agconnect: {
          instance(): never {
            throw new Error('unused');
          }
        }
      };
      const loader = new HuaweiAgcSdkLoader((): Promise<HuaweiAgcSdkHandle> => {
        importCount += 1;
        return importCount === 1 ? Promise.reject(new Error('missing')) : Promise.resolve(handle);
      });
      let firstFailed = false;
      try {
        await loader.load();
      } catch (_error) {
        firstFailed = true;
      }
      expect(firstFailed).assertTrue();
      const recovered = await loader.load();
      expect(importCount).assertEqual(2);
      expect(recovered === handle).assertTrue();
    });

    it('is usable before any load attempt', 0, () => {
      const loader = new HuaweiAgcSdkLoader((): Promise<HuaweiAgcSdkHandle> => {
        return Promise.reject(new Error('unused'));
      });
      expect(loader.peek() === undefined).assertTrue();
      expect(isHuaweiAgcSdkUnavailableError(new Error('other'))).assertFalse();
    });
  });
}
