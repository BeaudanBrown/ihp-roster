export function assertNever(value: never, message = "Unexpected generated union variant"): never {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
}
