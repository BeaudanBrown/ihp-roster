export class MiniClassList {
    private readonly values = new Set<string>();

    constructor(initial: readonly string[] = [], private readonly changed: (value: string) => void = () => undefined) {
        initial.forEach((value) => this.values.add(value));
    }

    add(...values: string[]): void {
        values.forEach((value) => this.values.add(value));
        this.changed(this.toString());
    }

    remove(...values: string[]): void {
        values.forEach((value) => this.values.delete(value));
        this.changed(this.toString());
    }

    toggle(value: string, force?: boolean): boolean {
        const enabled = force ?? !this.values.has(value);
        if (enabled) this.values.add(value);
        else this.values.delete(value);
        this.changed(this.toString());
        return enabled;
    }

    contains(value: string): boolean {
        return this.values.has(value);
    }

    toString(): string {
        return Array.from(this.values).join(" ");
    }
}

export class MiniElement extends EventTarget {
    readonly children: MiniElement[] = [];
    readonly classList: MiniClassList;
    parentElement: MiniElement | null = null;
    id: string;
    value: string;
    textContent: string | null = null;
    readonly tagName: string;
    focusCount = 0;
    blurCount = 0;
    clickCount = 0;
    private readonly attrs = new Map<string, string>();

    constructor(
        attrs: Record<string, string> = {},
        id = "",
        classes: readonly string[] = [],
        tagName = "div",
    ) {
        super();
        this.id = id || attrs.id || "";
        this.value = attrs.value || "";
        this.tagName = tagName.toUpperCase();
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
        const initialClasses = [...classes, ...(attrs.class?.split(/\s+/).filter(Boolean) ?? [])];
        this.classList = new MiniClassList(initialClasses, (value) => {
            if (value) this.attrs.set("class", value);
            else this.attrs.delete("class");
        });
    }

    get parent(): MiniElement | null {
        return this.parentElement;
    }

    get parentNode(): MiniElement | null {
        return this.parentElement;
    }

    get attributes(): Array<{ name: string; value: string }> {
        return Array.from(this.attrs, ([name, value]) => ({ name, value }));
    }

    append<T extends MiniElement>(child: T): T {
        return this.appendChild(child);
    }

    appendChild<T extends MiniElement>(child: T): T {
        child.parentElement?.removeChild(child);
        child.parentElement = this;
        this.children.push(child);
        return child;
    }

    removeChild<T extends MiniElement>(child: T): T {
        const index = this.children.indexOf(child);
        if (index >= 0) this.children.splice(index, 1);
        child.parentElement = null;
        return child;
    }

    replaceChildren(...children: MiniElement[]): void {
        this.children.forEach((child) => { child.parentElement = null; });
        this.children.length = 0;
        children.forEach((child) => this.append(child));
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
        if (name === "id") this.id = value;
        if (name === "value") this.value = value;
    }

    removeAttribute(name: string): void {
        this.attrs.delete(name);
        if (name === "id") this.id = "";
        if (name === "value") this.value = "";
    }

    matches(selector: string): boolean {
        return selector.split(",").some((part) => this.matchesOne(part.trim()));
    }

    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) {
            if (current.matches(selector)) return current;
            current = current.parentElement;
        }
        return null;
    }

    querySelectorAll<T extends MiniElement = MiniElement>(selector: string): T[] {
        const found: MiniElement[] = [];
        const visit = (owner: MiniElement) => {
            owner.children.forEach((child) => {
                if (child.matches(selector)) found.push(child);
                visit(child);
            });
        };
        visit(this);
        return found as T[];
    }

    querySelector<T extends MiniElement = MiniElement>(selector: string): T | null {
        return this.querySelectorAll<T>(selector)[0] ?? null;
    }

    contains(candidate: MiniElement): boolean {
        return candidate === this || this.children.some((child) => child.contains(candidate));
    }

    focus(): void {
        this.focusCount += 1;
    }

    blur(): void {
        this.blurCount += 1;
    }

    click(): void {
        this.clickCount += 1;
    }

    private matchesOne(selector: string): boolean {
        if (selector === "*") return true;
        const attribute = selector.match(/^\[([^\]=]+)(?:="([^"]*)")?\]$/);
        if (attribute) {
            const value = this.getAttribute(attribute[1] ?? "");
            return value !== null && (attribute[2] === undefined || value === attribute[2]);
        }
        const className = selector.match(/^\.([A-Za-z0-9_-]+)$/)?.[1];
        if (className) return this.classList.contains(className);
        return this.tagName.toLowerCase() === selector.toLowerCase();
    }
}
