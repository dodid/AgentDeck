export class RelayTransportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RelayTransportError";
  }
}

export class PreconditionFailedError extends RelayTransportError {
  constructor(message = "PreconditionFailed") {
    super(message);
    this.name = "PreconditionFailedError";
  }
}

export class CASRetryExceededError extends RelayTransportError {
  constructor(message = "Failed to append message after CAS retries") {
    super(message);
    this.name = "CASRetryExceededError";
  }
}
