import { describe, expect, it } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import { UserScriptExternalImportService } from
  '../main/ets/services/userscripts/UserScriptExternalImportService';

const WECHAT_SCRIPT_URI: string =
  'file://com.tencent.wechat/data/storage/el2/base/cache/shared/alita/message/temp_file/' +
  '9e20f478899dc29eb19741386f9343c8_491120070661994135_m/' +
  '%E7%BD%91%E9%A1%B5%E8%B0%83%E8%AF%95-%E7%A6%BB%E7%BA%BF%E5%AE%89%E8%A3%85.user.js';

export default function userScriptExternalImportServiceTest(): void {
  describe('UserScript external file open', () => {
    it('installs a WeChat file URI even when the open-with sheet omits viewData', 0, () => {
      const service = new UserScriptExternalImportService();
      const want: Want = {
        uri: WECHAT_SCRIPT_URI,
        type: 'text/plain'
      };

      expect(service.isCandidate(want)).assertTrue();
      expect(service.resolveSourceUri(want)).assertEqual(WECHAT_SCRIPT_URI);
    });

    it('keeps the documented viewData file open on the install path', 0, () => {
      const service = new UserScriptExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: WECHAT_SCRIPT_URI,
        type: 'general.java-script'
      };

      expect(service.isCandidate(want)).assertTrue();
      expect(service.resolveSourceUri(want)).assertEqual(WECHAT_SCRIPT_URI);
    });

    it('reads a script URI from the file-open stream when want.uri is empty', 0, () => {
      const service = new UserScriptExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        parameters: {
          'ability.params.stream': [WECHAT_SCRIPT_URI]
        } as Record<string, Object>
      };

      expect(service.isCandidate(want)).assertTrue();
      expect(service.resolveSourceUri(want)).assertEqual(WECHAT_SCRIPT_URI);
    });

    it('does not treat an ordinary page or a shared web link as a script file', 0, () => {
      const service = new UserScriptExternalImportService();
      const page: Want = {
        action: 'ohos.want.action.viewData',
        uri: 'https://example.com/'
      };
      const sharedLink: Want = {
        action: 'ohos.want.action.sendData',
        uri: 'https://greasyfork.org/scripts/475228.user.js'
      };
      const htmlFile: Want = {
        uri: 'file://com.tencent.wechat/data/storage/el2/base/cache/shared/page.html'
      };

      expect(service.isCandidate(page)).assertFalse();
      expect(service.isCandidate(sharedLink)).assertFalse();
      expect(service.isCandidate(htmlFile)).assertFalse();
    });

    it('does not steal a page open that also carries a script file parameter', 0, () => {
      const service = new UserScriptExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: 'https://example.com/',
        parameters: {
          uri: WECHAT_SCRIPT_URI
        } as Record<string, Object>
      };

      expect(service.isCandidate(want)).assertFalse();
    });
  });
}
