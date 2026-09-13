import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * Immersive light-sense material is only reachable through HDS components. ArkUI's own
 * uiMaterial requires a targetSdkVersion of 26 plus a Navigation title bar or bottom TabBar
 * scope; this app targets 23 and builds its own chrome, so uiMaterial silently paints
 * nothing. HDS exposes the same capability from 6.1.0(23), which is the release we build
 * against, so every floating surface routes through HDS and keeps its own fill when the
 * device cannot render the material.
 */
let cachedHdsMaterialAvailable: boolean | undefined = undefined;

export function isHdsMaterialAvailable(): boolean {
  if (cachedHdsMaterialAvailable !== undefined) {
    return cachedHdsMaterialAvailable;
  }
  try {
    const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    // The query reports which material types this device can actually render. IMMERSIVE is
    // the capability marker in the HDS guidance and ADAPTIVE is the follow-system policy;
    // accept any non-NONE entry so a device that reports either one still gets the material.
    cachedHdsMaterialAvailable = types.some((type: hdsMaterial.MaterialType) =>
      type !== hdsMaterial.MaterialType.NONE);
  } catch (_error) {
    cachedHdsMaterialAvailable = false;
  }
  return cachedHdsMaterialAvailable;
}
