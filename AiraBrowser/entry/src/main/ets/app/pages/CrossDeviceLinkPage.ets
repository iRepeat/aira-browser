import { CrossDeviceLinkHost } from '../components/sync/CrossDeviceLinkHost';

/**
 * The page, not the host, owns the page lifecycle: only an @Entry component receives
 * onPageShow, and the host is an ordinary component inside it.
 */
@Entry
@Component
struct CrossDeviceLinkPage {
  @State private refreshToken: number = 0;
  @State private pageVisible: boolean = false;

  onPageShow(): void {
    this.pageVisible = true;
    this.refreshToken += 1;
  }

  onPageHide(): void {
    this.pageVisible = false;
  }

  build() {
    Column() {
      CrossDeviceLinkHost({
        refreshToken: this.refreshToken,
        pageVisible: this.pageVisible
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
