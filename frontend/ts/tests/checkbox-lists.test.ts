import { updateCheckboxList } from '../app-checkbox-lists';
import * as C from '../generated/contracts';
import { assertDeepEqual, assertEqual, test } from './harness';

// Minimal native-state DOM seam; real label/keyboard/form association is also
// covered by the export and Xero browser tests.
class MiniElement {
    parent: MiniElement | null = null;
    children: MiniElement[] = [];
    constructor(readonly attrs: Record<string, string> = {}) {}
    append(...children: MiniElement[]): void {
        for (const child of children) { child.parent = this; this.children.push(child); }
    }
    hasAttribute(name: string): boolean { return name in this.attrs; }
    getAttribute(name: string): string | null { return this.attrs[name] ?? null; }
    closest(selector: string): MiniElement | null {
        return this.hasAttribute(selector.slice(1, -1)) ? this : this.parent?.closest(selector) ?? null;
    }
    querySelectorAll(selector: string): MiniElement[] {
        return this.children.flatMap(child => [
            ...(child.hasAttribute(selector.slice(1, -1)) ? [child] : []),
            ...child.querySelectorAll(selector),
        ]);
    }
}
class MiniInput extends MiniElement { type = 'checkbox'; checked = false; indeterminate = false; }
class MiniOutput extends MiniElement { value = '0'; }
class MiniButton extends MiniElement { disabled = true; }
class MiniForm extends MiniElement { elements: MiniElement[] = []; }

function withDom(run: () => void): void {
    const classes = { HTMLFormElement: MiniForm, HTMLInputElement: MiniInput, HTMLOutputElement: MiniOutput, HTMLButtonElement: MiniButton };
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

function fixture() {
    const form = new MiniForm({ [C.checkboxListRootDomAttr]: 'true' });
    const group = new MiniElement({ [C.checkboxListGroupDomAttr]: 'true' });
    const toggle = new MiniInput({ [C.checkboxListGroupToggleDomAttr]: 'true' });
    const item = (weight: string) => new MiniInput({ [C.checkboxListItemDomAttr]: 'true', [C.checkboxListWeightDomAttr]: weight });
    const a = item('0.1');
    const b = item('0.2');
    const c = item('2');
    const all = new MiniButton({ [C.checkboxListSelectAllDomAttr]: 'true' });
    const clear = new MiniButton({ [C.checkboxListClearAllDomAttr]: 'true' });
    const count = new MiniOutput({ [C.checkboxListCountDomAttr]: 'true' });
    const total = new MiniOutput({ [C.checkboxListTotalDomAttr]: 'true' });
    const submit = new MiniButton({ [C.checkboxListSubmitDomAttr]: 'true' });
    group.append(toggle, a, b);
    form.append(group, c, all, clear, count, total);
    // The footer is outside the form DOM but belongs to its native elements.
    form.elements = [toggle, a, b, c, submit];
    return { form, group, toggle, a, b, c, all, clear, count, total, submit };
}
const update = (target: MiniElement) => updateCheckboxList(target as unknown as Element);

test('checkbox lists synchronize groups, totals and external footer controls locally', () => withDom(() => {
    const f = fixture();
    update(f.all);
    assertDeepEqual([f.a.checked, f.b.checked, f.c.checked, f.toggle.checked], [true, true, true, true]);
    assertDeepEqual([f.count.value, f.total.value, f.submit.disabled], ['3', '2.3', false]);
    update(f.clear);
    assertDeepEqual([f.a.checked, f.b.checked, f.c.checked, f.toggle.checked], [false, false, false, false]);
    assertDeepEqual([f.count.value, f.total.value, f.submit.disabled], ['0', '0', true]);
}));

test('checkbox lists keep partial days unchecked and toggle only their own children', () => withDom(() => {
    const f = fixture();
    f.toggle.checked = true;
    update(f.toggle);
    assertDeepEqual([f.a.checked, f.b.checked, f.c.checked, f.total.value], [true, true, false, '0.3']);
    f.b.checked = false;
    update(f.b);
    assertEqual(f.toggle.checked, false);
    assertEqual(f.toggle.indeterminate, false);
    f.b.checked = true;
    update(f.b);
    assertEqual(f.toggle.checked, true);
    f.c.checked = true;
    f.toggle.checked = false;
    update(f.toggle);
    assertDeepEqual([f.a.checked, f.b.checked, f.c.checked, f.total.value], [false, false, true, '2']);
}));

test('checkbox lists never traverse a nested root or an unrelated form', () => withDom(() => {
    const outer = fixture();
    const inner = fixture();
    outer.form.append(inner.form);
    // Malformed nested data must neither invalidate nor be modified by outer actions.
    inner.a.attrs[C.checkboxListWeightDomAttr] = 'invalid';
    update(outer.all);
    assertEqual(outer.count.value, '3');
    assertEqual(inner.a.checked, false);
    assertEqual(inner.submit.disabled, true);
    const unrelated = fixture();
    update(unrelated.all);
    assertEqual(inner.count.value, '0');
}));

test('checkbox lists leave malformed controls untouched before group effects', () => withDom(() => {
    for (const weight of ['', 'invalid', '-1', 'Infinity']) {
        const f = fixture();
        f.a.attrs[C.checkboxListWeightDomAttr] = weight;
        update(f.all);
        assertDeepEqual([f.a.checked, f.b.checked, f.count.value, f.submit.disabled], [false, false, '0', true]);
    }
    for (const role of [C.checkboxListGroupToggleDomAttr, C.checkboxListItemDomAttr, C.checkboxListTotalDomAttr]) {
        const f = fixture();
        f.form.append(new MiniElement({ [role]: 'true' }));
        update(f.all);
        assertEqual(f.a.checked, false);
        assertEqual(f.count.value, '0');
    }
}));
