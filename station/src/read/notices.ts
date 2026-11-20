// What the people of a chat hear about while no client of theirs runs (an agent's turn ending in one of the station's
// own chats, something going wrong there, a person saying something there), as the station posts it to still.fail
// cloud (src/cloud/notify.ts). The TypeScript that worked them out of a store change is the tests'
// (test/reference/notices.ts).
export type Notice = { to: string[]; audience?: "managers"; kind: string; session: string; thread: number; seq: number | null; title: string; by: string; text: string; at: number; ws?: string };
