/*
 * App-side half of the Novel font de-obfuscation runtime. Concatenated by
 * scripts/build-novel-font-deobfuscator.js after the Brotli module registry, so
 * `airaRequire` is in scope and `window` is the page.
 *
 * ES5 on purpose: this is injected into third-party pages.
 */

var AIRA_NOVEL_FONT_VERSION = 'aira-novel-font-1';

// Table tags indexable by the 6-bit tag field of a WOFF2 table directory entry.
var AIRA_NOVEL_FONT_TABLE_TAGS = [
  'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post',
  'cvt ', 'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT',
  'EBLC', 'gasp', 'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea',
  'vmtx', 'BASE', 'GDEF', 'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH',
  'CBDT', 'CBLC', 'COLR', 'CPAL', 'SVG ', 'sbix', 'acnt', 'avar',
  'bdat', 'bloc', 'bsln', 'cvar', 'fdsc', 'feat', 'fmtx', 'fvar',
  'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx', 'opbd', 'prop',
  'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill'
];

// Detection thresholds. Modern Chinese prose effectively never uses the CJK
// Extension B plane (U+20000+), so a handful of such characters plus a modest
// share of the text is a strong signal of codepoint substitution rather than a
// genuinely obscure document.
var AIRA_NOVEL_FONT_MIN_OBFUSCATED_COUNT = 8;
var AIRA_NOVEL_FONT_MIN_OBFUSCATED_RATIO = 0.05;

function airaNovelFontCodePoints(text) {
  var result = [];
  for (var i = 0; i < text.length; ) {
    var code = text.codePointAt ? text.codePointAt(i) : text.charCodeAt(i);
    if (code === undefined || code !== code) { code = text.charCodeAt(i); }
    var size = code > 0xffff ? 2 : 1;
    result.push(code);
    i += size;
  }
  return result;
}

function airaNovelFontReadBase128(bytes, position) {
  var value = 0;
  for (var i = 0; i < 5; i++) {
    var byte = bytes[position++];
    value = value * 128 + (byte & 0x7f);
    if ((byte & 0x80) === 0) {
      return [value, position];
    }
  }
  throw new Error('invalid base128');
}

/**
 * Whether a table stores `transformLength` instead of `origLength`. Per the
 * WOFF2 spec this depends on the table and the transform version bits, and
 * getting it wrong desynchronises the whole table directory.
 */
function airaNovelFontHasTransformLength(tag, transformVersion) {
  if (tag === 'glyf' || tag === 'loca') {
    return transformVersion !== 3;
  }
  if (tag === 'hmtx') {
    return transformVersion === 1;
  }
  return transformVersion !== 0;
}

function airaNovelFontSliceTables(bytes) {
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 48 || view.getUint32(0, false) !== 0x774F4632) {
    return { ok: false, reason: 'signature' };
  }
  // 'ttcf': a font collection keeps a second directory between the table
  // directory and the data. None of the obfuscation fonts we target are
  // collections, so refuse rather than mis-slice.
  if (view.getUint32(4, false) === 0x74746366) {
    return { ok: false, reason: 'collection-unsupported' };
  }
  var numTables = view.getUint16(12, false);
  var totalCompressedSize = view.getUint32(20, false);
  if (numTables <= 0 || numTables > 512) {
    return { ok: false, reason: 'numTables' };
  }

  var position = 48;
  var entries = [];
  for (var i = 0; i < numTables; i++) {
    if (position >= bytes.length) {
      return { ok: false, reason: 'directory' };
    }
    var flags = bytes[position++];
    var tagIndex = flags & 0x3f;
    var transformVersion = (flags >> 6) & 0x03;
    var tag;
    if (tagIndex === 63) {
      if (position + 4 > bytes.length) {
        return { ok: false, reason: 'directory-tag' };
      }
      tag = String.fromCharCode(bytes[position], bytes[position + 1],
        bytes[position + 2], bytes[position + 3]);
      position += 4;
    } else {
      if (tagIndex >= AIRA_NOVEL_FONT_TABLE_TAGS.length) {
        return { ok: false, reason: 'tag-index' };
      }
      tag = AIRA_NOVEL_FONT_TABLE_TAGS[tagIndex];
    }
    var originalRead = airaNovelFontReadBase128(bytes, position);
    var storedLength = originalRead[0];
    position = originalRead[1];
    if (airaNovelFontHasTransformLength(tag, transformVersion)) {
      var transformRead = airaNovelFontReadBase128(bytes, position);
      storedLength = transformRead[0];
      position = transformRead[1];
    }
    entries.push({ tag: tag, length: storedLength });
  }

  if (position + totalCompressedSize > bytes.length) {
    return { ok: false, reason: 'compressed-range' };
  }
  var decoded = airaRequire('dec/decode')
    .BrotliDecompressBuffer(bytes.subarray(position, position + totalCompressedSize));

  var tables = {};
  var offset = 0;
  for (var j = 0; j < entries.length; j++) {
    var entry = entries[j];
    tables[entry.tag] = decoded.subarray(offset, offset + entry.length);
    offset += entry.length;
  }
  return { ok: true, tables: tables };
}

