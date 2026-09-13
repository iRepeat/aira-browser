import { HdsTabs, HdsTabsController, HdsTabsFloatingStyle, hdsMaterial } from '@kit.UIDesignKit';

/**
 * Immersive light-sense backplate for any floating chrome cluster.
 *
 * HdsTabs is the only component that exposes the immersive material, so a cluster renders
 * one of these purely as its backplate and draws nothing itself; the cluster keeps owning
 * its content and gestures on the layer above.
 *
 * Geometry notes, both learned the hard way:
 * - The floating style (which carries systemMaterialEffect) only takes effect when
 *   barOverlap is true with vertical false and barPosition End. Dropping barOverlap
 *   disables the material entirely and the plate renders transparent.
 * - A floating bar sizes itself from its tab count, so with a single item it collapses
 *   into a centered sliver. barWidth pins it to the cluster's own width instead.
 */
@Component
export struct HdsImmersiveMaterialSurface {
  @Prop plateWidth: number = 1;
  @Prop plateHeight: number = 1;
  @Prop plateRadius: number = 0;
  @Prop plateOpacity: number = 1;
  private controller: HdsTabsController = new HdsTabsController();

  build() {
    HdsTabs({ controller: this.controller }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.transparentBar)
    }
    .vertical(false)
    .scrollable(false)
    .barMode(BarMode.Fixed)
    .barPosition(BarPosition.End)
    .barOverlap(true)
    .barWidth(this.resolvePlateWidth())
    .barHeight(this.resolvePlateHeight())
    .barBackgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .barFloatingStyle(this.resolveFloatingStyle())
    .width('100%')
    .height('100%')
    .borderRadius(this.plateRadius)
    // Stay clipped to the cluster outline: HDS materializes its bar as a rectangle, so
    // without this the square body leaks past a rounded plate. Anything that needs a drop
    // shadow must draw it on its own unclipped layer.
    .clip(true)
    .opacity(this.plateOpacity)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private transparentBar() {
    // The bar must be physically present so HDS materializes onto it, but it carries no
    // visible content of its own.
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
  }

  private resolvePlateWidth(): number {
    return Math.max(1, this.plateWidth);
  }

  private resolvePlateHeight(): number {
    return Math.max(1, this.plateHeight);
  }

  private resolveFloatingStyle(): HdsTabsFloatingStyle {
    const width: number = this.resolvePlateWidth();
    const style: HdsTabsFloatingStyle = {
      barSideMargin: 0,
      barBottomMargin: 0,
      barOpacity: 1,
      // Symbolic widths are ignored by the floating bar; it needs the concrete vp width,
      // and all three breakpoints must carry it or the capsule falls back to item sizing.
      barWidth: {
        smallWidth: width,
        mediumWidth: width,
        largeWidth: width
      }
    };
    // ADAPTIVE lets the system pick the material strength for the device, which the
    // power guidance recommends over pinning a level per device class.
    style.systemMaterialEffect = {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    return style;
  }
}
