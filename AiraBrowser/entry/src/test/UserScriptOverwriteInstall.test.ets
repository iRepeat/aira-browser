import { describe, expect, it } from '@ohos/hypium';
import { EntitlementDecision } from '../main/ets/common/models/MembershipModels';
import { AiraFeatureKey } from '../main/ets/common/constants/MembershipFeatureKeys';
import {
  cloneInstalledUserScriptState,
  InstalledUserScriptState,
  UserScriptSettings
} from '../main/ets/features/userscripts/UserScriptMetadataModels';
import { UserScriptRepository } from '../main/ets/data/userscripts/UserScriptRepository';
import {
  UserScriptValueCommittedBytesAdapter,
  UserScriptValueStateStore
} from '../main/ets/data/userscripts/UserScriptValueStateStore';
import { MembershipRepository } from '../main/ets/data/membership/MembershipRepository';
import { MembershipFeature } from '../main/ets/features/membership/MembershipFeature';
import { EntitlementContext } from '../main/ets/services/membership/EntitlementService';
import { UserScriptLocalFileService } from '../main/ets/services/userscripts/UserScriptLocalFileService';
import {
  UserScriptPackageCommitResult,
  UserScriptPackageLifecycleCoordinator,
  UserScriptPackageMutationResult,
  UserScriptPackageSourceInput
} from '../main/ets/core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  UserScriptInstallSessionCoordinator,
  UserScriptInstallSourceResult
} from '../main/ets/core/userscripts/UserScriptInstallSessionCoordinator';

const INSTALLED_SCRIPT_ID: string = 'userscript-aira-overwrite-probe-1000';
const INSTALLED_UPDATE_URL: string = 'https://example.invalid/probe.meta.js';
const INSTALLED_DOWNLOAD_URL: string = 'https://example.invalid/probe.user.js';

class StatefulUserScriptRepository extends UserScriptRepository {
  private scripts: InstalledUserScriptState[] = [];

  seed(script: InstalledUserScriptState): void {
    this.scripts = this.scripts
      .filter((value: InstalledUserScriptState): boolean => value.id !== script.id)
      .concat(cloneInstalledUserScriptState(script));
  }

  initialize(): Promise<UserScriptSettings> {
    return Promise.resolve(this.getSettings());
  }

  getSettings(): UserScriptSettings {
    return {
      scripts: this.scripts.map(
        (script: InstalledUserScriptState): InstalledUserScriptState => cloneInstalledUserScriptState(script)
      ),
      autoUpdateEnabled: false,
      updatedAt: 0
    };
  }

  listScripts(): InstalledUserScriptState[] {
    return this.getSettings().scripts;
  }

  findScript(scriptId: string): InstalledUserScriptState | undefined {
    const script = this.scripts.find((value: InstalledUserScriptState): boolean => value.id === scriptId);
    return script === undefined ? undefined : cloneInstalledUserScriptState(script);
  }

  saveInstalledState(state: InstalledUserScriptState): Promise<UserScriptSettings> {
    this.seed(state);
    return Promise.resolve(this.getSettings());
  }
}

class AlwaysAllowedMembershipFeature extends MembershipFeature {
  constructor() {
    super(new MembershipRepository());
  }

  canUse(featureKey: AiraFeatureKey, _context: EntitlementContext): Promise<EntitlementDecision> {
    const decision: EntitlementDecision = {
      featureKey: featureKey,
      allowed: true,
      reason: 'allowed',
      title: '',
      message: '',
      primaryAction: 'none'
    };
    return Promise.resolve(decision);
  }

  recordUsage(_featureKey: AiraFeatureKey, _amount: number = 1): Promise<void> {
    return Promise.resolve();
  }
}

class InMemoryValueBytesAdapter implements UserScriptValueCommittedBytesAdapter {
  committed?: Uint8Array;

  readCommitted(): Promise<Uint8Array | undefined> {
    return Promise.resolve(this.committed);
  }

