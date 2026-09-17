import { DownloadV2Status } from '../../domain/downloadv2/DownloadV2Types';

export interface DownloadSelectionCandidate {
  guid: string;
  status: DownloadV2Status;
}

export const DOWNLOAD_SELECTION_EMPTY_TOAST: string = '请先选择下载任务。';

export function buildDownloadSelectionTitle(selectedCount: number): string {
  return `已选 ${selectedCount} 项`;
}

/**
 * Only completed downloads can be batched. Active tasks keep their per-row controls
 * (pause/resume/cancel) because a batch action must not race the running transfer.
 */
export function canSelectDownloadTask(status: DownloadV2Status): boolean {
  return status === 'completed';
}

export function collectSelectableDownloadGuids(candidates: DownloadSelectionCandidate[]): string[] {
  const guids: string[] = [];
  candidates.forEach((candidate: DownloadSelectionCandidate) => {
    if (canSelectDownloadTask(candidate.status)) {
      guids.push(candidate.guid);
    }
  });
  return guids;
}

export function pruneDownloadSelection(selectedGuids: string[], selectableGuids: string[]): string[] {
  return selectedGuids.filter((guid: string) => selectableGuids.indexOf(guid) >= 0);
}