function airaNovelFontCmapPriority(platformId, encodingId) {
  if (platformId === 3 && encodingId === 10) { return 3; }
  if (platformId === 0) { return 2; }
  if (platformId === 3 && encodingId === 1) { return 1; }
  return 0;
}

function airaNovelFontParseCmapFormat4(bytes, offset, assign) {
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  var segmentCount = view.getUint16(offset + 6, false) / 2;
  var endOffset = offset + 14;
  var startOffset = endOffset + segmentCount * 2 + 2;
  var deltaOffset = startOffset + segmentCount * 2;
  var rangeOffset = deltaOffset + segmentCount * 2;
  for (var i = 0; i < segmentCount; i++) {
    var end = view.getUint16(endOffset + i * 2, false);
    var start = view.getUint16(startOffset + i * 2, false);
    if (start === 0xffff) { continue; }
    var delta = view.getInt16(deltaOffset + i * 2, false);
    var range = view.getUint16(rangeOffset + i * 2, false);
    for (var code = start; code <= end && code !== 0x10000; code++) {
      var glyph;
      if (range === 0) {
        glyph = (code + delta) & 0xffff;
      } else {
        var glyphOffset = rangeOffset + i * 2 + range + (code - start) * 2;
        if (glyphOffset + 2 > bytes.length) { continue; }
        glyph = view.getUint16(glyphOffset, false);
        if (glyph !== 0) { glyph = (glyph + delta) & 0xffff; }
      }
      if (glyph) { assign(code, glyph); }
    }
  }
}

function airaNovelFontParseCmapFormat12(bytes, offset, assign) {
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  var groupCount = view.getUint32(offset + 12, false);
  for (var i = 0; i < groupCount; i++) {
    var base = offset + 16 + i * 12;
    var start = view.getUint32(base, false);
    var end = view.getUint32(base + 4, false);
    var glyph = view.getUint32(base + 8, false);
    if (end - start > 0x20000) { continue; }
    for (var code = start; code <= end; code++) {
      assign(code, glyph + (code - start));
    }
  }
}

function airaNovelFontParseCmap(bytes) {
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  var count = view.getUint16(2, false);
  var subtables = [];
  for (var i = 0; i < count; i++) {
    var record = 4 + i * 8;
    if (record + 8 > bytes.length) { break; }
    var platformId = view.getUint16(record, false);
    var encodingId = view.getUint16(record + 2, false);
    var offset = view.getUint32(record + 4, false);
    if (offset + 2 > bytes.length) { continue; }
    subtables.push({
      offset: offset,
      format: view.getUint16(offset, false),
      priority: airaNovelFontCmapPriority(platformId, encodingId)
    });
  }
  subtables.sort(function (left, right) { return left.priority - right.priority; });

  var mapping = {};
  function assign(code, glyph) { mapping[code] = glyph; }
  for (var j = 0; j < subtables.length; j++) {
    var subtable = subtables[j];
    try {
      if (subtable.format === 4) {
        airaNovelFontParseCmapFormat4(bytes, subtable.offset, assign);
      } else if (subtable.format === 12) {
        airaNovelFontParseCmapFormat12(bytes, subtable.offset, assign);
      }
    } catch (_error) {
      // A malformed subtable must not discard the ones already parsed.
    }
  }
  return mapping;
}

