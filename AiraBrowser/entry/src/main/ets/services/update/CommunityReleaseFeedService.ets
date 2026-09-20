import http from '@ohos.net.http';
import { AIRA_COMMUNITY_REPOSITORY_URL } from '../../common/constants/AiraCommunityProjectLinks';

/**
 * The public GitHub Releases atom feed. It is the Community distribution's only
 * release channel, needs no token, and — unlike the REST API — is not subject to
 * the anonymous per-address rate limit that a browser can exhaust.
 */
export const AIRA_COMMUNITY_RELEASES_ATOM_URL: string =
  `${AIRA_COMMUNITY_REPOSITORY_URL}/releases.atom`;

const COMMUNITY_RELEASE_TIMEOUT_MS: number = 10000;
const COMMUNITY_RELEASE_MAX_ITEMS: number = 10;

interface CommunityVersionIdentity {
  versionName: string;
  versionCode: number;
}

interface CommunityChangelogSection {
  summary: string;
  items: string[];
}

/**
 * One remote Community release, already reduced to what the update prompt may
 * show. `versionCode` is 0 when the published title did not carry one, in which
 * case the coordinator decides by `versionName` instead.
 */
export interface CommunityReleaseInfo {
  versionName: string;
  versionCode: number;
  tagName: string;
  releaseUrl: string;
  title: string;
  publishedAt: string;
  summary: string;
  items: string[];
}

interface HtmlEntityReplacement {
  pattern: RegExp;
  replacement: string;
}