  replaceCommitted(bytes: Uint8Array): Promise<void> {
    this.committed = new Uint8Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    return Promise.resolve();
  }
}

class StubLocalFileService extends UserScriptLocalFileService {
  scriptSource: string = '';

  readScriptFile(_uri: string): Promise<string> {
    return Promise.resolve(this.scriptSource);
  }
}

class OverwriteFixture {
  readonly repository: StatefulUserScriptRepository = new StatefulUserScriptRepository();
  readonly valueStore: UserScriptValueStateStore = new UserScriptValueStateStore(
    new InMemoryValueBytesAdapter(),
    0,
    (): number => 1000
  );
  readonly localFileService: StubLocalFileService = new StubLocalFileService();
  readonly lifecycle: UserScriptPackageLifecycleCoordinator = new UserScriptPackageLifecycleCoordinator(
    this.repository,
    this.valueStore,
    undefined,
    new AlwaysAllowedMembershipFeature()
  );
  readonly installSession: UserScriptInstallSessionCoordinator = new UserScriptInstallSessionCoordinator(
    this.lifecycle,
    undefined,
    this.localFileService
  );
}

function buildUserScriptSource(
  name: string,
  namespace: string,
  version: string,
  extraHeaderLines: string[] = []
): string {
  const headerLines: string[] = [
    '// ==UserScript==',
    `// @name         ${name}`,
    `// @namespace    ${namespace}`,
    `// @version      ${version}`,
    '// @match        https://example.invalid/*',
    '// @grant        none'
  ].concat(extraHeaderLines);
  headerLines.push('// ==/UserScript==', '', '(function () {', '  console.log("probe");', '})();');
  return headerLines.join('\n');
}

function buildInstalledProbe(): InstalledUserScriptState {
  return {
    id: INSTALLED_SCRIPT_ID,
    name: 'Aira Overwrite Probe',
    namespace: 'aira.overwrite.test',
    version: '1.0.0',
    description: 'installed copy',
    iconUrl: '',
    source: buildUserScriptSource('Aira Overwrite Probe', 'aira.overwrite.test', '1.0.0'),
    sourceUrl: 'https://example.invalid/probe.user.js',
    updateUrl: INSTALLED_UPDATE_URL,
    downloadUrl: INSTALLED_DOWNLOAD_URL,
    enabled: true,
    matches: ['https://example.invalid/*'],
    includes: [],
    excludeMatches: [],
    excludes: [],
    grants: ['none'],
    requireUrls: [],
    requireSources: [],
    resources: [],
    connectRules: [],
    noframes: false,
    runAt: 'document-end',
    installSource: 'url',
    createdAt: 1000,
    updatedAt: 1000,
    lastCheckedAt: 0
  };
}

function buildLocalCopyWithNoUpdateUrls(version: string): string {
  return buildUserScriptSource('Aira Overwrite Probe', 'aira.overwrite.test', version);
}

