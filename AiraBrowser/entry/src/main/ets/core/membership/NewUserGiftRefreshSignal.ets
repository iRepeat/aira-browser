export const AIRA_NEW_USER_GIFT_REVISION_KEY: string = 'aira.membership.newUserGift.revision';

/**
 * Shell-observable bump raised when the resolved account identity changes.
 * The New User Gift evaluator listens so a prompt can appear right after a
 * successful sign-in without polling the membership state.
 */
export class NewUserGiftRefreshSignal {
  bump(): number {
    const nextRevision = (AppStorage.get<number>(AIRA_NEW_USER_GIFT_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(AIRA_NEW_USER_GIFT_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}
