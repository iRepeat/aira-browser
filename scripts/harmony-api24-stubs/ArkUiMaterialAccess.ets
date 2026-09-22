class ImmersiveMaterialPlaceholder {
}

export type ImmersiveMaterialHandle = ImmersiveMaterialPlaceholder;
export type ImmersiveStyleHandle = number;

export const IMMERSIVE_STYLE_STANDARD: ImmersiveStyleHandle = 1;
export const IMMERSIVE_STYLE_THICK: ImmersiveStyleHandle = 3;
export const IMMERSIVE_STYLE_ULTRA_THICK: ImmersiveStyleHandle = 4;

class NoopSystemMaterialAttributeModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(_instance: CommonAttribute): void {
  }
}

export function createImmersiveMaterial(
  _style: ImmersiveStyleHandle,
  _materialColor?: ResourceColor,
  _lightEffectColor: ResourceColor | null = null,
  _applyShadow: boolean = true,
  _interactive: boolean = true
): ImmersiveMaterialHandle {
  return new ImmersiveMaterialPlaceholder();
}

export function isKitMaterialEnabled(): boolean {
  return false;
}

export function applyCommonSystemMaterial(
  _instance: CommonAttribute,
  _material: ImmersiveMaterialHandle | undefined
): void {
}

export function systemMaterialModifier(
  _material: ImmersiveMaterialHandle | undefined
): AttributeModifier<CommonAttribute> {
  return new NoopSystemMaterialAttributeModifier();
}