const HTML_ENTITY_REPLACEMENTS: HtmlEntityReplacement[] = [
  { pattern: /&lt;/g, replacement: '<' },
  { pattern: /&gt;/g, replacement: '>' },
  { pattern: /&quot;/g, replacement: '"' },
  { pattern: /&#39;/g, replacement: '\'' },
  { pattern: /&apos;/g, replacement: '\'' },
  { pattern: /&nbsp;/g, replacement: ' ' },
  { pattern: /&mdash;/g, replacement: '—' },
  { pattern: /&ndash;/g, replacement: '–' },
  { pattern: /&hellip;/g, replacement: '…' },
  { pattern: /&amp;/g, replacement: '&' }
];

/**
 * Reads the newest entry of the public repo's release feed. Returns undefined on
 * any transport, status, or parse problem: checking for updates is best effort
 * and must never surface a network error to the user.
 */
export class CommunityReleaseFeedService {
  async fetchLatestRelease(): Promise<CommunityReleaseInfo | undefined> {
    try {
      const body = await this.requestFeed();
      if (body === undefined) {
        return undefined;
      }
      return this.parseAtomFeed(body);
    } catch (_error) {
      return undefined;
    }
  }

  private async requestFeed(): Promise<string | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(AIRA_COMMUNITY_RELEASES_ATOM_URL, {
        method: 'GET' as http.RequestMethod,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: COMMUNITY_RELEASE_TIMEOUT_MS,
        readTimeout: COMMUNITY_RELEASE_TIMEOUT_MS,
        header: {
          'Accept': 'application/atom+xml,application/xml,text/xml,*/*'
        } as Record<string, string>
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        return undefined;
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  /** Parses the first `<entry>` of an Atom feed. Public for the contract test. */
  parseAtomFeed(atomXml: string): CommunityReleaseInfo | undefined {
    const entry = this.extractFirstEntry(atomXml);
    if (entry === undefined) {
      return undefined;
    }
    const title = this.normalizeText(this.extractTagText(entry, 'title'));
    const releaseUrl = this.extractAlternateLink(entry);
    const tagName = this.extractTagText(entry, 'id').replace(/^.*Repository\/\d+\//, '').trim();
    const publishedAt = this.extractTagText(entry, 'updated').substring(0, 10);
    const html = this.decodeHtml(this.extractTagText(entry, 'content'));
    const identity = this.resolveVersionIdentity(title, tagName, html);
    if (identity === undefined) {
      return undefined;
    }
    const section = this.parseChangelogSection(html);
    return {
      versionName: identity.versionName,
      versionCode: identity.versionCode,
      tagName: tagName,
      releaseUrl: releaseUrl.length > 0 ? releaseUrl : `${AIRA_COMMUNITY_REPOSITORY_URL}/releases`,
      title: title.length > 0 ? title : `Aira Community ${identity.versionName}`,
      publishedAt: publishedAt,
      summary: section.summary,
      items: section.items.slice(0, COMMUNITY_RELEASE_MAX_ITEMS)
    };
  }

  private extractFirstEntry(atomXml: string): string | undefined {
    const match = /<entry\b[\s\S]*?<\/entry>/.exec(atomXml);
    return match === null ? undefined : match[0];
  }

  private extractTagText(xml: string, tag: string): string {
    const pattern = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`);
    const match = pattern.exec(xml);
    if (match === null) {
      return '';
    }
    return match[1].replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '').trim();
  }

  private extractAlternateLink(entry: string): string {
    const match = /<link\b[^>]*rel="alternate"[^>]*href="([^"]*)"/.exec(entry) ??
      /<link\b[^>]*href="([^"]*)"[^>]*rel="alternate"/.exec(entry);
    return match === null ? '' : this.decodeHtml(match[1]).trim();
  }

  /**
   * Resolves the version from the release title when it carries the explicit
   * `name (code)` pair the release script writes, then falls back to the tag for
   * a name-only release and finally to the changelog heading.
   */
  private resolveVersionIdentity(
    title: string,
    tagName: string,
    html: string
  ): CommunityVersionIdentity | undefined {
    const fromTitle = /(\d+\.\d+\.\d+)\s*[（(]\s*(\d+)\s*[)）]/.exec(title);
    if (fromTitle !== null) {
      return this.buildVersionIdentity(fromTitle[1], fromTitle[2]);
    }
    const fromHeading = /(\d+\.\d+\.\d+)\s*[（(]\s*(\d+)\s*[)）]/.exec(html);
    if (fromHeading !== null) {
      return this.buildVersionIdentity(fromHeading[1], fromHeading[2]);
    }
    const fromTag = /v?(\d+\.\d+\.\d+)/.exec(tagName.length > 0 ? tagName : title);
    if (fromTag !== null) {
      return this.buildVersionIdentity(fromTag[1], this.extractVersionCode(html));
    }
    return undefined;
  }

  private buildVersionIdentity(versionName: string, versionCode: string | undefined): CommunityVersionIdentity {
    return {
      versionName: versionName,
      versionCode: this.normalizeCount(versionCode)
    };
  }

  /**
   * Reduces the release body to the same shape the changelog page uses: the first
   * paragraph after the version heading becomes the summary and the bullets under
   * it become the items. The body also carries install instructions, so parsing
   * starts at the `更新日志` heading instead of at the top.
   */
  private parseChangelogSection(html: string): CommunityChangelogSection {
    const lines = this.toPlainLines(html);
    const headingIndex = lines.findIndex((line: string) => line === '更新日志');
    const sectionStart = headingIndex >= 0 ? headingIndex + 1 : 0;
    const summaryLines: string[] = [];
    const items: string[] = [];
    for (let index = sectionStart; index < lines.length; index += 1) {
      const line = lines[index];
      if (this.isVersionHeadingLine(line)) {
        if (summaryLines.length > 0 || items.length > 0) {
          break;
        }
        continue;
      }
      if (line.startsWith('- ')) {
        const item = line.substring(2).trim();
        if (item.length > 0) {
          items.push(item);
        }
        continue;
      }
      if (items.length === 0 && line.length > 0) {
        summaryLines.push(line);
      }
    }
    return {
      summary: summaryLines.join(' ').trim(),
      items: items
    };
  }

  private isVersionHeadingLine(line: string): boolean {
    return /^\d+\.\d+\.\d+/.test(line) || /^\d{4}-\d{2}-\d{2}$/.test(line);
  }

  /**
   * Flattens HTML to newline-separated text, turning list items into `- ` bullets
   * so the downstream parser can share the changelog markdown heuristics.
   */
  private toPlainLines(html: string): string[] {
    const withBullets = html.replace(/<li\b[^>]*>/gi, '\n- ');
    const withBreaks = withBullets
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|h[1-6]|ul|ol|li)>/gi, '\n')
      .replace(/<(p|div|h[1-6]|ul|ol)\b[^>]*>/gi, '\n');
    return this.decodeHtml(withBreaks)
      .replace(/<[^>]*>/g, '')
      .split('\n')
      .map((line: string) => line.replace(/\s+/g, ' ').trim());
  }

  private decodeHtml(value: string): string {
    let decoded = value;
    HTML_ENTITY_REPLACEMENTS.forEach((entity: HtmlEntityReplacement) => {
      decoded = decoded.replace(entity.pattern, entity.replacement);
    });
    return decoded.replace(/&#(\d+);/g, (_match: string, code: string) => {
      const value = Number(code);
      return Number.isFinite(value) ? String.fromCharCode(value) : '';
    });
  }

  private extractVersionCode(html: string): string | undefined {
    const match = /(?:versionCode|版本号)[：:\s]*(\d+)/i.exec(html);
    return match === null ? undefined : match[1];
  }

  private normalizeText(value: string): string {
    return value.replace(/\s+/g, ' ').trim();
  }

  private normalizeCount(value: string | undefined): number {
    const count = Number(value);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }
}
