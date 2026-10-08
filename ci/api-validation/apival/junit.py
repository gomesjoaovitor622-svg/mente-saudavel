"""Leitura de relatórios JUnit XML (com parser XML seguro contra XXE/billion-laughs)."""

from __future__ import annotations

import os
from collections.abc import Iterable
from dataclasses import dataclass
from xml.etree.ElementTree import Element

from defusedxml import DefusedXmlException
from defusedxml.ElementTree import ParseError, parse

from apival.classification import Category, classify, hints_for
from apival.redaction import redact


@dataclass(frozen=True)
class Totals:
    tests: int = 0
    failures: int = 0
    errors: int = 0
    skipped: int = 0
    time: float = 0.0

    @property
    def passed(self) -> int:
        return max(self.tests - self.failures - self.errors - self.skipped, 0)

    def __add__(self, other: Totals) -> Totals:
        return Totals(
            self.tests + other.tests,
            self.failures + other.failures,
            self.errors + other.errors,
            self.skipped + other.skipped,
            self.time + other.time,
        )


@dataclass(frozen=True)
class Failure:
    test: str
    category: Category
    message: str
    hints: tuple[str, ...] = ()


_EXCERPT_LIMIT = 520


def summarize(text: str, limit: int = _EXCERPT_LIMIT) -> str:
    """Uma linha, sem segredos/PII, com tamanho limitado."""
    one_line = redact(" ".join(text.split()))
    return one_line if len(one_line) <= limit else one_line[: limit - 1] + "…"


def _int(element: Element, name: str) -> int:
    try:
        return int(element.get(name, "0") or 0)
    except ValueError:
        return 0


def _float(element: Element, name: str) -> float:
    try:
        return float(element.get(name, "0") or 0)
    except ValueError:
        return 0.0


def parse_reports(paths: Iterable[str]) -> tuple[Totals, list[Failure]]:
    """Totais e falhas (já classificadas e sanitizadas) de um ou mais relatórios JUnit."""
    totals = Totals()
    failures: list[Failure] = []
    for path in paths:
        try:
            root = parse(path).getroot()
        except (ParseError, DefusedXmlException, OSError):
            failures.append(Failure(os.path.basename(path), Category.OTHER, "relatório JUnit ilegível ou malicioso"))
            continue
        if root is None:
            continue
        for suite in root.iter("testsuite"):
            totals += Totals(
                _int(suite, "tests"),
                _int(suite, "failures"),
                _int(suite, "errors"),
                _int(suite, "skipped"),
                _float(suite, "time"),
            )
        for case in root.iter("testcase"):
            for child in list(case):
                if child.tag not in ("failure", "error"):
                    continue
                raw = f"{child.get('type', '')} {child.get('message', '')}\n{child.text or ''}"
                name = f"{case.get('classname', '')}::{case.get('name', '')}".strip(":")
                failures.append(
                    Failure(name, classify(raw), summarize(child.get("message") or child.text or raw), hints_for(raw))
                )
    return totals, failures
