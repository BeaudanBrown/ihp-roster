#!/usr/bin/env python3
"""Recalculate selected Payroll Workbook formulas with isolated LibreOffice Calc."""

from __future__ import annotations

import importlib
import math
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from typing import Any, NoReturn


def fail(message: str) -> NoReturn:
    raise RuntimeError(message)


def libreoffice_program_directory() -> Path:
    executable = shutil.which("libreoffice")
    if executable is None:
        fail("libreoffice is unavailable; enter the repository Nix dev shell")
    return Path(executable).resolve().parent


program_directory = libreoffice_program_directory()
os.environ["UNO_PATH"] = str(program_directory)
os.environ["URE_BOOTSTRAP"] = (
    "vnd.sun.star.pathname:" + str(program_directory / "fundamentalrc")
)
sys.path.insert(0, str(program_directory))

try:
    uno: Any = importlib.import_module("uno")  # supplied by pinned LibreOffice
except ImportError as exception:
    fail(f"could not load LibreOffice UNO from {program_directory}: {exception}")


def property_value(name: str, value: object):
    prop = uno.createUnoStruct("com.sun.star.beans.PropertyValue")
    prop.Name = name
    prop.Value = value
    return prop


def unused_tcp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def connect_to_office(port: int):
    local_context = uno.getComponentContext()
    resolver = local_context.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local_context
    )
    connection = (
        f"uno:socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext"
    )
    last_error: Exception | None = None
    for _ in range(100):
        try:
            return resolver.resolve(connection)
        except Exception as exception:  # UNO raises generated exception classes
            last_error = exception
            time.sleep(0.05)
    fail(f"could not connect to isolated LibreOffice: {last_error}")


def parse_expectations(arguments: list[str]) -> list[tuple[str, str, float]]:
    expectations: list[tuple[str, str, float]] = []
    for argument in arguments:
        fields = argument.split("\t")
        if len(fields) != 3:
            fail(f"invalid expectation {argument!r}; expected SHEET<TAB>CELL<TAB>VALUE")
        sheet_name, cell_name, expected_text = fields
        expectations.append((sheet_name, cell_name, float(expected_text)))
    if not expectations:
        fail("at least one formula expectation is required")
    return expectations


def assert_formula_values(document: Any, expectations: list[tuple[str, str, float]], phase: str) -> None:
    sheets = document.getSheets()
    for sheet_name, cell_name, expected in expectations:
        if not sheets.hasByName(sheet_name):
            fail(f"{phase}: missing sheet {sheet_name!r}")
        cell = sheets.getByName(sheet_name).getCellRangeByName(cell_name)
        formula = cell.getFormula()
        if not formula.startswith("="):
            fail(f"{phase}: {sheet_name}!{cell_name} is not a formula: {formula!r}")
        actual = float(cell.getValue())
        if not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=5e-7):
            fail(
                f"{phase}: {sheet_name}!{cell_name} evaluated to {actual!r}, "
                f"expected {expected!r}; formula={formula!r}"
            )


def load_workbook(desktop: Any, path: Path) -> Any:
    return desktop.loadComponentFromURL(
        path.resolve().as_uri(),
        "_blank",
        0,
        (
            property_value("Hidden", True),
            property_value("ReadOnly", False),
            property_value("UpdateDocMode", 3),
        ),
    )


