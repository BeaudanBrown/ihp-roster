import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, truncateSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

const recorder = new URL('./verification-measure.py', import.meta.url).pathname;
function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), 'bepis-verification-measure-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    return join(root, 'run');
}
function run(output, code, options = {}) {
    return spawnSync('python3', [recorder, 'run', '--output', output,
        '--owner', 'fixture', '--cache-state', 'retained', '--', 'python3', '-c', code],
    { encoding: 'utf8', timeout: 10_000, ...options });
}

test('records real command duration and exit without persisting arguments or output', (t) => {
    const output = fixture(t);
    const secret = 'private-fixture-value-not-for-artifacts';
    const result = run(output, `import time; print('${secret}'); time.sleep(0.15)`);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(secret));
    const evidence = JSON.parse(readFileSync(join(output, 'result.json'), 'utf8'));
    assert.equal(evidence.commandStatus, 'passed');
    assert.equal(evidence.exitCode, 0);
    assert.ok(evidence.wallSeconds >= 0.15);
    assert.equal(evidence.measurementStatus, 'complete');
    assert.equal(evidence.authority, 'diagnostic-only');
    assert.equal(inspect(output).status, 0);
    assert.doesNotMatch(readFileSync(join(output, 'metadata.json'), 'utf8'), new RegExp(secret));
    assert.doesNotMatch(JSON.stringify(evidence), new RegExp(secret));
});

function inspect(output) {
    return spawnSync('python3', [recorder, 'inspect', output], { encoding: 'utf8', timeout: 10_000 });
}

test('captures dirty and generated input changes without persisting paths or contents', (t) => {
    const root = fixture(t);
    mkdirSync(root);
    const git = (...args) => {
        const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
        assert.equal(result.status, 0, result.stderr);
    };
    git('init', '-q');
    writeFileSync(join(root, '.gitignore'), 'capture-*/\nbuild/\nfrontend/\n');
    writeFileSync(join(root, 'private-source-name'), 'initial-private-content');
    git('add', '.');
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
    mkdirSync(join(root, 'build/Generated'), { recursive: true });
    writeFileSync(join(root, 'build/Generated/Types.hs'), 'initial generated source');
    const capture = (name) => {
        const output = join(root, `capture-${name}`);
        const result = run(output, 'pass', { cwd: root });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(inspect(output).status, 0);
        return readFileSync(join(output, 'provenance.json'), 'utf8');
    };
    const clean = JSON.parse(capture('clean'));
    assert.equal(clean.dirty, false);
    assert.equal(clean.untracked.files, 0);
    assert.equal(clean.generatedHaskell.files, 1);
    assert.equal(clean.generatedFrontend.state, 'absent');
    writeFileSync(join(root, 'private-source-name'), 'modified-private-content');
    writeFileSync(join(root, 'private-untracked-name'), 'untracked-private-content');
    writeFileSync(join(root, 'build/Generated/Types.hs'), 'changed generated source');
    const raw = capture('dirty');
    const dirty = JSON.parse(raw);
    assert.equal(dirty.dirty, true);
    assert.notEqual(dirty.trackedDiffSha256, clean.trackedDiffSha256);
    assert.equal(dirty.untracked.files, 1);
    assert.notEqual(dirty.untracked.sha256, clean.untracked.sha256);
    assert.notEqual(dirty.generatedHaskell.sha256, clean.generatedHaskell.sha256);
    assert.doesNotMatch(raw, /private-(source|untracked)-name|private-content|generated source/);
});

test('missing Git provenance is unavailable, never reported as clean', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass', { cwd: dirname(output) }).status, 0);
    const provenance = JSON.parse(readFileSync(join(output, 'provenance.json')));
    assert.equal(provenance.dirty, null);
    assert.equal(provenance.trackedDiffSha256, null);
    assert.equal(provenance.untracked.state, 'unavailable');
    assert.equal(provenance.generatedHaskell.state, 'unavailable');
    assert.equal(inspect(output).status, 0);
    for (const invalid of [{ ...provenance, dirty: 'false' },
        { ...provenance, untracked: { state: 'captured', files: 0, sha256: null } }]) {
        writeFileSync(join(output, 'provenance.json'), JSON.stringify(invalid));
        assert.equal(inspect(output).status, 2);
    }
    rmSync(join(output, 'provenance.json'));
    assert.equal(inspect(output).status, 2);
});

