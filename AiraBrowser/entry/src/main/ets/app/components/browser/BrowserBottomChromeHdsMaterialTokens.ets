import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * Immersive light-sense material is only reachable through HDS components. ArkUI's
 * own uiMaterial requires targetSdkVersion 26 plus a Navigation title bar or bottom
 * TabBar scope, neither of which the browser shell has. HDS exposes the same
 * capability at 6.1.0(23), which is the release we build against, so the bottom
 * chrome uses HDS and falls back to the existing blur when the device lacks it.
 */
let cachedHdsBottomMaterialAvailable: boolean | undefined = undefined;

export function isHdsBottomMaterialAvailable(): boolean {
  if (cachedHdsBottomMaterialAvailable !== undefined) {
    return cachedHdsBottomMaterialAvailable;
  }
  try {
    const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    // The query reports which material types this device can actually render. IMMERSIVE is
    // the capability marker in the HDS guidance and ADAPTIVE is the follow-system policy;
    // accept any non-NONE entry so a device that reports either one still gets the material.
    cachedHdsBottomMaterialAvailable = types.some((type: hdsMaterial.MaterialType) =>
      type !== hdsMaterial.MaterialType.NONE);
  } catch (_error) {
    cachedHdsBottomMaterialAvailable = false;
  }
  return cachedHdsBottomMaterialAvailable;
}
