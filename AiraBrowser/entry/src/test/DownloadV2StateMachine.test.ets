import { describe, expect, it } from '@ohos/hypium';
import { transitionDownloadV2Status } from '../main/ets/domain/downloadv2/DownloadV2StateMachine';
import {
  isDownloadV2ActiveStatus,
  isDownloadV2TerminalStatus
} from '../main/ets/domain/downloadv2/DownloadV2Types';

export default function downloadV2StateMachineTest(): void {
  describe('DownloadV2 status transitions', () => {
    // A queued task can be rejected by the download backend before it ever starts (the libcurl
    // adapter refuses any method other than GET). If that failure cannot leave `queued`, the task
    // stays startable forever and the queue drain re-selects it until the main thread is killed for
    // input blocking. This transition is the fix for that crash.
    it('lets a queued task fail before it starts', 0, () => {
      const transition = transitionDownloadV2Status('queued', 'fail');
      expect(transition.valid).assertTrue();
      expect(transition.nextStatus).assertEqual('failed');
      expect(transition.changed).assertTrue();
    });

    it('keeps a failed task recoverable through retry', 0, () => {
      const transition = transitionDownloadV2Status('failed', 'retry');
      expect(transition.valid).assertTrue();
      expect(transition.nextStatus).assertEqual('queued');
    });

    it('treats a failed task as terminal and not startable', 0, () => {
      expect(isDownloadV2TerminalStatus('failed')).assertTrue();
      expect(isDownloadV2ActiveStatus('failed')).assertFalse();
    });

    it('still refuses to fail a task that already reached a terminal status', 0, () => {
      expect(transitionDownloadV2Status('completed', 'fail').valid).assertFalse();
      expect(transitionDownloadV2Status('removed', 'fail').valid).assertFalse();
    });

    it('keeps the ordinary queued lifecycle intact', 0, () => {
      expect(transitionDownloadV2Status('queued', 'start').nextStatus).assertEqual('running');
      expect(transitionDownloadV2Status('queued', 'cancel').nextStatus).assertEqual('canceled');
      expect(transitionDownloadV2Status('queued', 'remove').nextStatus).assertEqual('removed');
    });
  });
}
