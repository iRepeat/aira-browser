import { BrowserWebLoadDataPayload } from '../browser/BrowserWebLoadCoordinator';
import { OfflinePageOpenCoordinator } from './OfflinePageOpenCoordinator';
import { parseSavedPageWebTabUrl } from './SavedPageWebTabUrl';

export interface SavedPageWebTabLoadResult {
  payload?: BrowserWebLoadDataPayload;
  archiveUri: string;
}

/**
 * Resolves a desktop saved-page tab into the stored snapshot.
 * The tab itself stays a normal web tab so large-screen chrome is unchanged.
 */
export class SavedPageWebTabLoadCoordinator {
  private openCoordinator: OfflinePageOpenCoordinator;

  constructor(openCoordinator: OfflinePageOpenCoordinator) {
    this.openCoordinator = openCoordinator;
  }

  async resolve(url: string): Promise<SavedPageWebTabLoadResult> {
    const route = parseSavedPageWebTabUrl(url);
    if (route === undefined) {
      return { archiveUri: '' };
    }
    const result = await this.openCoordinator.open(route.pageId, route.dataScope, route.privacyMode);
    if (!result.ok || result.record === undefined) {
      return {
        archiveUri: '',
        payload: this.buildMessagePayload(url, result.message.length > 0 ? result.message : '离线页面打开失败')
      };
    }
    if (result.contentKind === 'web_archive' && result.html.trim().length === 0 && result.archiveUri.trim().length > 0) {
      return { archiveUri: result.archiveUri };
    }
    const originalUrl = result.record.originalUrl.trim();
    const documentUrl = originalUrl.length > 0 ? originalUrl : url;
    return {
      archiveUri: '',
      payload: {
        data: result.html,
        mimeType: 'text/html',
        encoding: 'UTF-8',
        baseUrl: documentUrl,
        historyUrl: documentUrl
      }
    };
  }

  private buildMessagePayload(url: string, message: string): BrowserWebLoadDataPayload {
    return {
      data: `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><p>${this.escapeHtml(message)}</p></body></html>`,
      mimeType: 'text/html',
      encoding: 'UTF-8',
      baseUrl: url,
      historyUrl: url
    };
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }
}
