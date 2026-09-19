import { CrossDeviceLinkSetupScreen } from '../components/sync/CrossDeviceLinkSetupScreen';

@Entry
@Component
struct CrossDeviceLinkSetupPage {
  @State private refreshToken: number = 0;

  onPageShow(): void {
    this.refreshToken += 1;
  }

  build() {
    Column() {
      Column() {
        CrossDeviceLinkSetupScreen({ refreshToken: this.refreshToken })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