export default function userScriptOverwriteInstallTest(): void {
  describe('UserScript overwrite install', () => {
    it('loads a local copy of an installed script as an overwrite instead of a duplicate', 0, async () => {
      const fixture = new OverwriteFixture();
      fixture.repository.seed(buildInstalledProbe());
      fixture.localFileService.scriptSource = buildLocalCopyWithNoUpdateUrls('2.0.0');

      const result: UserScriptInstallSourceResult = await fixture.installSession.loadSource({
        type: 'file_uri',
        uri: 'file://docs/probe.user.js'
      });

      expect(result.status).assertEqual('loaded');
      if (result.status !== 'loaded') {
        return;
      }
      expect(result.state.existingTarget.scriptId).assertEqual(INSTALLED_SCRIPT_ID);
      expect(result.state.existingTarget.version).assertEqual('1.0.0');
      expect(result.state.preview?.status).assertEqual('ready');
    });

    it('keeps one script, its identity state, and its update addresses when overwriting', 0, async () => {
      const fixture = new OverwriteFixture();
      fixture.repository.seed(buildInstalledProbe());
      fixture.localFileService.scriptSource = buildLocalCopyWithNoUpdateUrls('2.0.0');
      const entitlementContext: EntitlementContext = {
        dataScope: 'profile_persistent',
        privacyMode: 'regular',
        loggedIn: true
      };

      await fixture.installSession.loadSource({
        type: 'file_uri',
        uri: 'file://docs/probe.user.js'
      });
      const result: UserScriptPackageMutationResult = await fixture.installSession.commit(entitlementContext);

      expect(result.status).assertEqual('updated');
      expect(result.status === 'updated' ? result.scriptId : '').assertEqual(INSTALLED_SCRIPT_ID);
      const scripts = fixture.repository.listScripts();
      expect(scripts.length).assertEqual(1);
      const installed = scripts[0];
      expect(installed.id).assertEqual(INSTALLED_SCRIPT_ID);
      expect(installed.version).assertEqual('2.0.0');
      expect(installed.createdAt).assertEqual(1000);
      expect(installed.enabled).assertTrue();
      // The local copy declares no @updateURL/@downloadURL, so the addresses that keep
      // future update checks working must survive the overwrite.
      expect(installed.updateUrl).assertEqual(INSTALLED_UPDATE_URL);
      expect(installed.downloadUrl).assertEqual(INSTALLED_DOWNLOAD_URL);
    });

    it('overwrites when a confirmed package matches an installed script by identity', 0, async () => {
      const fixture = new OverwriteFixture();
      fixture.repository.seed(buildInstalledProbe());
      const input: UserScriptPackageSourceInput = {
        source: buildLocalCopyWithNoUpdateUrls('1.1.0'),
        installSource: 'file',
        sourceUrl: '',
        existingScriptId: ''
      };

      const result: UserScriptPackageCommitResult = await fixture.lifecycle.saveInteractiveSource(input);

      expect(result.status).assertEqual('updated');
      expect(result.status === 'updated' ? result.scriptId : '').assertEqual(INSTALLED_SCRIPT_ID);
      expect(fixture.repository.listScripts().length).assertEqual(1);
      expect(fixture.repository.findScript(INSTALLED_SCRIPT_ID)?.version).assertEqual('1.1.0');
    });

    it('still installs a script that shares no identity with an installed one', 0, async () => {
      const fixture = new OverwriteFixture();
      fixture.repository.seed(buildInstalledProbe());
      fixture.localFileService.scriptSource =
        buildUserScriptSource('Aira Unrelated Probe', 'aira.other.test', '1.0.0');

      const loadResult: UserScriptInstallSourceResult = await fixture.installSession.loadSource({
        type: 'file_uri',
        uri: 'file://docs/other.user.js'
      });

      expect(loadResult.status).assertEqual('loaded');
      if (loadResult.status !== 'loaded') {
        return;
      }
      expect(loadResult.state.existingTarget.scriptId.length).assertEqual(0);
      const result: UserScriptPackageMutationResult = await fixture.installSession.commit();
      expect(result.status).assertEqual('installed');
      expect(fixture.repository.listScripts().length).assertEqual(2);
    });

    it('treats a same-name script in another namespace as a separate install', 0, async () => {
      const fixture = new OverwriteFixture();
      fixture.repository.seed(buildInstalledProbe());
      const input: UserScriptPackageSourceInput = {
        source: buildUserScriptSource('Aira Overwrite Probe', 'aira.another.namespace', '1.0.0'),
        installSource: 'file',
        sourceUrl: '',
        existingScriptId: ''
      };

      const result: UserScriptPackageCommitResult = await fixture.lifecycle.saveInteractiveSource(input);

      expect(result.status).assertEqual('installed');
      expect(fixture.repository.listScripts().length).assertEqual(2);
    });
  });
}
