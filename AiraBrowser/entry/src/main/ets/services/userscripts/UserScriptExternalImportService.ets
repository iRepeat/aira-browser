import { Want } from '@kit.AbilityKit';

const WANT_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';
const PARAMS_STREAM: string = 'ability.params.stream';

class UserScriptExternalImportSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UserScriptExternalImportSourceError';
  }
}

export class UserScriptExternalImportService {
  isCandidate(want: Want): boolean {
    return this.resolveCandidateUri(want).length > 0;
  }

  resolveSourceUri(want: Want): string {
    const uri = this.resolveCandidateUri(want);
    if (uri.length === 0) {
      throw new UserScriptExternalImportSourceError('Aira 只接收 .user.js 用户脚本文件。');
    }
    return uri;
  }

  buildUserFacingError(error: Object | undefined): string {
    if (error instanceof UserScriptExternalImportSourceError) {
      return error.message;
    }
    if (error instanceof Error && error.message.trim().length > 0) {
      return `无法导入用户脚本：${error.message.trim()}`;
    }
    return '无法导入用户脚本，请确认文件完整且格式正确。';
  }

  private resolveCandidateUri(want: Want): string {
    const action = String(want.action ?? '').trim();
    const directUri = String(want.uri ?? '').trim();
    if (this.acceptsDirectUri(action, directUri)) {
      return directUri;
    }
    // A normal page open must not be stolen because some unrelated parameter
    // happens to mention a script file.
    if (directUri.length > 0) {
      return '';
    }
    const parameterUris = this.collectParameterUris(want);
    for (let index = 0; index < parameterUris.length; index += 1) {
      const uri = parameterUris[index];
      if (this.isFileUri(uri) && this.isUserScriptUri(uri)) {
        return uri;
      }
    }
    return '';
  }

  private acceptsDirectUri(action: string, rawUri: string): boolean {
    if (!this.isUserScriptUri(rawUri)) {
      return false;
    }
    // HarmonyOS file open uses file://bundleName/path. WeChat's own "open with"
    // sheet starts the chosen app explicitly and often omits viewData, so a
    // .user.js file URI is an install request regardless of action. Non-file
    // script links stay limited to the documented viewData action.
    if (this.isFileUri(rawUri)) {
      return true;
    }
    return action === WANT_ACTION_VIEW_DATA;
  }

  private collectParameterUris(want: Want): string[] {
    const parameters = want.parameters as Record<string, Object> | undefined;
    if (parameters === undefined) {
      return [];
    }
    const uris: string[] = [];
    this.appendParameterUri(uris, parameters['uri']);
    this.appendParameterUri(uris, parameters['url']);
    this.appendParameterUri(uris, parameters['targetUrl']);
    this.appendParameterUri(uris, parameters[PARAMS_STREAM]);
    this.appendParameterUri(uris, parameters['stream']);
    return uris;
  }

  private appendParameterUri(target: string[], value: Object | undefined): void {
    if (Array.isArray(value)) {
      const values = value as Array<Object>;
      for (let index = 0; index < values.length; index += 1) {
        this.appendParameterUri(target, values[index]);
      }
      return;
    }
    const uri = String(value ?? '').trim();
    if (uri.length === 0 || uri === 'undefined') {
      return;
    }
    target.push(uri);
  }

  private isFileUri(rawUri: string): boolean {
    return rawUri.trim().toLowerCase().startsWith('file:');
  }

  private isUserScriptUri(rawUri: string): boolean {
    const withoutQuery = rawUri.trim().split('?')[0].split('#')[0];
    if (withoutQuery.length === 0) {
      return false;
    }
    if (withoutQuery.toLowerCase().endsWith('.user.js')) {
      return true;
    }
    try {
      return decodeURIComponent(withoutQuery).toLowerCase().endsWith('.user.js');
    } catch (_error) {
      return false;
    }
  }
}