test('oversized and symlinked source inputs are unavailable rather than partially fingerprinted', (t) => {
    const output = fixture(t);
    const root = dirname(output);
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: root }).status, 0);
    const oversized = join(root, 'large-private-input');
    writeFileSync(oversized, '');
    truncateSync(oversized, 16 * 1024 * 1024 + 1);
    mkdirSync(join(root, 'build'));
    mkdirSync(join(root, 'elsewhere'));
    symlinkSync(join(root, 'elsewhere'), join(root, 'build/Generated'));
    assert.equal(run(output, 'pass', { cwd: root }).status, 0);
    const provenance = JSON.parse(readFileSync(join(output, 'provenance.json')));
    assert.equal(provenance.dirty, true);
    assert.equal(provenance.untracked.state, 'unavailable');
    assert.equal(provenance.untracked.sha256, null);
    assert.equal(provenance.generatedHaskell.state, 'unavailable');
    assert.equal(inspect(output).status, 0);
});

test('records monotonic owner phase boundaries through the command interface', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys,time\nevent=[sys.executable,${JSON.stringify(recorder)},'event','--phase','compile','--scope','0','--edge']\nsubprocess.run(event+['start'],check=True)\ntime.sleep(0.1)\nsubprocess.run(event+['finish'],check=True)`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.state, 'observed');
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].phase, 'compile');
    assert.equal(phases.intervals[0].status, 'finished');
    assert.ok(phases.intervals[0].durationSeconds >= 0.1);
    assert.equal(inspect(output).status, 0);
    rmSync(join(output, 'events', '000.json'));
    assert.equal(inspect(output).status, 2);
});

test('stdlib-only phase CLI preserves option syntax and rejects invalid boundaries', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys\nbase=[sys.executable,'-S',${JSON.stringify(recorder)},'event']\nassert subprocess.run(base+['--help'],capture_output=True).returncode==0\nassert subprocess.run(base+['--scope=0','--edge=start','--phase=compile']).returncode==0\nassert subprocess.run(base+['--phase','compile','--edge','finish','--scope','0']).returncode==0\nfor extra in (['--scope','-1'],['--scope','65536'],['--edge','unknown'],['--unknown'],['unexpected']):\n p=subprocess.run(base+['--phase','compile','--scope','0','--edge','start']+extra,capture_output=True)\n assert p.returncode==2\n assert len(p.stderr)<4096`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].status, 'finished');
    assert.equal(inspect(output).status, 0);
});

test('service readiness is a recorded boundary distinct from merely starting a process', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys,time\nbase=[sys.executable,'-S',${JSON.stringify(recorder)},'event','--phase','e2e-app-startup','--scope','1','--edge']\nsubprocess.run(base+['start'],check=True)\ntime.sleep(0.1)\nsubprocess.run(base+['ready'],check=True)`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].status, 'ready');
    assert.ok(phases.intervals[0].durationSeconds >= 0.1);
    assert.equal(inspect(output).status, 0);
});

test('reaped service failures close only unfinished startup intervals', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys\nbase=[sys.executable,'-S',${JSON.stringify(recorder)},'event']\nfor phase,scope,ready in [('e2e-worker-startup',1,False),('e2e-stripe-startup',1,False),('e2e-stripe-startup',2,True)]:\n args=base+['--phase',phase,'--scope',str(scope)]\n subprocess.run(args+['--edge','start'],check=True)\n producer=subprocess.Popen([sys.executable,'-c','pass']); producer.wait()\n if ready: subprocess.run(args+['--edge','ready'],check=True)\n for _ in range(2): subprocess.run(args+['--edge','fail','--if-unfinished'],check=True)`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.deepEqual(phases.intervals.map((item) => item.status), ['failed', 'failed', 'ready']);
    assert.equal(inspect(output).status, 0);
});

