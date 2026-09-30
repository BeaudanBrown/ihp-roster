import { clipFilterSelectionOptions, updateFilterSelection } from '../app-filter-selection';
import * as C from '../generated/contracts';
import { assertEqual, test } from './harness';

class Node {
    parent: Node | null = null;
    children: Node[] = [];
    hidden = false;
    textContent = '';
    constructor(readonly attrs: string[] = []) {}
    hasAttribute(name: string): boolean { return this.attrs.includes(name); }
    append(...children: Node[]): void { for (const child of children) { child.parent = this; this.children.push(child); } }
    closest(selector: string): Node | null {
        return this.hasAttribute(selector.slice(1, -1)) ? this : this.parent?.closest(selector) ?? null;
    }
    querySelectorAll(selector: string): Node[] {
        return this.children.flatMap(child => [
            ...(child.hasAttribute(selector.slice(1, -1)) ? [child] : []), ...child.querySelectorAll(selector),
        ]);
    }
}
class Checkbox extends Node { type = 'checkbox'; checked = false; }
function fixture() {
    const root = new Node([C.filterSelectionSectionDomAttr]);
    const first = new Checkbox([C.filterSelectionItemDomAttr]);
    const second = new Checkbox([C.filterSelectionItemDomAttr]);
    const all = new Node([C.filterSelectionAllDomAttr]);
    const selected = new Node([C.filterSelectionSelectedDomAttr]);
    const count = new Node([C.filterSelectionCountDomAttr]);
    const clear = new Node([C.filterSelectionClearDomAttr]);
    root.append(first, second, all, selected, count, clear);
    return { root, first, second, all, selected, count, clear };
}
function withDom(run: () => void): void {
    const classes = { HTMLElement: Node, HTMLInputElement: Checkbox, CSS: { escape: (value: string) => value } };
    const saved = Object.keys(classes).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const);
    try {
        for (const [key, value] of Object.entries(classes)) Object.defineProperty(globalThis, key, { configurable: true, value });
        run();
    } finally {
        for (const [key, descriptor] of saved) {
            if (descriptor === undefined) Reflect.deleteProperty(globalThis, key);
            else Object.defineProperty(globalThis, key, descriptor);
        }
    }
}
const update = (node: Node) => updateFilterSelection(node as unknown as Element);

test('filter options clip below the sticky heading and restore at their resting position', () => withDom(() => {
    let top = -100;
    const button = Object.assign(new Node(), {
        getAttribute: () => 'choices',
        getBoundingClientRect: () => ({ bottom: 50 }),
    });
    const content = Object.assign(new Node(), {
        style: { clipPath: '' },
        getBoundingClientRect: () => ({ top, height: 400 }),
    });
    const section = { querySelector: (selector: string) => selector === 'button[aria-controls]' ? button : content };
    const clip = () => clipFilterSelectionOptions(section as unknown as Element);
    clip();
    assertEqual(content.style.clipPath, 'inset(150px 0 0)');
    top = 50;
    clip();
    assertEqual(content.style.clipPath, '');
    top = -500;
    clip();
    assertEqual(content.style.clipPath, 'inset(400px 0 0)');
}));

test('filter selection updates count and All from native checkboxes without submitting', () => withDom(() => {
    const f = fixture();
    f.first.checked = true;
    f.second.checked = true;
    update(f.second);
    assertEqual(f.count.textContent, '2');
    assertEqual(f.all.hidden, true);
    assertEqual(f.selected.hidden, false);
    update(f.clear);
    assertEqual(f.first.checked, false);
    assertEqual(f.second.checked, false);
    assertEqual(f.count.textContent, '0');
    assertEqual(f.all.hidden, false);
    assertEqual(f.selected.hidden, true);
}));

test('filter selection isolates sibling and nested sections', () => withDom(() => {
    const outer = fixture();
    const inner = fixture();
    outer.root.append(inner.root);
    inner.first.checked = true;
    outer.first.checked = true;
    update(outer.first);
    assertEqual(outer.count.textContent, '1');
    update(outer.clear);
    assertEqual(inner.first.checked, true);
}));

test('filter selection leaves malformed roots and checkbox roles untouched', () => withDom(() => {
    const f = fixture();
    f.first.checked = true;
    f.second.type = 'text';
    update(f.clear);
    assertEqual(f.first.checked, true);
    update(new Node());
}));
