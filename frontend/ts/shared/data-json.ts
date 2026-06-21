export type JsonScriptElement = {
    textContent: string | null;
    type: string;
};

export type JsonScriptRoot = {
    querySelector(selector: string): JsonScriptElement | null;
};

export function readJsonScriptElement<T>(root: JsonScriptRoot, selector: string): T | null {
    const element = root.querySelector(selector);
    if (element === null) {
        return null;
    }

    if (element.type !== "application/json") {
        throw new Error(`Expected ${selector} to be an application/json script`);
    }

    const text = element.textContent;
    if (text === null || text.trim() === "") {
        return null;
    }

    return JSON.parse(text) as T;
}