test('MailHog readiness observes HTTP and SMTP without sending a message', (t) => {
    const output = fixture(t);
    const result = run(output, `import http.server,os,socket,subprocess,sys,threading,time\nclass Handler(http.server.BaseHTTPRequestHandler):\n def do_GET(self):\n  assert self.path=='/api/v2/messages?limit=0'\n  self.send_response(200); self.end_headers()\n def log_message(self,*args): pass\nhttp=http.server.HTTPServer(('127.0.0.1',0),Handler)\nsmtp=socket.socket(); smtp.bind(('127.0.0.1',0)); smtp.listen(); smtp.settimeout(2)\nquit_commands=[]\ndef smtp_ready():\n time.sleep(0.15)\n connection,_=smtp.accept()\n with connection:\n  connection.settimeout(2)\n  connection.sendall(b'220 fixture ready\\r\\n')\n  quit_commands.append(connection.recv(256))\nt=threading.Thread(target=smtp_ready,daemon=True); t.start()\nthreading.Thread(target=http.serve_forever,daemon=True).start()\nbase=[sys.executable,'-S',${JSON.stringify(recorder)}]\nsubprocess.run(base+['event','--phase','e2e-mailhog-startup','--scope','0','--edge','start'],check=True)\nsubprocess.run(base+['watch-mailhog','--http-port',str(http.server_port),'--smtp-port',str(smtp.getsockname()[1]),'--pid',str(os.getpid()),'--timeout-seconds','2'],check=True)\nt.join(); assert quit_commands==[b'QUIT\\r\\n']\nhttp.shutdown(); smtp.close()`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals.length, 1);
    assert.equal(phases.intervals[0].status, 'ready');
    assert.equal(inspect(output).status, 0);
});

test('MailHog observation timeout stays unfinished when only HTTP is ready', (t) => {
    const output = fixture(t);
    const result = run(output, `import http.server,os,socket,subprocess,sys,threading\nclass Handler(http.server.BaseHTTPRequestHandler):\n def do_GET(self): self.send_response(200); self.end_headers()\n def log_message(self,*args): pass\nhttp=http.server.HTTPServer(('127.0.0.1',0),Handler)\nthreading.Thread(target=http.serve_forever,daemon=True).start()\nsmtp=socket.socket(); smtp.bind(('127.0.0.1',0)); smtp.listen()\nbase=[sys.executable,'-S',${JSON.stringify(recorder)}]\nsubprocess.run(base+['event','--phase','e2e-mailhog-startup','--scope','0','--edge','start'],check=True)\nassert subprocess.run(base+['watch-mailhog','--http-port',str(http.server_port),'--smtp-port',str(smtp.getsockname()[1]),'--pid',str(os.getpid()),'--timeout-seconds','0.1']).returncode==2\nhttp.shutdown(); smtp.close()`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals[0].status, 'unfinished');
    assert.equal(phases.intervals[0].durationSeconds, null);
    assert.equal(inspect(output).status, 0);
});

test('MailHog producer death is distinguished from readiness timeout', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys\nbase=[sys.executable,'-S',${JSON.stringify(recorder)}]\nsubprocess.run(base+['event','--phase','e2e-mailhog-startup','--scope','0','--edge','start'],check=True)\nassert subprocess.run(base+['watch-mailhog','--http-port','9','--smtp-port','9','--pid','2147483647']).returncode==1`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.intervals[0].status, 'failed');
    assert.equal(inspect(output).status, 0);
});

test('concurrent phase producers retain separate scopes without taking over events', (t) => {
    const output = fixture(t);
    const child = `import subprocess,sys,time\nevent=[sys.executable,${JSON.stringify(recorder)},'event','--phase','hspec-execution','--scope',sys.argv[1],'--edge']\nsubprocess.run(event+['start'],check=True)\ntime.sleep(0.1)\nsubprocess.run(event+['finish'],check=True)`;
    const result = run(output, `import subprocess,sys\nchildren=[subprocess.Popen([sys.executable,'-c',${JSON.stringify(child)},str(i)]) for i in (1,2)]\nassert all(p.wait()==0 for p in children)`);
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.state, 'observed');
    assert.deepEqual(phases.intervals.map(row => row.scope).sort(), [1, 2]);
    assert.ok(phases.intervals.every(row => row.status === 'finished' && row.durationSeconds >= 0.1));
    assert.equal(inspect(output).status, 0);
});

test('failed commands preserve explicitly failed and unfinished phases without inventing durations', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys\nbase=[sys.executable,${JSON.stringify(recorder)},'event']\nsubprocess.run(base+['--phase','compile','--scope','0','--edge','start'],check=True)\nfor edge in ('start','fail'):\n subprocess.run(base+['--phase','hspec-execution','--scope','1','--edge',edge],check=True)\nraise SystemExit(17)`);
    assert.equal(result.status, 17, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    const unfinished = phases.intervals.find(row => row.phase === 'compile');
    assert.equal(unfinished.status, 'unfinished');
    assert.equal(unfinished.durationSeconds, null);
    assert.equal(phases.intervals.find(row => row.phase === 'hspec-execution').status, 'failed');
    assert.equal(inspect(output).status, 17);
});

