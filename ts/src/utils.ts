export function assertExhausted(v: never) {
  throw new TypeError(`Unhandled case: ${JSON.stringify(v)}`) };
