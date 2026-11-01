/** The stored credentials cannot be used; the user must reconnect. */
export class NeedsReauthError extends Error {
  constructor(message = "Reconnect required") {
    super(message);
    this.name = "NeedsReauthError";
  }
}

/** Gmail's startHistoryId is too old. Reset the cursor and do a full sync. */
export class GmailHistoryExpiredError extends Error {
  constructor() {
    super("Gmail history cursor expired");
    this.name = "GmailHistoryExpiredError";
  }
}