def stop_office(office: subprocess.Popen[str]) -> None:
    if office.poll() is not None:
        return
    try:
        os.killpg(office.pid, signal.SIGTERM)
        office.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(office.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            office.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def main() -> None:
    if len(sys.argv) < 3:
        fail("usage: libreoffice-recalculate.py WORKBOOK EXPECTATION...")
    workbook_path = Path(sys.argv[1])
    if not workbook_path.is_file():
        fail(f"workbook does not exist: {workbook_path}")
    expectations = parse_expectations(sys.argv[2:])

    with tempfile.TemporaryDirectory(prefix="bepis-libreoffice-") as temporary_directory:
        temporary_path = Path(temporary_directory)
        profile_path = temporary_path / "profile"
        home_path = temporary_path / "home"
        home_path.mkdir()
        recalculated_path = temporary_path / "recalculated.xlsx"
        port = unused_tcp_port()
        office_environment = {**os.environ, "HOME": str(home_path)}
        office_environment.pop("UNO_PATH", None)
        office_environment.pop("URE_BOOTSTRAP", None)
        office = subprocess.Popen(
            [
                "libreoffice",
                "--headless",
                "--invisible",
                "--nologo",
                "--nodefault",
                "--nofirststartwizard",
                "--norestore",
                f"-env:UserInstallation={profile_path.resolve().as_uri()}",
                f"--accept=socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=office_environment,
            start_new_session=True,
        )
        watchdog_finished = threading.Event()
        deadline_exceeded = threading.Event()

        def enforce_deadline() -> None:
            if not watchdog_finished.wait(timeout=30):
                deadline_exceeded.set()
                print("libreoffice-recalculate: exceeded 30 second safety deadline", file=sys.stderr, flush=True)
                stop_office(office)

        watchdog = threading.Thread(target=enforce_deadline, daemon=True)
        watchdog.start()
        desktop: Any | None = None
        document: Any | None = None
        reopened_document: Any | None = None
        try:
            print("libreoffice-recalculate: connecting", file=sys.stderr, flush=True)
            context = connect_to_office(port)
            if deadline_exceeded.is_set():
                fail("LibreOffice exceeded the 30 second safety deadline")
            desktop = context.ServiceManager.createInstanceWithContext(
                "com.sun.star.frame.Desktop", context
            )
            print("libreoffice-recalculate: loading workbook", file=sys.stderr, flush=True)
            document = load_workbook(desktop, workbook_path)
            if document is None:
                fail("LibreOffice rejected the generated XLSX workbook")
            document.enableAutomaticCalculation(True)
            document.calculateAll()
            if deadline_exceeded.is_set():
                fail("LibreOffice exceeded the 30 second safety deadline")
            print("libreoffice-recalculate: checking recalculated formulas", file=sys.stderr, flush=True)
            assert_formula_values(document, expectations, "recalculated workbook")
            document.storeAsURL(
                recalculated_path.as_uri(),
                (
                    property_value("FilterName", "Calc MS Excel 2007 XML"),
                    property_value("Overwrite", True),
                ),
            )
            document.close(True)
            document = None

            print("libreoffice-recalculate: reopening saved XLSX", file=sys.stderr, flush=True)
            if not zipfile.is_zipfile(recalculated_path):
                fail("LibreOffice did not save a valid XLSX archive")
            reopened_document = load_workbook(desktop, recalculated_path)
            if deadline_exceeded.is_set():
                fail("LibreOffice exceeded the 30 second safety deadline")
            if reopened_document is None:
                fail("LibreOffice could not reopen its recalculated XLSX workbook")
            assert_formula_values(reopened_document, expectations, "reopened workbook")
            print(
                f"LibreOffice formula reconciliation passed: {len(expectations)} cells "
                f"with {program_directory.parent.parent.name}"
            )
        finally:
            failed = sys.exc_info()[0] is not None
            cleanup_errors: list[str] = []
            try:
                if reopened_document is not None:
                    try:
                        reopened_document.close(True)
                    except Exception as exception:
                        cleanup_errors.append(f"could not close reopened workbook: {exception}")
                if document is not None:
                    try:
                        document.close(True)
                    except Exception as exception:
                        cleanup_errors.append(f"could not close workbook: {exception}")
            finally:
                watchdog_finished.set()
                stop_office(office)
            if failed or cleanup_errors:
                standard_output, standard_error = office.communicate()
                if standard_output:
                    print(standard_output, file=sys.stderr, flush=True)
                if standard_error:
                    print(standard_error, file=sys.stderr, flush=True)
            if cleanup_errors and not failed:
                fail("; ".join(cleanup_errors))


if __name__ == "__main__":
    try:
        main()
    except Exception as exception:
        print(f"libreoffice-recalculate: {exception}", file=sys.stderr)
        raise SystemExit(1)
