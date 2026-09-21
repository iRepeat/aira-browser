/**
 * Navigation forensics probe (temporary).
 *
 * Reported symptom: after opening a second/third level page on an ordinary multi-document site and
 * sending the app to the background without killing it, returning to the foreground puts the page back
 * on the site's first page. The restore, download-rewind, snapshot and paging paths already decide
 * everything needed to explain that, but their runtime-event sinks are no-ops in this build, so the
 * decisions are invisible. This probe records them under one tag so a single capture answers which
 * branch ran and which URL it used.
 *
 * This module deliberately imports no platform kit: several build guards load core browser modules in a
 * sandbox that rejects platform dependencies. The platform writer (HiLog) is installed once from the
 * ability through {@link AiraNavForensicsProbe.install}.
 *
 * Everything recorded is either a URL the user is already browsing or a bounded enum/flag. Remove this
 * probe together with its call sites once the branch is identified.
 */
export type AiraNavForensicsWriter = (line: string) => void;

export class AiraNavForensicsProbe {
  private static writer?: AiraNavForensicsWriter = undefined;
  private static sequence: number = 0;
  private static lastForegroundAt: number = 0;

  static install(writer: AiraNavForensicsWriter): void {
    AiraNavForensicsProbe.writer = writer;
  }

  static markForeground(source: string, windowId: string = ''): void {
    AiraNavForensicsProbe.lastForegroundAt = Date.now();
    AiraNavForensicsProbe.log('foreground', `source=${source} window=${windowId}`);
  }

  static markBackground(source: string, windowId: string = ''): void {
    AiraNavForensicsProbe.log('background', `source=${source} window=${windowId}`);
  }

  static log(event: string, detail: string): void {
    const writer = AiraNavForensicsProbe.writer;
    if (writer === undefined) {
      return;
    }
    AiraNavForensicsProbe.sequence += 1;
    const sinceForegroundMs = AiraNavForensicsProbe.lastForegroundAt <= 0
      ? -1
      : Date.now() - AiraNavForensicsProbe.lastForegroundAt;
    try {
      writer(`seq=${AiraNavForensicsProbe.sequence} since_fg_ms=${sinceForegroundMs} ` +
        `event=${event} ${detail}`);
    } catch (_error) {
    }
  }

  /** One navigation command the app is about to issue. */
  static logLoadIssued(owner: string, tabId: string, targetUrl: string, clearHistory: boolean): void {
    AiraNavForensicsProbe.log(
      'load_issued',
      `owner=${owner} tab=${tabId} clear_history=${clearHistory ? 1 : 0} target=${targetUrl}`
    );
  }

  /** A resolved restore/rewind decision: which reason, which candidate won, what the tab held. */
  static logRestoreDecision(
    owner: string,
    tabId: string,
    reason: string,
    targetUrl: string,
    snapshotPath: string,
    tabFacts: string
  ): void {
    AiraNavForensicsProbe.log(
      'restore_decision',
      `owner=${owner} tab=${tabId} reason=${reason} snapshot=${snapshotPath.length > 0 ? 1 : 0} ` +
        `target=${targetUrl} ${tabFacts}`
    );
  }

  static logWebStateRestore(tabId: string, bytes: number, restored: boolean, reason: string): void {
    AiraNavForensicsProbe.log(
      'web_state_restore',
      `tab=${tabId} restored=${restored ? 1 : 0} bytes=${bytes} reason=${reason}`
    );
  }

  static logSnapshotPersist(tabId: string, reason: string, status: string, detail: string): void {
    AiraNavForensicsProbe.log(
      'snapshot_persist',
      `tab=${tabId} reason=${reason} status=${status} ${detail}`
    );
  }

  static logDownloadRewind(
    owner: string,
    tabId: string,
    skippedUrl: string,
    fallbackUrl: string,
    liveDocumentUrl: string,
    reason: string
  ): void {
    AiraNavForensicsProbe.log(
      'download_rewind',
      `owner=${owner} tab=${tabId} reason=${reason} skipped=${skippedUrl} ` +
        `live=${liveDocumentUrl} fallback=${fallbackUrl}`
    );
  }

  static logPageEvent(tabId: string, kind: string, url: string, detail: string = ''): void {
    AiraNavForensicsProbe.log('page_event', `tab=${tabId} kind=${kind} url=${url} ${detail}`);
  }

  static logRuntimeState(tabId: string, runtimeState: string, liveController: boolean, detail: string): void {
    AiraNavForensicsProbe.log(
      'runtime_state',
      `tab=${tabId} state=${runtimeState} live=${liveController ? 1 : 0} ${detail}`
    );
  }

  static logRuntimeEvent(type: string, message: string, tabId: string): void {
    AiraNavForensicsProbe.log('runtime_event', `tab=${tabId} type=${type} ${message}`);
  }
}
