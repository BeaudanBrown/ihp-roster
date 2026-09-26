#!/usr/bin/env python3
"""Native runner scheduling policy: whole Playwright file/project groups."""
import copy
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class GroupingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = subprocess.check_output([str(ROOT / 'bin/tooling-run'), 'runners', '--print-binary'], text=True).strip()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='bepis-e2e-grouping-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def fixture(self):
        groups = [('a.spec.ts', 3, 9000), ('b.spec.ts', 1, 8000), ('c.spec.ts', 1, 5000), ('d.spec.ts', 1, 4000), ('e.spec.ts', 1, 1000)]
        inventory = {'config': {'fullyParallel': False, 'projects': [{'name': 'desktop', 'id': 'desktop', 'repeatEach': 1, 'retries': 1}]}, 'suites': [
            {'specs': [{'id': f'{file}-{index}', 'file': file, 'tests': [{'projectName': 'desktop'}]} for index in range(count)]}
            for file, count, _ in groups]}
        durations = {'schemaVersion': 1, 'groups': [{'file': file, 'project': 'desktop', 'testCount': count, 'milliseconds': duration} for file, count, duration in groups]}
        return inventory, durations

    def plan(self, inventory, durations, shards=2):
        (self.root / 'inventory.json').write_text(json.dumps(inventory))
        (self.root / 'durations.json').write_text(json.dumps(durations))
        return subprocess.run([self.runner, 'e2e-groups', '--shards', str(shards), '--inventory', str(self.root / 'inventory.json'), '--durations', str(self.root / 'durations.json')], text=True, capture_output=True, timeout=15)

    def test_exact_membership_whole_groups_and_deterministic_duration_assignment(self):
        inventory, durations = self.fixture()
        result = self.plan(inventory, durations)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual((plan['testCount'], plan['groupCount']), (7, 5))
        self.assertEqual([s['estimatedMilliseconds'] for s in plan['shards']], [14000, 13000])
        self.assertEqual(plan['shards'][0]['selectors'], ['[desktop] › a.spec.ts', '[desktop] › d.spec.ts', '[desktop] › e.spec.ts'])
        self.assertEqual(plan['shards'][1]['selectors'], ['[desktop] › b.spec.ts', '[desktop] › c.spec.ts'])
        actual = [identifier for shard in plan['shards'] for group in shard['groups'] for identifier in group['testIds']]
        self.assertEqual(sorted(actual), sorted(spec['id'] for suite in inventory['suites'] for spec in suite['specs']))
        inventory['suites'].reverse()
        durations['groups'].reverse()
        self.assertEqual(json.loads(self.plan(inventory, durations).stdout), plan)

    def test_new_groups_and_changed_counts_never_drop_membership(self):
        inventory, durations = self.fixture()
        inventory['suites'][0]['specs'].append({'id': 'new-a', 'file': 'a.spec.ts', 'tests': [{'projectName': 'desktop'}]})
        inventory['config']['projects'].append({'name': 'mobile'})
        inventory['suites'].append({'suites': [{'specs': [{'id': 'new-mobile', 'file': 'a.spec.ts', 'tests': [{'projectName': 'mobile'}]}]}]})
        durations['groups'].append({'file': 'retired.spec.ts', 'project': 'desktop', 'testCount': 1, 'milliseconds': 99999})
        result = self.plan(inventory, durations)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual((plan['testCount'], plan['groupCount']), (9, 6))
        groups = {(g['project'], g['file']): g for shard in plan['shards'] for g in shard['groups']}
        self.assertEqual(groups['desktop', 'a.spec.ts']['estimatedMilliseconds'], 12000)
        self.assertEqual(groups['mobile', 'a.spec.ts']['estimatedMilliseconds'], 3000)
        self.assertNotIn(('desktop', 'retired.spec.ts'), groups)

    def test_malformed_or_unsafe_membership_and_policy_fail_closed(self):
        original, baseline = self.fixture()
        mutations = [
            lambda i, d: i['suites'][0]['specs'].append(copy.deepcopy(i['suites'][0]['specs'][0])),
            lambda i, d: i['suites'][0]['specs'][0].update(file='../escape.spec.ts'),
            lambda i, d: i['suites'][0]['specs'][0].update(file='x//y.spec.ts'),
            lambda i, d: i['suites'][0]['specs'][0]['tests'][0].update(projectName='unknown'),
            lambda i, d: i.update(errors=[{'message': 'discovery failure'}]),
            lambda i, d: i['config'].update(fullyParallel=True),
            lambda i, d: i['config']['projects'][0].update(repeatEach=2),
            lambda i, d: i['config']['projects'][0].update(dependencies=['setup']),
            lambda i, d: d['groups'].append(copy.deepcopy(d['groups'][0])),
            lambda i, d: d['groups'][0].update(milliseconds=0),
            lambda i, d: d['groups'][0].update(testCount=0),
            lambda i, d: d.update(schemaVersion=2),
            lambda i, d: i.update(suites=[]),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                inventory, durations = copy.deepcopy(original), copy.deepcopy(baseline)
                mutate(inventory, durations)
                self.assertNotEqual(self.plan(inventory, durations).returncode, 0)
        for shards in [0, 6, 9]:
            self.assertNotEqual(self.plan(original, baseline, shards).returncode, 0)

    def test_real_playwright_selectors_preserve_serial_hooks_cleanup_and_retry_reporting(self):
        module = str(Path(os.environ['E2E_PLAYWRIGHT_NODE_MODULES']) / '@playwright/test/index.js')
        (self.root / 'playwright.config.cjs').write_text("module.exports={testDir:__dirname,workers:1,retries:1,projects:[{name:'one'},{name:'two'}],reporter:'json'};")
        (self.root / 'serial.spec.cjs').write_text('''const {test,expect}=require(MODULE);
const fs=require('fs'),path=require('path');let marker;
test.describe.configure({mode:'serial'});
test.beforeAll(async({},info)=>{marker=path.join(__dirname,info.project.name+'.state');fs.writeFileSync(marker,'ready');fs.appendFileSync(path.join(__dirname,'hooks.log'),'start:'+info.project.name+'\\n');});
test.afterAll(async({},info)=>{fs.unlinkSync(marker);fs.appendFileSync(path.join(__dirname,'hooks.log'),'stop:'+info.project.name+'\\n');});
test('first',()=>{expect(fs.readFileSync(marker,'utf8')).toBe('ready');fs.writeFileSync(marker,'first');});
test('second',()=>{expect(fs.readFileSync(marker,'utf8')).toBe('first');});
'''.replace('MODULE', json.dumps(module)))
        (self.root / 'retry.spec.cjs').write_text('''const {test,expect}=require(MODULE);
test('retry remains visible',async({},info)=>{expect(process.env.GROUPING_ALWAYS_FAIL ? 0 : info.retry).toBe(1);});
'''.replace('MODULE', json.dumps(module)))
        command = ['playwright', 'test', '--config', str(self.root / 'playwright.config.cjs')]
        inventory = json.loads(subprocess.check_output([*command, '--list'], text=True, cwd=self.root))
        result = self.plan(inventory, {'schemaVersion': 1, 'groups': []})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan['testCount'], 6)
        for shard in plan['shards']:
            selection = self.root / f"shard-{shard['index']}.txt"
            selection.write_text('\n'.join(shard['selectors']) + '\n')
            result = subprocess.run([*command, '--test-list', str(selection)], cwd=self.root, text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual((report['stats']['expected'], report['stats']['flaky'], report['stats']['unexpected']), (2, 1, 0))
        self.assertEqual(sorted((self.root / 'hooks.log').read_text().splitlines()), ['start:one', 'start:two', 'stop:one', 'stop:two'])
        self.assertEqual(list(self.root.glob('*.state')), [])
        result = subprocess.run([*command, '--test-list', str(self.root / 'shard-2.txt')], cwd=self.root, env=dict(os.environ, GROUPING_ALWAYS_FAIL='1'), text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)['stats']['unexpected'], 1)
        self.assertEqual(list(self.root.glob('*.state')), [])


if __name__ == '__main__':
    unittest.main()
