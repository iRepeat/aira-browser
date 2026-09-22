# Phone Page Push Is Independent Of Bookmark Sync

Accepted: Phone Page Push and Bookmark Sync are separate product flows, but Page Push uses the active service Provider.
When the active Provider is Personal Server, the HarmonyOS App authenticates with its paired phone credential and the
paired Aira-sync installations receive the page without Aira Account or Pro. When the active Provider is Aira Cloud, the
existing verified Huawei Account and Pro boundary remains. WebDAV and Huawei Cloud Space do not transport Page Push.

Amended 2026-09-22: the account channel no longer requires the active data-sync provider to be Aira Cloud. A signed-in
Huawei Account on the phone and the same account on Aira-sync are enough for Page Push and cross-device tabs, including
when data sync is off or the selected provider is WebDAV or Huawei Cloud Space. The Pro boundary on that account channel
is unchanged. Personal Server remains its own paired channel and is still selected only when it is the active sync
provider; it does not fall through to the account, and the account channel does not replace it.

Changing the active Provider does not mutate bookmark snapshots, baselines, CAS state, or conflict handling. A valid
pushed webpage immediately opens in a new active desktop tab and is acknowledged through the lease flow, without an
inbox or deferred-delivery UI. Personal Server creates one short-lived task for every paired desktop that is online at
enqueue time; offline devices receive no historical delivery.
