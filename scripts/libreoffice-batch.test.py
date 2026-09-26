"""Real Calc formula/save/reopen authority with private miniature XLSX inputs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

OWNER = Path(__file__).resolve().parent.parent / 'Config/nix/scripts/payroll-workbook/libreoffice-recalculate.py'


class CalculatorBatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bepis-calculator-fixture-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def workbook(self, name, formula):
        path = self.root / name
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
            archive.writestr('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
            archive.writestr('xl/workbook.xml', '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Fixture" sheetId="1" r:id="rId1"/></sheets></workbook>')
            archive.writestr('xl/_rels/workbook.xml.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
            cell = '<v>3</v>' if formula is None else f'<f>{formula}</f><v>0</v>'
            archive.writestr('xl/worksheets/sheet1.xml', f'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1">{cell}</c></row></sheetData></worksheet>')
        return str(path)

    def run_owner(self, *arguments, extra=None):
        return subprocess.run(['timeout', '--kill-after=5s', '40s', 'python3', str(OWNER), *arguments],
                              env={**os.environ, **(extra or {})}, capture_output=True, text=True, timeout=47)

    def fault_environment(self, code):
        probe = self.root / 'probe'
        probe.mkdir()
        (probe / 'sitecustomize.py').write_text(code)
        return {'PYTHONPATH': str(probe) + os.pathsep + os.environ.get('PYTHONPATH', '')}

    def test_failure_in_second_document_fails_entire_batch(self):
        first = self.workbook('first.xlsx', '1+2')
        second = self.workbook('second.xlsx', '3*7')
        result = self.run_owner(first, 'Fixture\tA1\t3', '--next', second, 'Fixture\tA1\t23')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.count('LibreOffice formula reconciliation passed'), 1)
        self.assertIn('expected 23.0', result.stderr)

    def test_deadline_is_not_restarted_for_the_next_document(self):
        environment = self.fault_environment('''import builtins, time
real_print, real_clock = builtins.print, time.monotonic
offset = 0
def emit(*args, **keywords):
    global offset
    result = real_print(*args, **keywords)
    if args and str(args[0]).startswith('LibreOffice formula reconciliation passed'):
        offset = 31
    return result
builtins.print = emit
time.monotonic = lambda: real_clock() + offset
''')
        first = self.workbook('first.xlsx', '1+2')
        second = self.workbook('second.xlsx', '3*7')
        result = self.run_owner(first, 'Fixture\tA1\t3', '--next', second, 'Fixture\tA1\t21', extra=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.count('LibreOffice formula reconciliation passed'), 1)
        self.assertEqual(result.stderr.count('loading workbook'), 1)
        self.assertIn('30 second safety deadline', result.stderr)

    def test_failure_between_documents_cannot_become_cleanup_success(self):
        environment = self.fault_environment('''import builtins
real = builtins.print
def emit(*args, **keywords):
    if args and str(args[0]).startswith('LibreOffice formula reconciliation passed'):
        raise RuntimeError('injected between-document failure')
    return real(*args, **keywords)
builtins.print = emit
''')
        result = self.run_owner(self.workbook('first.xlsx', '1+2'), 'Fixture\tA1\t3', '--next', self.workbook('second.xlsx', '3*7'), 'Fixture\tA1\t21', extra=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('injected between-document failure', result.stderr)
        self.assertEqual(result.stderr.count('loading workbook'), 1)

    def test_literal_values_and_invalid_workbooks_cannot_satisfy_formula_authority(self):
        result = self.run_owner(self.workbook('literal.xlsx', None), 'Fixture\tA1\t3')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('is not a formula', result.stderr)
        broken = self.root / 'broken.xlsx'
        with zipfile.ZipFile(broken, 'w') as archive:
            archive.writestr('not-a-workbook.txt', 'invalid fixture')
        result = self.run_owner(str(broken), 'Fixture\tA1\t3')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('LibreOffice formula reconciliation passed', result.stdout)

    def test_corrupted_saved_archive_cannot_pass_reopen_authority(self):
        marker = self.root / 'corruption-injected'
        environment = self.fault_environment(f'''import zipfile
from pathlib import Path
real = zipfile.is_zipfile
def corrupt(path):
    if Path(path).name.startswith('recalculated-'):
        Path(path).write_bytes(b'corrupted private saved workbook')
        Path({str(marker)!r}).touch()
    return real(path)
zipfile.is_zipfile = corrupt
''')
        result = self.run_owner(self.workbook('valid.xlsx', '1+2'), 'Fixture\tA1\t3', extra=environment)
        self.assertTrue(marker.exists())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not save a valid XLSX archive', result.stderr)

    def test_connection_failure_preserves_real_owner_failure(self):
        environment = self.fault_environment('''import subprocess, sys
real = subprocess.Popen
def launch(args, *positional, **keywords):
    if isinstance(args, list) and args[:1] == ['libreoffice']:
        args = [sys.executable, '-c', 'raise SystemExit(17)']
    return real(args, *positional, **keywords)
subprocess.Popen = launch
''')
        result = self.run_owner(self.workbook('valid.xlsx', '1+2'), 'Fixture\tA1\t3', extra=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('child_exit=17', result.stderr)
        self.assertNotIn('LibreOffice formula reconciliation passed', result.stdout)

    def test_hung_owned_startup_is_killed_by_existing_deadline_before_outer_timeout(self):
        marker = self.root / 'hung-child'
        child_code = f'import os,signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path({str(marker)!r}).write_text(str(os.getpid()));time.sleep(60)'
        environment = self.fault_environment(f'''import subprocess, sys
real = subprocess.Popen
def launch(args, *positional, **keywords):
    if isinstance(args, list) and args[:1] == ['libreoffice']:
        args = [sys.executable, '-c', {child_code!r}]
    return real(args, *positional, **keywords)
subprocess.Popen = launch
''')
        result = self.run_owner(self.workbook('valid.xlsx', '1+2'), 'Fixture\tA1\t3', extra=environment)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('30 second safety deadline', result.stderr)
        self.assertTrue(marker.exists())
        self.assertFalse(Path('/proc', marker.read_text()).exists())

    def test_single_cold_start_compatibility_keeps_real_formula_and_reopen(self):
        result = self.run_owner(self.workbook('single.xlsx', '1+2'), 'Fixture\tA1\t3')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('reopening saved XLSX', result.stderr)
        self.assertEqual(result.stdout.count('LibreOffice formula reconciliation passed'), 1)

    def test_two_documents_with_same_cell_names_do_not_contaminate_each_other(self):
        first = self.workbook('first.xlsx', '1+2')
        second = self.workbook('second.xlsx', '3*7')
        before = [Path(path).read_bytes() for path in (first, second)]
        result = self.run_owner(first, 'Fixture\tA1\t3', '--next', second, 'Fixture\tA1\t21')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr.count('connecting'), 1)
        self.assertEqual(result.stderr.count('reopening saved XLSX'), 2)
        self.assertEqual(result.stdout.count('LibreOffice formula reconciliation passed'), 2)
        self.assertEqual([Path(path).read_bytes() for path in (first, second)], before)


if __name__ == '__main__':
    unittest.main()