/**
 * `post` format 2.0: glyph id -> glyph name. The obfuscation fonts name each
 * glyph `uniXXXX` for the character it draws, which is what turns a codepoint
 * mapping into a character mapping.
 */
function airaNovelFontParsePost(bytes) {
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 34 || view.getUint32(0, false) !== 0x00020000) {
    return undefined;
  }
  var glyphCount = view.getUint16(32, false);
  if (34 + glyphCount * 2 > bytes.length) {
    return undefined;
  }
  var indices = [];
  for (var i = 0; i < glyphCount; i++) {
    indices.push(view.getUint16(34 + i * 2, false));
  }

  var names = [];
  var position = 34 + glyphCount * 2;
  while (position < bytes.length) {
    var length = bytes[position++];
    var name = '';
    for (var c = 0; c < length && position < bytes.length; c++) {
      name += String.fromCharCode(bytes[position++]);
    }
    names.push(name);
  }

  var byGlyph = {};
  for (var gid = 0; gid < glyphCount; gid++) {
    var index = indices[gid];
    // The first 258 entries are the standard Macintosh names, which are never
    // `uniXXXX` and carry no information here.
    if (index < 258) { continue; }
    var glyphName = names[index - 258];
    if (glyphName) { byGlyph[gid] = glyphName; }
  }
  return byGlyph;
}

function airaNovelFontGlyphNameToCharacter(name) {
  var match = /^uni([0-9A-Fa-f]{4,6})$/.exec(name);
  if (!match) { return undefined; }
  var code = parseInt(match[1], 16);
  if (!isFinite(code) || code <= 0 || code > 0x10ffff) { return undefined; }
  try {
    return String.fromCodePoint(code);
  } catch (_error) {
    return undefined;
  }
}

/**
 * Recovers codepoint -> character from one WOFF2 file. Returns `{ ok, map }`.
 */
function airaNovelFontParseWoff2(bytes) {
  try {
    if (!bytes || bytes.length < 48) {
      return { ok: false, reason: 'short' };
    }
    var sliced = airaNovelFontSliceTables(bytes);
    if (!sliced.ok) {
      return { ok: false, reason: sliced.reason };
    }
    var cmapBytes = sliced.tables['cmap'];
    var postBytes = sliced.tables['post'];
    if (!cmapBytes || !postBytes) {
      return { ok: false, reason: 'missing-tables' };
    }
    var codepointToGlyph = airaNovelFontParseCmap(cmapBytes);
    var glyphToName = airaNovelFontParsePost(postBytes);
    if (!glyphToName) {
      return { ok: false, reason: 'post-format' };
    }

    var mapping = {};
    var resolved = 0;
    for (var key in codepointToGlyph) {
      if (!Object.prototype.hasOwnProperty.call(codepointToGlyph, key)) { continue; }
      var glyphName = glyphToName[codepointToGlyph[key]];
      if (!glyphName) { continue; }
      var character = airaNovelFontGlyphNameToCharacter(glyphName);
      if (character === undefined) { continue; }
      mapping[key] = character;
      resolved++;
    }
    if (resolved === 0) {
      // The font drew real glyphs under opaque names; nothing to recover from
      // `post`, so the caller must not treat this as a fix.
      return { ok: false, reason: 'no-glyph-names' };
    }
    return { ok: true, map: mapping, resolved: resolved };
  } catch (error) {
    return { ok: false, reason: 'error:' + (error && error.message ? error.message : 'unknown') };
  }
}

/**
 * CSS text from the document's @font-face rules. Returns the text it could read
 * synchronously plus the same-origin stylesheet hrefs it could not, so the
 * caller can fetch those instead of losing the font.
 *
 * Reading `styleSheets` only works for the live document; a chapter parsed with
 * DOMParser has no registered sheets, which is why the <link> scan matters.
 */
