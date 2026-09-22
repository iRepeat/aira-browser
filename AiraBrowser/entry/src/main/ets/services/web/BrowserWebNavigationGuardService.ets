/**
 * One ArkWeb navigation callback is running on this tab, on this thread.
 *
 * ArkWeb answers an in-navigation Controller mutation with a reentrancy `CHECK`, not with an error code.
 * The custom-UA setter on a Controller whose main-frame navigation is being decided walks the frame tree and
 * asks the navigation controller to reload, and the pending-entry reentrancy guard aborts the process on the
 * spot. The reproducer is any main-frame navigation this browser rewrites inside `onLoadIntercept` — an
 * `http://` link upgraded by HTTPS First is the common one, because the rewrite ends in a second `loadUrl()`
 * issued from inside the same callback.
 *
 * `BrowserWebEventHostCoordinator` therefore opens a scope around both navigation callbacks and
 * `BrowserUserAgentRuntimeService` refuses to mutate a Controller while one is open. The identity change is not
 * dropped: it is reported as `identity_transition_required`, so the navigation proceeds under the identity
 * already bound to the Controller and the pending change lands on the next explicit navigation, which is the
 * same terminal ADR 0073 already defines for a custom-to-native transition.
 */
export interface BrowserWebNavigationScope {
  /** Closes this scope. A nested close keeps the open scope in force. */
  close: () => void;
}

export class BrowserWebNavigationGuardService {
  private activeScopeIdByTabId: Record<string, number | undefined> = {};
  private nextScopeId: number = 0;

  openTabNavigationScope(tabId: string): BrowserWebNavigationScope {
    const normalizedTabId = tabId.trim();
    const scopeId = ++this.nextScopeId;
    let open = true;
    if (normalizedTabId.length > 0) {
      this.activeScopeIdByTabId[normalizedTabId] = scopeId;
    }
    return {
      close: (): void => {
        if (!open) {
          return;
        }
        open = false;
        if (normalizedTabId.length > 0 && this.activeScopeIdByTabId[normalizedTabId] === scopeId) {
          // A callback that opened its own scope while this one was running owns the tab now; only the
          // innermost close clears it, so the guard cannot be lifted in the middle of an outer callback.
          this.activeScopeIdByTabId[normalizedTabId] = undefined;
        }
      }
    };
  }

  isTabNavigationInProgress(tabId: string): boolean {
    return this.activeScopeIdByTabId[tabId] !== undefined;
  }

  releaseTab(tabId: string): void {
    this.activeScopeIdByTabId[tabId] = undefined;
  }
}

export const sharedBrowserWebNavigationGuardService: BrowserWebNavigationGuardService =
  new BrowserWebNavigationGuardService();