test('malformed phase evidence cannot certify measurement or replace the command exit', (t) => {
    const output = fixture(t);
    const result = run(output, `import os,pathlib\n(pathlib.Path(os.environ['BEPIS_VERIFICATION_EVENTS'])/'000.json').write_text('{"private":"never-echo-this"}')\nraise SystemExit(17)`);
    assert.equal(result.status, 17);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.state, 'invalid');
    assert.equal(phases.invalidEvents, 1);
    assert.equal(JSON.parse(readFileSync(join(output, 'result.json'))).measurementStatus, 'incomplete');
    const checked = inspect(output);
    assert.equal(checked.status, 2);
    assert.doesNotMatch(checked.stdout + checked.stderr, /never-echo-this/);
});

test('phase journal overflow is explicit and cannot silently become complete evidence', (t) => {
    const output = fixture(t);
    const result = run(output, `import subprocess,sys\nbase=[sys.executable,'-S',${JSON.stringify(recorder)},'event','--phase','e2e-worker-startup','--edge','start','--scope']\nfor i in range(256):\n assert subprocess.run(base+[str(65000+i)]).returncode==0\nassert subprocess.run(base+['65535']).returncode==2`, { timeout: 20_000 });
    assert.equal(result.status, 0, result.stderr);
    const phases = JSON.parse(readFileSync(join(output, 'phases.json')));
    assert.equal(phases.state, 'truncated');
    assert.equal(phases.overflow, true);
    assert.equal(phases.intervals.length, 256);
    assert.ok(phases.intervals.every(row => row.durationSeconds === null));
    assert.ok(readFileSync(join(output, 'phases.json')).length <= 65_536);
    assert.equal(inspect(output).status, 2);
});

test('retains failures and launch failures without certifying success', (t) => {
    const output = fixture(t);
    const result = run(output, 'raise SystemExit(17)');
    assert.equal(result.status, 17, result.stderr);
    assert.equal(JSON.parse(readFileSync(join(output, 'result.json'))).commandStatus, 'failed');
    assert.equal(inspect(output).status, 17);
    const missing = fixture(t);
    const launched = spawnSync('python3', [recorder, 'run', '--output', missing,
        '--owner', 'fixture', '--cache-state', 'retained', '--', '/no-such-verification-command'], { encoding: 'utf8' });
    assert.equal(launched.status, 127);
    assert.equal(JSON.parse(readFileSync(join(missing, 'result.json'))).commandStatus, 'launch-failed');
});

test('incomplete, malformed, non-finite and oversized evidence is never accepted', (t) => {
    const output = fixture(t);
    mkdirSync(output);
    writeFileSync(join(output, 'run.json'), '{"state":"running"}');
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), '{');
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), ' '.repeat(70_000));
    assert.equal(inspect(output).status, 2);
    writeFileSync(join(output, 'result.json'), '['.repeat(2000) + ']'.repeat(2000));
    assert.equal(inspect(output).status, 2);
    const good = fixture(t);
    assert.equal(run(good, 'pass').status, 0);
    const path = join(good, 'result.json');
    const evidence = JSON.parse(readFileSync(path));
    for (const invalid of [-1, null, '0', true]) {
        writeFileSync(path, JSON.stringify({ ...evidence, wallSeconds: invalid }));
        assert.equal(inspect(good).status, 2);
    }
    writeFileSync(path, JSON.stringify(evidence).replace(/"wallSeconds":[\d.e+-]+/, '"wallSeconds":NaN'));
    assert.equal(inspect(good).status, 2);
});

