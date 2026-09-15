import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';

export type BrowserQrScanStatus = 'success' | 'empty' | 'canceled' | 'failed';

export interface BrowserQrScanResult {
  status: BrowserQrScanStatus;
  value: string;
  message: string;
}

const SCAN_INTERNAL_ERROR_CODE: number = 1000500001;
const SCAN_USER_CANCEL_CODE: number = 1000500002;
const PHOTO_PICKER_USER_CANCEL_CODE: number = 13900004;

export class BrowserQrScanService {
  async scan(context: common.Context, preferAlbum: boolean = false): Promise<BrowserQrScanResult> {
    if (preferAlbum) {
      return await this.scanFromAlbum();
    }
    try {
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: true
      });
      return this.buildDecodedResult(result.originalValue);
    } catch (error) {
      const businessError = error as BusinessError;
      if (this.isUserCancel(businessError)) {
        return this.buildCanceledResult();
      }
      if (businessError.code === SCAN_INTERNAL_ERROR_CODE) {
        return await this.scanFromAlbum();
      }
      return this.buildFailureResult(this.resolveFailureMessage(businessError));
    }
  }

  private async scanFromAlbum(): Promise<BrowserQrScanResult> {
    try {
      const uri = await this.pickAlbumImageUri();
      if (uri === undefined) {
        return this.buildCanceledResult();
      }
      const results = await detectBarcode.decode({ uri: uri }, {
        scanTypes: [scanCore.ScanType.QR_CODE]
      });
      if (results.length <= 0) {
        return {
          status: 'empty',
          value: '',
          message: '没有识别到二维码内容。'
        };
      }
      return this.buildDecodedResult(results[0].originalValue);
    } catch (error) {
      const businessError = error as BusinessError;
      if (this.isUserCancel(businessError)) {
        return this.buildCanceledResult();
      }
      if (businessError.code === SCAN_INTERNAL_ERROR_CODE) {
        return this.buildFailureResult('无法识别这张图片中的二维码，请换一张再试。');
      }
      return this.buildFailureResult(this.resolveFailureMessage(businessError));
    }
  }

  private async pickAlbumImageUri(): Promise<string | undefined> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    return result.photoUris.length > 0 ? result.photoUris[0] : undefined;
  }

  private buildDecodedResult(value: string): BrowserQrScanResult {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return {
        status: 'empty',
        value: '',
        message: '没有识别到二维码内容。'
      };
    }
    return {
      status: 'success',
      value: normalized,
      message: ''
    };
  }

  private buildCanceledResult(): BrowserQrScanResult {
    return {
      status: 'canceled',
      value: '',
      message: ''
    };
  }

  private buildFailureResult(message: string): BrowserQrScanResult {
    return {
      status: 'failed',
      value: '',
      message: message
    };
  }

  private isUserCancel(error: BusinessError): boolean {
    if (error.code === SCAN_USER_CANCEL_CODE || error.code === PHOTO_PICKER_USER_CANCEL_CODE) {
      return true;
    }
    const message = error.message ?? '';
    return message.indexOf('cancel') >= 0 ||
      message.indexOf('Cancel') >= 0 ||
      message.indexOf('取消') >= 0;
  }

  private resolveFailureMessage(error: BusinessError): string {
    if (error.message !== undefined && error.message.length > 0) {
      return `扫码失败：${error.message}`;
    }
    return '扫码失败，请稍后重试。';
  }
}