function airaNovelFontCollectCss(doc) {
  var texts = [];
  var linkHrefs = [];
  function addLink(href) {
    if (!href) { return; }
    if (linkHrefs.indexOf(href) < 0) { linkHrefs.push(href); }
  }

  var sheets = doc.styleSheets || [];
  for (var s = 0; s < sheets.length; s++) {
    var sheet = sheets[s];
    var sheetText = '';
    try {
      var rules = sheet.cssRules;
      if (rules) {
        for (var r = 0; r < rules.length; r++) {
          var rule = rules[r];
          if (!rule || !rule.style) { continue; }
          var src = rule.style.getPropertyValue ? rule.style.getPropertyValue('src') : rule.style.src;
          if (src) {
            sheetText += 'src:' + src + ';';
          }
        }
      }
    } catch (_error) {
      sheetText = '';
    }
    if (sheetText.length > 0) {
      texts.push(sheetText);
    } else if (sheet.href) {
      addLink(sheet.href);
    }
  }

  var inlineStyles = doc.querySelectorAll ? doc.querySelectorAll('style') : [];
  for (var t = 0; t < inlineStyles.length; t++) {
    var text = inlineStyles[t].textContent;
    if (text) { texts.push(text); }
  }

  var links = doc.querySelectorAll ? doc.querySelectorAll('link[rel~="stylesheet"]') : [];
  for (var l = 0; l < links.length; l++) {
    addLink(links[l].href);
  }
  return { texts: texts, linkHrefs: linkHrefs };
}

function airaNovelFontIsSameOrigin(url, doc) {
  try {
    return new URL(url, doc.baseURI || doc.location.href).origin === doc.location.origin;
  } catch (_error) {
    // A document without a usable location (a DOMParser result) cannot prove
    // cross-origin, so let the fetch decide through its own CORS rules.
    return true;
  }
}

function airaNovelFontResolveUrl(raw, baseUrl) {
  var trimmed = String(raw || '').trim();
  if (trimmed.length === 0) { return ''; }
  try {
    return new URL(trimmed, baseUrl).href;
  } catch (_error) {
    return trimmed;
  }
}