test('cannot overwrite an existing run or follow output directory symlinks', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    const before = readFileSync(join(output, 'result.json'), 'utf8');
    assert.equal(run(output, 'raise SystemExit(17)').status, 2);
    assert.equal(readFileSync(join(output, 'result.json'), 'utf8'), before);
    const link = `${output}-link`;
    symlinkSync(output, link);
    assert.equal(run(join(link, 'nested'), 'pass').status, 2);
    assert.equal(existsSync(join(output, 'nested')), false);
});

function start(output, code, extraEnv = {}, options = []) {
    const process = spawn('python3', [recorder, 'run', '--output', output,
        '--owner', 'fixture', '--cache-state', 'retained', ...options, '--', 'python3', '-c', code],
    { env: { ...globalThis.process.env, ...extraEnv }, stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    process.stderr.on('data', (data) => { stderr += data; });
    process.stdout.resume();
    const done = new Promise((resolve, reject) => {
        process.on('error', reject);
        process.on('close', (code, signal) => resolve({ code, signal, stderr }));
    });
    return { process, done };
}
async function waitFor(path) {
    const deadline = Date.now() + 5000;
    while (!existsSync(path)) {
        assert.ok(Date.now() < deadline, `fixture never created ${path}`);
        await new Promise((resolve) => setTimeout(resolve, 20));
    }
}

test('concurrent writers cannot take over the same run directory', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const first = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.5)`);
    t.after(() => first.process.kill('SIGKILL'));
    await waitFor(ready);
    assert.equal(run(output, 'raise SystemExit(17)').status, 2);
    assert.equal((await first.done).code, 0);
    assert.equal(inspect(output).status, 0);
});

test('interruption is retained even when child handles termination as success', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const stopped = `${output}-stopped`;
    const running = start(output, `import signal,time,sys\nfrom pathlib import Path\ndef stop(*_):\n Path(${JSON.stringify(stopped)}).touch()\n sys.exit(0)\nsignal.signal(signal.SIGTERM, stop)\nPath(${JSON.stringify(ready)}).touch()\ntime.sleep(2)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    running.process.kill('SIGTERM');
    const result = await running.done;
    assert.equal(result.code, 143, result.stderr);
    assert.ok(existsSync(stopped));
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.equal(evidence.commandStatus, 'interrupted');
    assert.equal(inspect(output).status, 143);
});

test('metadata work is outside command wall and child CPU measurements', async (t) => {
    const output = fixture(t);
    const bin = `${output}-bin`;
    mkdirSync(bin);
    const git = join(bin, 'git');
    writeFileSync(git, '#!/usr/bin/env python3\nimport time\nend=time.process_time()+0.25\nwhile time.process_time()<end: pass\ntime.sleep(0.25)\nprint("a"*40)\n');
    chmodSync(git, 0o755);
    const started = performance.now();
    const running = start(output, 'import time; time.sleep(0.15)', { PATH: `${bin}:${process.env.PATH}` });
    assert.equal((await running.done).code, 0);
    const elapsed = (performance.now() - started) / 1000;
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    const metadata = JSON.parse(readFileSync(join(output, 'metadata.json')));
    assert.equal(metadata.revision, 'a'.repeat(40));
    assert.ok(elapsed - evidence.wallSeconds >= 0.45, `metadata included in timer: ${elapsed}/${evidence.wallSeconds}`);
    assert.ok(evidence.cpuSeconds < 0.2, `metadata CPU included: ${evidence.cpuSeconds}`);
});

test('samples simultaneous descendant memory and measures CPU of only this command', (t) => {
    const output = fixture(t);
    const result = run(output, 'import subprocess,sys,time\nx=bytearray(24*1024*1024)\np=subprocess.Popen([sys.executable,"-c","import time; x=bytearray(24*1024*1024); time.sleep(0.3)"])\np.wait()');
    assert.equal(result.status, 0, result.stderr);
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.equal(evidence.memory.method, 'sampled-simultaneous-tree-rss');
    assert.ok(evidence.memory.samples >= 1);
    assert.ok(evidence.memory.peakBytes >= 48 * 1024 * 1024, JSON.stringify(evidence.memory));
    assert.ok(evidence.cpuSeconds >= 0 && Number.isFinite(evidence.cpuSeconds));
    assert.equal(evidence.cpuScope, 'waited-command-and-waited-descendants');
});

test('non-overlapping child allocations are not added as historical peak memory', (t) => {
    const output = fixture(t);
    const result = run(output, 'import subprocess,sys\nfor _ in range(2):\n subprocess.run([sys.executable,"-c","import time; x=bytearray(48*1024*1024); time.sleep(0.2)"],check=True)');
    assert.equal(result.status, 0, result.stderr);
    const evidence = JSON.parse(readFileSync(join(output, 'result.json')));
    assert.ok(evidence.memory.peakBytes >= 48 * 1024 * 1024);
    assert.ok(evidence.memory.peakBytes < 100 * 1024 * 1024, JSON.stringify(evidence.memory));
});

test('hard-killed recorder leaves incomplete evidence, never a result', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.3)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    running.process.kill('SIGKILL');
    assert.equal((await running.done).signal, 'SIGKILL');
    assert.equal(existsSync(join(output, 'result.json')), false);
    assert.equal(inspect(output).status, 2);
});

test('publication stays bound to the original directory if its pathname is replaced', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const victim = `${output}-victim`;
    mkdirSync(victim);
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.4)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    renameSync(output, `${output}-original`);
    symlinkSync(victim, output);
    assert.equal((await running.done).code, 2);
    assert.equal(existsSync(join(victim, 'result.json')), false);
});

test('publication cannot overwrite an injected completion file', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const running = start(output, `from pathlib import Path; import time; Path(${JSON.stringify(ready)}).touch(); time.sleep(0.4)`);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    writeFileSync(join(output, 'result.json'), 'foreign result');
    assert.equal((await running.done).code, 2);
    assert.equal(readFileSync(join(output, 'result.json'), 'utf8'), 'foreign result');
});

test('inspection requires bounded valid metadata and lifecycle evidence', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    for (const name of ['metadata.json', 'run.json', 'provenance.json', 'phases.json']) {
        const path = join(output, name);
        const valid = readFileSync(path, 'utf8');
        rmSync(path);
        assert.equal(inspect(output).status, 2);
        for (const invalid of ['{', '{}', ' '.repeat(70_000)]) {
            writeFileSync(path, invalid);
            assert.equal(inspect(output).status, 2);
        }
        writeFileSync(path, valid);
        assert.equal(inspect(output).status, 0);
    }
});

test('termination escalates for an uncooperative command without killing an unrelated process', async (t) => {
    const output = fixture(t);
    const ready = `${output}-ready`;
    const sibling = spawn('python3', ['-c', 'import time; time.sleep(10)'], { stdio: 'ignore' });
    t.after(() => sibling.kill('SIGKILL'));
    const running = start(output, `import signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nPath(${JSON.stringify(ready)}).touch()\ntime.sleep(3)`, {}, ['--termination-grace-seconds', '1']);
    t.after(() => running.process.kill('SIGKILL'));
    await waitFor(ready);
    const before = performance.now();
    running.process.kill('SIGTERM');
    assert.equal((await running.done).code, 143);
    assert.ok(performance.now() - before < 2500);
    assert.equal(sibling.exitCode, null);
    assert.equal(sibling.signalCode, null);
});

test('unknown fields, inconsistent outcomes and malformed resource metrics fail inspection', (t) => {
    const output = fixture(t);
    assert.equal(run(output, 'pass').status, 0);
    const path = join(output, 'result.json');
    const evidence = JSON.parse(readFileSync(path));
    for (const change of [
        { secret: 'not-a-schema-field' }, { commandStatus: 'failed' },
        { commandStatus: 'interrupted', exitCode: 17 },
        { commandStatus: 'launch-failed', exitCode: 1, cpuSeconds: null },
        { cpuSeconds: -1 }, { memory: { ...evidence.memory, peakBytes: '1024' } },
    ]) {
        writeFileSync(path, JSON.stringify({ ...evidence, ...change }));
        const checked = inspect(output);
        assert.equal(checked.status, 2);
        assert.doesNotMatch(checked.stdout, /not-a-schema-field/);
    }
    writeFileSync(path, JSON.stringify(evidence).replace('"exitCode":0', '"exitCode":17,"exitCode":0'));
    assert.equal(inspect(output).status, 2);
});