function airaNovelFontExtractWoff2Urls(cssText, baseUrl) {
  var urls = [];
  var pattern = /url\(\s*(['"]?)([^'")]+)\1\s*\)/g;
  var match;
  while ((match = pattern.exec(cssText)) !== null) {
    var value = match[2];
    if (/\.woff2(\?|#|$)/i.test(value)) {
      urls.push(airaNovelFontResolveUrl(value, baseUrl));
    }
  }
  return urls;
}

var AIRA_NOVEL_FONT_MAX_FONTS = 8;

/**
 * Resolves codepoint -> character for a document by locating its @font-face
 * rule, fetching the WOFF2, and parsing it. Resolves to
 * `{ ok, map, resolved, reason, fontCount }` and never rejects.
 */
function airaNovelFontResolveForDocument(doc, fetchImpl) {
  var doFetch = fetchImpl || (typeof fetch === 'function' ? fetch : null);
  return new Promise(function (resolve) {
    if (!doFetch) {
      resolve({ ok: false, reason: 'no-fetch', resolved: 0, fontCount: 0 });
      return;
    }
    var collected = airaNovelFontCollectCss(doc);
    var base = doc.baseURI || (doc.location && doc.location.href) || '';
    var urls = [];
    function pushUrls(list) {
      for (var i = 0; i < list.length; i++) {
        if (urls.indexOf(list[i]) < 0) { urls.push(list[i]); }
      }
    }
    for (var t = 0; t < collected.texts.length; t++) {
      pushUrls(airaNovelFontExtractWoff2Urls(collected.texts[t], base));
    }

    var cssTargets = [];
    for (var l = 0; l < collected.linkHrefs.length; l++) {
      var href = collected.linkHrefs[l];
      if (airaNovelFontIsSameOrigin(href, doc)) { cssTargets.push(href); }
    }

    function fetchCssThenFonts() {
      if (cssTargets.length === 0) {
        fetchFonts();
        return;
      }
      var pending = cssTargets.length;
      var done = false;
      function settle() {
        pending--;
        if (pending <= 0 && !done) { done = true; fetchFonts(); }
      }
      for (var c = 0; c < cssTargets.length; c++) {
        (function (target) {
          var attempt;
          try {
            attempt = doFetch(target, { credentials: 'include' });
          } catch (_error) {
            settle();
            return;
          }
          Promise.resolve(attempt).then(function (response) {
            return response.text();
          }).then(function (text) {
            pushUrls(airaNovelFontExtractWoff2Urls(text, target));
            settle();
          }).catch(function () { settle(); });
        })(cssTargets[c]);
      }
    }

    function fetchFonts() {
      if (urls.length === 0) {
        resolve({ ok: false, reason: 'no-font-url', resolved: 0, fontCount: 0 });
        return;
      }
      var candidates = urls.slice(0, AIRA_NOVEL_FONT_MAX_FONTS);
      var merged = {};
      var resolvedCount = 0;
      var parsedCount = 0;
      var pending = candidates.length;
      var finished = false;
      function settle() {
        pending--;
        if (pending <= 0 && !finished) {
          finished = true;
          resolve({
            ok: resolvedCount > 0,
            reason: resolvedCount > 0 ? undefined : 'unresolved',
            map: merged,
            resolved: resolvedCount,
            fontCount: parsedCount
          });
        }
      }
      for (var f = 0; f < candidates.length; f++) {
        (function (fontUrl) {
          var attempt;
          try {
            attempt = doFetch(fontUrl, { credentials: 'include' });
          } catch (_error) {
            settle();
            return;
          }
          Promise.resolve(attempt).then(function (response) {
            return response.arrayBuffer();
          }).then(function (buffer) {
            var parsed = airaNovelFontParseWoff2(new Uint8Array(buffer));
            if (parsed.ok) {
              parsedCount++;
              for (var key in parsed.map) {
                if (!Object.prototype.hasOwnProperty.call(parsed.map, key)) { continue; }
                // First font wins: the fonts for one response agree, and a
                // later sheet must not overwrite a resolved character.
                if (!Object.prototype.hasOwnProperty.call(merged, key)) {
                  merged[key] = parsed.map[key];
                  resolvedCount++;
                }
              }
            }
            settle();
          }).catch(function () { settle(); });
        })(candidates[f]);
      }
    }

    fetchCssThenFonts();
  });
}

/**
 * Share of non-whitespace characters that sit in the CJK Extension B plane or
 * beyond, which is where the substitution fonts draw from.
 */
function airaNovelFontObfuscatedRatio(text) {
  if (!text) { return 0; }
  var total = 0;
  var obfuscated = 0;
  var codes = airaNovelFontCodePoints(text);
  for (var i = 0; i < codes.length; i++) {
    var code = codes[i];
    if (code === 32 || code === 9 || code === 10 || code === 13 ||
      code === 0x3000 || code === 0x00a0) {
      continue;
    }
    total++;
    if (code >= 0x20000) { obfuscated++; }
  }
  if (total === 0) { return 0; }
  return obfuscated / total;
}

function airaNovelFontCountObfuscated(text) {
  var codes = airaNovelFontCodePoints(text || '');
  var count = 0;
  for (var i = 0; i < codes.length; i++) {
    if (codes[i] >= 0x20000) { count++; }
  }
  return count;
}

function airaNovelFontIsObfuscated(text) {
  if (!text) { return false; }
  if (airaNovelFontCountObfuscated(text) < AIRA_NOVEL_FONT_MIN_OBFUSCATED_COUNT) {
    return false;
  }
  return airaNovelFontObfuscatedRatio(text) >= AIRA_NOVEL_FONT_MIN_OBFUSCATED_RATIO;
}

/** Replaces each substituted codepoint with the character the font draws. */
function airaNovelFontDeobfuscate(text, mapping) {
  if (!text || !mapping) { return text; }
  var output = '';
  for (var i = 0; i < text.length; ) {
    var code = text.codePointAt ? text.codePointAt(i) : text.charCodeAt(i);
    if (code === undefined || code !== code) { code = text.charCodeAt(i); }
    var size = code > 0xffff ? 2 : 1;
    var original = text.substr(i, size);
    var replacement = Object.prototype.hasOwnProperty.call(mapping, code)
      ? mapping[code]
      : undefined;
    output += (typeof replacement === 'string' && replacement.length > 0)
      ? replacement
      : original;
    i += size;
  }
  return output;
}

global.__airaNovelFont = {
  version: AIRA_NOVEL_FONT_VERSION,
  parseWoff2: airaNovelFontParseWoff2,
  resolveForDocument: airaNovelFontResolveForDocument,
  isObfuscated: airaNovelFontIsObfuscated,
  obfuscatedRatio: airaNovelFontObfuscatedRatio,
  countObfuscated: airaNovelFontCountObfuscated,
  deobfuscate: airaNovelFontDeobfuscate
};
